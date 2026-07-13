---
name: social-login
description: 多区域第三方登录 — ★ flavor 感知登录方式（cn: 微信/QQ/手机号；overseas: Google/Apple/邮箱；iOS 受 App Store 4.8 约束有三方登录必给 Apple Sign In）、四端客户端接入（sign_in_with_apple / google_sign_in / fluwx / tencent_kit）、★ 后端一律服务端验签（Apple identityToken JWS / Google id_token / 微信 code 换 openid+unionId / QQ access_token 验 openid）、统一账号打通（SocialIdentity 表 + unionId 聚合 + 账号合并策略）、登录后签发 JWT 并解析默认租户。
---

# 多区域第三方登录 Skill

> 覆盖中国（微信/QQ）+ 海外（Apple/Google）+ 手机号/邮箱兜底。所有 `<PLACEHOLDER>` 替换为项目实际值。
>
> **铁律先行**：
> - ★ **一切三方凭证都必须服务端验签**——客户端拿到的 token/code 只是"待验证凭据"，绝不能信客户端自报的 userId / openid。
> - ★ **登录 ≠ 支付**——微信/QQ 的登录和支付是两套 scope / 两套开放平台配置，别混。
> - ★ **登录是 user 级、不是 tenant 级**——一个账号登录后再按既有规则解析默认租户（`~/.claude/skills/_shared/rules.md` §4）。

## 1. ★ Flavor 感知的登录方式矩阵

| flavor | 提供的登录方式 | 禁止 |
|---|---|---|
| **cn_android** | 微信 / QQ / 手机号(短信验证码) | ❌ Apple / Google（国内不可用/无意义） |
| **overseas_android** | Google / Apple(可选) / 邮箱 | ❌ 微信 / QQ（海外无生态 + Play 合规） |
| **iOS** | ★ **Apple Sign In**（见 §7 合规）+ 微信(国区用户) + Google(海外用户) + 手机号/邮箱 | 单包按 region/locale 决定展示哪些 |

**代码层**：登录方式也走工厂（对应 `flutter-coding-conventions` §18），按 flavor + region 返回可用 provider 列表：
```dart
// lib/core/config/auth_provider_factory.dart
List<LoginMethod> availableLoginMethods() {
  final f = FlavorConfig.current;
  switch (f) {
    case Flavor.cnAndroid:      return [LoginMethod.wechat, LoginMethod.qq, LoginMethod.phone];
    case Flavor.overseasAndroid:return [LoginMethod.google, LoginMethod.apple, LoginMethod.email];
    case Flavor.ios:            return _iosMethodsByRegion();  // 见 §7，含 Apple 兜底
  }
}
```
> ★ 顶层禁止直接 import 平台登录包（`google_sign_in` / `tencent_kit`），只在工厂内条件构造，否则 cn 包会打入 Google native lib（对应 `flutter-testing` §6.2 守卫）。

## 2. 统一后端账号模型（一次设计，四端复用）

一个用户可绑定多个第三方身份；用 `SocialIdentity` 表把 provider 身份挂到 `User`：
```prisma
model SocialIdentity {
  id          String   @id @default(uuid())
  userId      String   @map("user_id")
  provider    String                            // apple | google | wechat | qq
  providerUid String   @map("provider_uid")     // Apple sub / Google sub / 微信 openid / QQ openid
  unionId     String?  @map("union_id")         // ★ 微信/QQ 跨应用聚合（开放平台 unionId）
  email       String?
  nickname    String?
  avatarUrl   String?  @map("avatar_url")
  createdAt   DateTime @default(now()) @map("created_at")

  user        User     @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([provider, providerUid])             // ★ 同 provider 同 uid 唯一
  @@index([unionId])                            // 按 unionId 聚合同一自然人
  @@index([userId])
  @@map("social_identities")
}
```
**铁律**：
- ★ `SocialIdentity` 是 **user 级**，不带 tenantId（登录发生在选租户之前）
- ★ `@@unique([provider, providerUid])` 防同一第三方账号被绑到两个 user
- ★ 微信/QQ 优先用 **unionId** 认人（同主体旗下多 app 共享），openid 仅单 app 内唯一

