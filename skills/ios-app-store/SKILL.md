---
name: ios-app-store
description: iOS App Store 发布工作流 — TestFlight 构建脚本、Info.plist 配置、IDFV/ATT 隐私字段、Privacy Manifest、IAP capability 与服务端 JWS 验证、APNs 推送、TestFlight train-closed 409 应对、隐私营养标签。
---

# iOS App Store 发布 Skill

> 适用于 Flutter iOS 上架 App Store / TestFlight。所有 `<PLACEHOLDER>` 替换为项目实际值。
>
> **跨平台共用规则在 `~/.claude/skills/_shared/rules.md`**：
> - §3 buildNumber + Changelog 三件套（双平台共用）
> - §5 ICP 备案应用名（iOS / Android 共用）
>
> 本 skill 只补充 iOS 特有的内容。

## 1. TestFlight train-closed 409 应对（iOS 独有）

**症状**：上传 IPA 后 Apple Connect 返回：
```
Validation failed (409)
Invalid Pre-Release Train. The train version 'X.Y.Z' is closed for new build submissions
```

**根因**：上一发布（如 1.0.1+19）已在 App Store 上线，App Store Connect 自动**关闭** `1.0.1` 这条 pre-release train，不再接受任何 1.0.1+N build。

**应对**：必须按版本号纪律 patch +1，开新 train：
- `1.0.1+21` → `1.0.2+22`（patch +1，buildNumber 同步 +1）
- `pubspec.yaml`、所有 `docs/changelog/{ios,android}/*.md` 文件名、`CHANGELOG.md` header 全部同步改名/同步号

## 2. `build_ios_testflight.sh` 模板

完整可执行模板见 [`templates/build_ios_testflight.sh.template`](templates/build_ios_testflight.sh.template)。落地步骤：
1. `cp ~/.claude/skills/ios-app-store/templates/build_ios_testflight.sh.template scripts/build_ios_testflight.sh`
2. 替换 `<PROD_API_URL>`
3. `chmod +x scripts/build_ios_testflight.sh`

调用：
```bash
./scripts/build_ios_testflight.sh --build-name 1.0.2 --build-number 22
```

## 3. `pubspec.yaml` Release 默认值

```yaml
name: <app_name_snake>
description: "<App Display Description>"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.10.0
```

**生产口径**：iOS / TestFlight / App Store 生产包默认后端必须固定（不能 fallback 到 localhost / 空值）。`build_ios_testflight.sh` 强制传 `API_BASE_URL`。

## 4. `Info.plist` 关键字段

```xml
<key>CFBundleDisplayName</key>
<string><App 显示名（用户主屏看到的）></string>

<key>CFBundleName</key>
<string><App 短名 ASCII（技术字段，≤16 chars）></string>

<key>CFBundleShortVersionString</key>
<string>$(FLUTTER_BUILD_NAME)</string>

<key>CFBundleVersion</key>
<string>$(FLUTTER_BUILD_NUMBER)</string>

<!-- 隐私权限说明（用到才声明，未用不写） -->
<key>NSCameraUsageDescription</key>
<string>用于扫码、拍照等业务功能</string>

<key>NSMicrophoneUsageDescription</key>
<string>用于语音输入和通话功能</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>用于选择照片上传</string>

<!-- ★ 不使用 IDFA 时禁止声明 NSUserTrackingUsageDescription -->
```

中国区 App Store ICP 备案 → `CFBundleDisplayName` 必须等于备案名，详见 `~/.claude/skills/_shared/rules.md` §5。

## 5. 设备标识（IDFV / ATT）

**只用 IDFV，不用 IDFA**：
- `identifierForVendor` (IDFV) = vendor 级标识，App 卸载即重置，**不需要 ATT 弹窗**
- IDFA = 跨 App 广告追踪标识，**需要 ATT 授权**

如果不用 IDFA：
- `Info.plist` **不写** `NSUserTrackingUsageDescription`
- 隐私营养标签（App Store Connect 后台）**"用于跟踪您的数据"** = "未收集"
- 用户在 iOS Settings → 隐私与安全性 → 跟踪 → 你的 app 应**不出现在列表中**

Flutter 端 IDFV 读取（`device_info_plus`）：
```dart
final ios = await DeviceInfoPlugin().iosInfo;
final stableId = ios.identifierForVendor ?? ios.utsname.machine;
```

## 6. Privacy Manifest（PrivacyInfo.xcprivacy）— 强制项

> 自 2024 年 5 月起，App Store 强制要求 app 主体 + 三方 SDK 都附带 Privacy Manifest。缺失或不一致会触发 ITMS-91053 / ITMS-91056 警告。

**主 manifest 位置**：`ios/Runner/PrivacyInfo.xcprivacy`，并在 Xcode 中将文件加入 Runner target 的 Copy Bundle Resources。