## 3. 统一登录端点契约

```yaml
# POST /api/v1/auth/social-login
Request:
  provider: apple | google | wechat | qq
  # 按 provider 传对应凭据（都由后端验签）：
  identityToken?: string    # apple：客户端 credential.identityToken
  authCode?: string         # apple：授权码（可选，用于换 refresh token）
  nonce?: string            # apple：客户端生成的 raw nonce（防重放）
  idToken?: string          # google：GoogleSignInAuthentication.idToken
  code?: string             # 微信：fluwx 授权返回的 code
  accessToken?: string      # QQ：tencent_kit 返回的 access_token
  openid?: string           # QQ：客户端 openid（仅作 sanity，仍以服务端验为准）
  deviceInfo?: {...}        # 设备指纹（4 台设备限制用）

Response 200:
  token: string             # 本系统 JWT（与账密登录同一套，含默认租户）
  isNewUser: boolean        # true=首次注册，前端可引导设置
  kickedOldDevice?: boolean # 超 4 台踢老设备（对应 frontend-backend-alignment §10）
  needBindPhone?: boolean   # 如业务要求手机号，返回 true 引导补绑

Response 4xx:
  401 SOCIAL_TOKEN_INVALID  # 验签失败
  409 IDENTITY_CONFLICT     # 该第三方已绑其他账号（见 §5 合并策略）
```

## 4. 后端验签（每个 provider 一段，全部服务端做）

### 4.1 Apple Sign In —— 验 identityToken（JWS）
```typescript
// 1. 取 Apple 公钥（https://appleid.apple.com/auth/keys，按 kid 匹配，缓存）
// 2. 用 jose/jsonwebtoken 验签 + 校验 claims
const decoded = await verifyAppleIdToken(identityToken, {
  audience: process.env.APPLE_BUNDLE_ID,          // aud 必须=你的 bundleId
  issuer: 'https://appleid.apple.com',            // iss
  nonce: sha256(rawNonce),                        // ★ 校验 nonce（防重放）
});
// decoded.sub = Apple 稳定用户标识（providerUid）；decoded.email 首次才返回
```
- ★ Apple **email 只在首次授权返回**，必须首次落库；后续登录只有 sub
- ★ nonce：客户端生成 raw nonce，`sign_in_with_apple` 传 `nonce: sha256(raw)`，服务端用 raw 再 sha256 比对

### 4.2 Google Sign In —— 验 id_token
```typescript
import { OAuth2Client } from 'google-auth-library';
const client = new OAuth2Client();
const ticket = await client.verifyIdToken({
  idToken,
  audience: [process.env.GOOGLE_IOS_CLIENT_ID, process.env.GOOGLE_ANDROID_CLIENT_ID],
});
const p = ticket.getPayload();      // p.sub=providerUid, p.email, p.name, p.picture
```
- ★ `audience` 必须是你的 OAuth clientId（防别的 app 的 token 冒用）

### 4.3 微信登录 —— code 换 openid + unionId（服务端持 secret）
```typescript
// 客户端 fluxw 授权(scope: snsapi_userinfo) → 返回 code
// 服务端拿 code 换 token（AppSecret 绝不下发客户端）
const r = await fetch(`https://api.weixin.qq.com/sns/oauth2/access_token`
  + `?appid=${WECHAT_APPID}&secret=${WECHAT_SECRET}&code=${code}&grant_type=authorization_code`);
const { openid, unionid, access_token } = await r.json();
// 可选拉资料：GET /sns/userinfo?access_token&openid → nickname/headimgurl
```
- ★ **AppSecret 只在后端**；换 token 是服务端行为
- ★ 用 `unionid` 认人（需在微信开放平台把 app 绑到同一开放平台账号）

### 4.4 QQ 登录 —— access_token 验 openid + unionId
```typescript
// 客户端 tencent_kit 授权 → access_token（+ 客户端自报 openid，仅 sanity）
// 服务端用 access_token 反查权威 openid/unionid
const r = await fetch(`https://graph.qq.com/oauth2.0/me?access_token=${accessToken}&unionid=1&fmt=json`);
const { openid, unionid } = await r.json();     // 以此为准，不信客户端自报
```

## 5. 账号打通 / 合并策略（登录 upsert 核心逻辑）

```typescript
async socialLogin(provider, verified /* {providerUid, unionId, email, ... } */) {
  // 1. 先按 (provider, providerUid) 找已绑身份
  let identity = await prisma.socialIdentity.findUnique({
    where: { provider_providerUid: { provider, providerUid: verified.providerUid } },
  });
  if (identity) return this.issueJwtForUser(identity.userId);   // 老用户直登

  // 2. 微信/QQ：同 unionId 视为同一自然人 → 复用已有 user，补一条 identity
  if (verified.unionId) {
    const sib = await prisma.socialIdentity.findFirst({ where: { unionId: verified.unionId } });
    if (sib) {
      await prisma.socialIdentity.create({ data: { userId: sib.userId, provider, ...verified } });
      return this.issueJwtForUser(sib.userId);
    }
  }

  // 3. 邮箱撞库：已有同 email 的账密用户 → 走"绑定确认"而非静默合并（防账号劫持）
  if (verified.email) {
    const emailUser = await prisma.user.findUnique({ where: { email: verified.email } });
    if (emailUser) throw new ConflictException({ code: 'IDENTITY_CONFLICT', email: verified.email });
    //   ↑ 前端提示"该邮箱已注册，请先用密码登录后在设置里绑定"，不自动合并
  }

  // 4. 全新用户：建 User + SocialIdentity（事务）
  const user = await prisma.$transaction(async (tx) => {
    const u = await tx.user.create({ data: { email: verified.email, nickname: verified.nickname } });
    await tx.socialIdentity.create({ data: { userId: u.id, provider, ...verified } });
    return u;
  });
  return this.issueJwtForUser(user.id, { isNewUser: true });
}
```
**铁律**：
- ★ **邮箱撞库不静默合并**——返回 409 让用户先用原方式登录再手动绑定，否则伪造 email 的三方 token 可劫持账号
- ★ 微信/QQ 用 unionId 合并；无 unionId（未接开放平台）只能按 openid 单 app 认人
- ★ 建 User 与建 identity 必须**同事务**，避免半条脏数据

## 6. 登录后签发 JWT + 解析默认租户

社交登录成功后走**与账密登录完全相同**的后半程：
```typescript
issueJwtForUser(userId) {
  // 1. 解析默认租户（对应 _shared/rules.md §4 / 项目 tenant 解析优先级）
  const tenantId = resolveDefaultTenant(userId);   // lastSelected → 首个 member → 自己第一个
  // 2. 设备管理（超 4 台踢老，对应 frontend-backend-alignment §10）
  const kickedOldDevice = enforceDeviceLimit(userId, deviceInfo);
  // 3. 签 JWT（payload: sub/tier/tenantId/teamRole）
  const token = this.jwt.sign({ sub: userId, tenantId, ... });
  return { token, kickedOldDevice };
}
```
- ★ 社交登录不特殊化下游——拿到 token 后前端走既有 `switchTenant` / provider 初始化时序

## 7. ★ App Store 4.8 合规（iOS 最容易被拒的点）

**规则**：iOS app 只要提供**任一第三方社交登录**（Google / 微信 / Facebook 等），就**必须**同时提供一个"隐私友好"登录，**Sign in with Apple 满足此要求**。
- ★ iOS 上出现微信/Google 登录按钮 → **必须**也放 Apple Sign In，否则 4.8 拒
- 例外：只用你自己的账号体系（手机号/邮箱），不接任何第三方 → 可不放 Apple
- Apple 登录按钮遵循 HIG：用官方 `SignInWithAppleButton`，尺寸/文案/圆角别自定义过头

```dart
List<LoginMethod> _iosMethodsByRegion() {
  final base = <LoginMethod>[LoginMethod.phone];
  if (isChinaRegion) base.add(LoginMethod.wechat);
  else base.add(LoginMethod.google);
  base.add(LoginMethod.apple);           // ★ 只要上面有三方登录，Apple 必加
  return base;
}
```

## 8. 客户端依赖与最小接入

```yaml
dependencies:
  sign_in_with_apple: ^6.x.x     # Apple（iOS + 海外 Android via web flow）
  google_sign_in: ^6.x.x         # Google（overseas / iOS 海外）
  fluwx: ^4.x.x                  # 微信（登录复用支付同一 SDK，scope 不同）
  tencent_kit: ^5.x.x            # QQ（也支持微信，二选一，别与 fluwx 重复注册）