**最小模板**（仅用 IDFV、不跟踪）：见 [`templates/PrivacyInfo.xcprivacy`](templates/PrivacyInfo.xcprivacy)。模板含 4 类常见 Required Reason API 速查（FileTimestamp / UserDefaults / SystemBootTime / DiskSpace + 对应 reason code）。

**SDK manifest 检查**：三方 SDK（fluwx、tobias、firebase、jpush 等）需各自在 framework 内带 `PrivacyInfo.xcprivacy`：
```bash
# 列出 ipa 内所有 PrivacyInfo.xcprivacy
unzip -l build/ios/ipa/<App>.ipa | grep -i 'PrivacyInfo.xcprivacy'
```
主 app + 每个 framework 都应该有一份。少哪个就升级哪个 SDK 到带 manifest 的版本。

**审核警告查阅**：上传后到 App Store Connect → TestFlight → build 详情 → "Apple-issued warnings"，看具体是哪个 SDK / 哪个 API 缺 reason code。

## 7. IAP capability 判定（不要看 entitlements）

> **铁律**：iOS 项目的 `Runner.entitlements` **不会**包含 In-App Purchase 相关的 key（不像 APNs 的 `aps-environment` 或 HealthKit 的 `com.apple.developer.healthkit`）。IAP capability 只在 Apple Developer Portal 的 App ID Capabilities 页面勾选，Provisioning Profile 重生成后即生效。

**禁止**根据 `Runner.entitlements` 不含 `com.apple.InAppPurchase` 就判定 "IAP capability 缺失 / 100% 会被拒"。这是误判。

**正确判定方式**（任选其一）：
1. 询问用户：是否在 Apple Developer Portal 的 App ID 上勾选了 In-App Purchase
2. 或解 ipa 看 embedded mobileprovision：
   ```bash
   unzip -p Runner.ipa Payload/Runner.app/embedded.mobileprovision \
     | security cms -D \
     | grep -A2 Entitlements
   ```
3. 或问用户：TestFlight / Sandbox 是否能跑通购买流程

## 8. IAP 服务端验证（App Store Server API）

> 客户端 `in_app_purchase` 拿到 `JWSRepresentation` 后必须由后端验签，**不能**信客户端自报的 `productId` / `transactionId`。

**.env 配置**：
```
APPLE_ISSUER_ID=<APPLE_ISSUER_ID>           # App Store Connect → Users and Access → Integrations → App Store Server API
APPLE_KEY_ID=<APPLE_KEY_ID>                 # 同页面新建的 Key 的 KEY ID
APPLE_PRIVATE_KEY_PATH=<REMOTE_PROJECT_PATH>/keys/AuthKey_<KEY_ID>.p8
APPLE_BUNDLE_ID=<APP_PACKAGE>               # 例：com.acme.myapp
APPLE_ENVIRONMENT=Production                 # Sandbox（TestFlight）/ Production（正式）
```

**验签流程**（NestJS 模板）：
```typescript
import { AppStoreServerAPIClient, Environment, SignedDataVerifier } from '@apple/app-store-server-library';

const verifier = new SignedDataVerifier(
  appleRootCAs, true, Environment.PRODUCTION, process.env.APPLE_BUNDLE_ID!,
);
const decoded = await verifier.verifyAndDecodeTransaction(jwsRepresentation);
// decoded.productId / .transactionId / .originalTransactionId / .purchaseDate / .expiresDate

// 用 decoded.productId 查 DEFAULT_IAP_PRICING；按 transactionId 幂等入账
// 写 IapTransaction 表（transactionId 唯一索引，防重）
```

**Sandbox vs Production 切换**：
- TestFlight + Sandbox 测试账号 → `APPLE_ENVIRONMENT=Sandbox`
- App Store 正式购买 → `APPLE_ENVIRONMENT=Production`
- 同一台后端可用 environment fallback 策略：先 Production 验，失败时降级 Sandbox 重试

**App Store Server Notifications V2**：
- App Store Connect → App → App Store Server Notifications 配置 webhook URL（`https://<PROD_DOMAIN>/api/v1/payment/apple/webhook`）
- 后端 webhook 收 `SUBSCRIBED / DID_RENEW / DID_FAIL_TO_RENEW / REFUND` 等事件
- webhook 也是 JWS，用同一个 `verifyAndDecodeNotification` 验签

## 9. APNs 推送

**iOS 推送链路**：
- Flutter 端：`firebase_messaging`（如 overseas flavor）或原生 `APNS` token 注册
- 后端：用 Apple JWS（JWT）签 `.p8` key 调 APNs HTTP/2 接口
- `.env`：
```
APPLE_ISSUER_ID=<APPLE_ISSUER_ID>
APPLE_KEY_ID=<APPLE_KEY_ID>
APPLE_PRIVATE_KEY_PATH=<REMOTE_PROJECT_PATH>/keys/AuthKey_<KEY_ID>.p8
APPLE_BUNDLE_ID=<APP_PACKAGE>
APPLE_WEBHOOK_ENVIRONMENT=Sandbox
```