```
**Apple（含 nonce）**：
```dart
final rawNonce = _generateNonce();
final cred = await SignInWithApple.getAppleIDCredential(
  scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
  nonce: sha256ofString(rawNonce),
);
await api.socialLogin(provider: 'apple', identityToken: cred.identityToken, nonce: rawNonce);
```
**微信**：
```dart
await Fluwx().authBy(which: NormalAuth(scope: 'snsapi_userinfo', state: _csrfState));
// 监听 WeChatAuthResponse → code → 后端换 openid
```
- ★ 各平台需在开放平台/控制台配置：Apple(Service ID + Key)、Google(OAuth clientId per 平台)、微信(移动应用 AppID + 签名)、QQ(移动应用 AppID)

## 9. 安全与隐私铁律

- ★ **一律服务端验签**（§4），客户端自报 uid/openid 只作 sanity
- ★ **Apple nonce / OAuth state**：防重放与 CSRF
- ★ **最小 scope**：只要 openid + email + 昵称头像，别要通讯录/朋友列表
- ★ **AppSecret / Client Secret / .p8 只在后端**，绝不打进客户端
- ★ **PII 上报脱敏**（对应 `observability` §5）：日志别记完整 token / email
- ★ **海外 GDPR**：社交登录也要在隐私政策列明收集的字段 + 提供解绑/注销（对应 `overseas-android-google-play` §11）

## 10. 中国合规要点

- 微信登录需 **微信开放平台"移动应用"审核通过**（非公众号）；unionId 需把 app 绑到同一开放平台账号
- QQ 登录需 **腾讯开放平台"移动应用"**；unionId 同理
- 国内 App 常要求**手机号实名**：社交登录后按业务用 `needBindPhone` 引导补绑手机号（短信验证码）
- ★ 隐私政策必须列明第三方登录 SDK 的信息收集（对应 `cn-android-flavor` §12 隐式标识文档）

## 11. 测试要点（挂进 `flutter-testing`）

- 工厂按 flavor 返回正确登录方式（cn 无 Apple/Google；iOS 有 Apple 兜底）
- 后端验签失败 → 401；伪造 email 撞库 → 409 不合并
- unionId 相同 → 复用同一 user（断言不新建 User）
- 建 User + identity 事务失败 → 无脏数据
- App Store 4.8：iOS 含三方登录时 Apple 按钮存在（widget 测试）

## 12. 自检模板

```
新增/修改登录 provider：
flavor 展示矩阵：（cn / overseas / iOS 各有哪些；iOS 是否含 Apple 兜底）
服务端验签：（Apple JWS / Google id_token / 微信 code换openid / QQ me）— 是否全服务端
账号打通：（unionId 聚合 / 邮箱撞库是否 409 不合并 / 建号是否事务）
JWT 与租户：（是否复用 issueJwtForUser + 默认租户解析）
合规：（iOS 4.8 Apple 兜底 / 隐私政策列明 / secret 是否只在后端）
```

## 参考

- 配套 skill：`ios-app-store`（4.8 合规 / bundleId / .p8）、`cn-android-flavor`（微信/QQ 开放平台 + 隐私文档）、`overseas-android-google-play`（Google OAuth / GDPR）、`nestjs-backend-conventions`（JWT/@CurrentUser/DTO）、`frontend-backend-alignment`（设备踢出/租户解析回传）、`flutter-testing`（验签与工厂测试）、`observability`（登录失败监控 + PII 脱敏）
- 跨 skill 铁律：`~/.claude/skills/_shared/rules.md` §4（登录后租户上下文）
- Sign in with Apple：https://developer.apple.com/sign-in-with-apple/
- 微信开放平台移动应用：https://open.weixin.qq.com/
- Google Identity：https://developers.google.com/identity