`.p8` 私钥不进 git，单独通过 `rsync --ignore-existing` 推到 `keys/` 目录。

## 10. App Store Connect 上传

**方式 A（推荐）—Transporter**：
1. 打开 macOS App「Transporter」（App Store 免费下载）
2. 把 `build/ios/ipa/<App>.ipa` 拖入
3. 点 **Deliver** 上传

**方式 B—命令行 altool**：
```bash
xcrun altool --upload-app \
  --type ios \
  -f "build/ios/ipa/<App>.ipa" \
  --apiKey <APPLE_API_KEY_ID> \
  --apiIssuer <APPLE_API_ISSUER_ID>
```

上传成功后在 App Store Connect → TestFlight 看 build 状态：
- `Processing`（5-30 分钟）
- `Ready to Submit`（外测开关 + 选择测试组）

## 11. Privacy Nutrition Labels（隐私营养标签）

App Store Connect → My Apps → App Privacy → **Manage**

**最少集（如本 app 只用 IDFV）**：
- "Identifiers" → 是的
  - "User ID" / "Device ID" → ❌ 未收集
  - "Identifier for Vendors" 不在标签选项中（IDFV 不算 trackable）
- "Contact Info" → ❌ 未收集
- "Tracking" → ❌ 未收集（确认无 IDFA）
- 所收集均"链接到您的身份" / "不用于跟踪"

## 12. iOS 商店投放文案模板

**`docs/changelog/ios/<v>.md` 模板**（buildNumber + Changelog 三件套规则在 `_shared/rules.md` §3，本节只是 iOS 商店特有的字数限制 + 文案约定）：

```markdown
# x.y.z+n · iOS（App Store / TestFlight）

> 字数限制：≤ 4000 字符（App Store What's New）。
> 禁止内部编号；禁止第三方 AI 品牌名（统一产品名）；动词开头，每条 1 句话。

## 中文（zh-Hans / zh-Hant 投放）
- 新增：[功能名] [一句话价值]
- 优化：[XX] [改进点]
- 修复：[XX] [问题]

## English (en + global locales)
- New: [feature] [value]
- Improved: [thing] [improvement]
- Fixed: [thing] [issue]
```

`CHANGELOG.md` 总索引格式见 `_shared/rules.md` §3。

## 13. iOS 隐私政策 v1.x 升级流程

新版隐私政策上线（如 v1.0 → v1.1）时：
1. App 启动检测当前用户已同意的版本号 < 服务端最新版本号
2. 弹「隐私政策升级」弹窗，用户必须重新同意
3. 服务端记录 `userPrivacyConsentVersion`、`consentTimestamp`
4. Changelog 写一句"优化：隐私政策升级到 vX.X，已同意旧版的用户会重新确认。"

## 14. 审核拒绝常见原因清单

| 原因 | 应对 |
|---|---|
| **2.1 Performance: App Completeness** | App Store 测试时 crash → 本地用 `flutter run --release` 测真机 + Sentry/Crashlytics 看堆栈 |
| **4.0 Design** | 截图 / 描述与实际功能不符 → App Store Connect 后台更新 screenshots |
| **5.1.1 Data Collection and Storage** | 隐私政策链接失效 / 与 nutrition label 不一致 → 检查 `docs/legal/privacy.html` 部署状态 |
| **5.1.2 Data Use and Sharing** | 用了 IDFA 但没声明 ATT → 要么去掉 IDFA、要么写 `NSUserTrackingUsageDescription` 并实现 ATT 弹窗 |
| **3.2.1 Acceptable Business Model** | 内购未实现 / 有 IAP 入口但未走 Apple IAP → 用 `in_app_purchase` 走 StoreKit。**不要**仅看 `Runner.entitlements` 没有 IAP key 就判定 capability 缺失，详见第 7 节 |
| **2.5.1 Software Requirements** | 用了私有 API → 用 `xcrun otool -L` 检查 framework 引用 |

## 15. 中国区 ICP 备案专属要求

提交 App Store **中国区 (CN)** 必须提供：
- ICP 备案号（如 `<ICP_FILING_NUMBER>`）
- 备案 App 名称必须与 `CFBundleDisplayName` 一致（详见 `_shared/rules.md` §5）
- App Store Connect → App Information → "China Mainland" 区域填 ICP 信息
- 工信部备案的 App 名称、版号一致；版号变化时需在工信部更新备案

## 参考

- 配套 skill：`backend-production-deploy`（APNs `.env`）、`flutter-coding-conventions`（buildNumber 纪律双平台共用）、`cn-android-flavor`（备案名同步）、`overseas-android-google-play`（海外用 FCM 而非 APNs）
- App Store Review Guidelines：https://developer.apple.com/app-store/review/guidelines/
- Privacy Nutrition Label 文档：https://developer.apple.com/app-store/app-privacy-details/
