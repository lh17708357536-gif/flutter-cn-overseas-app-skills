# Flutter 中国 + 海外 多平台 App 开发 · Agent Skills

> **一套给 AI 编码助手（Claude Code / Codex / Cursor 等）用的工程规范包**，把"中国市场 + 海外市场、iOS + Android、Flutter 前端 + NestJS 后端"三flavor 全区发布的真实踩坑经验，蒸馏成可被 agent 自动加载的 Skill。
>
> A set of **agent-loadable engineering skills** for building & shipping a Flutter + NestJS app to **both China and overseas markets** (iOS + Android), with three build flavors, distilled from real production experience.

这不是一个"即用框架"，而是一套 **参考骨架 + 铁律清单**。所有代码片段用 `<PLACEHOLDER>` 占位，落地时替换为你的项目值。它的价值在于：让 AI 助手在你开发多区域 App 时，**自动想起那些上架被拒、跨租户越权、切租户 race、积分丢失、cn 包混入 Google 被华为拒** 之类的坑。

---

## 这套东西覆盖什么（诚实版）

这是**一条经过生产验证的精选技术栈**，不是"任你挑供应商的集成大全"。下面如实标注覆盖边界：

### ✅ 已覆盖
- **三 flavor 架构**：iOS（APNs + App Store IAP）/ cn_android（JPush + 微信支付宝 + 阿里云）/ overseas_android（FCM + Play Billing）+ 互斥硬约束（cn 禁 Firebase、overseas 禁 JPush）
- **前端**：Flutter + Riverpod + go_router + Freezed + i18n 多语言 + UI 原语 + 多租户 Provider 重置
- **后端**：NestJS + Prisma + MySQL 多租户铁律 + JWT + Redis + BullMQ + UploadService（本地/OSS）+ 内容审核
- **登录**：Apple / Google / 微信 / QQ 第三方登录 + 服务端验签 + 账号打通 + App Store 4.8 合规
- **支付**：微信支付 / 支付宝（fluwx/tobias）/ Apple IAP（JWS 验签）/ Google Play Billing
- **推送**：极光 JPush（国内）/ FCM（海外）/ APNs（iOS）
- **存储**：阿里云 OSS（UploadService 抽象，可切）
- **合规**：ICP 备案名双 label / 隐式标识技术说明文档 / Privacy Manifest / GDPR·CCPA
- **测试**：单元 / widget / golden / ★flavor 条件编译测试 / 多租户隔离 / 扣费退款
- **CI/CD**：GitHub Actions 三 flavor 矩阵构建 + iOS 签名（fastlane match）+ 产物守卫 + 部署流水线
- **可观测性**：flavor 感知崩溃采集（Sentry）+ 结构化日志 + 健康告警 + PII 脱敏
- **部署**：rsync + PM2 + Nginx 生产 SOP（ask-before-write / dry-run / uploads 双向补齐）

### ❌ 暂未覆盖（Roadmap，欢迎 PR）
- 华为原生 HMS Push（当前走 JPush 厂商通道）
- 腾讯云 COS / AWS S3 的具体实现（仅有 UploadService 抽象层）
- 地图：高德 / Google Maps / Mapbox（按 country 路由——已在参考项目中实践，尚未抽成 skill）
- 海外订阅：Stripe / RevenueCat
- Flutter Web / Desktop 目标
- 微信原生分享（fluwx 支持，尚未单独成文）

> 想要上面某块？开 issue 说需求，或参照现有 skill 的写法提 PR。**每个 skill 都是自洽的单文件规范，容易增补。**

---

## Skill 索引（13 个）

从 **`flutter-multi-region-dev`** 进入——它是路由器，会按你的上架范围告诉 agent 加载哪些子 skill。

| Skill | 用途 |
|---|---|
| **`flutter-multi-region-dev`** | 🚪 **总入口路由器**：上架范围决策 + 子 skill 索引 + bootstrap |
| `flutter-coding-conventions` | Flutter 前端工程规范（Riverpod / Freezed / i18n / UI 原语 / flavor 工厂）|
| `nestjs-backend-conventions` | NestJS 后端规范（分层 / DTO / Prisma 多租户 / JWT / Redis / BullMQ / 审核）|
| `frontend-backend-alignment` | 前后端对齐（字段 / 文档 / 版本 / 扣费 / 租户重置一致性）|
| `backend-production-deploy` | 生产部署 SOP（rsync / uploads 双向补齐 / PM2 / 健康检查）|
| `cn-android-flavor` | 中国 Android（JPush / 微信支付宝 / ICP 备案 / 隐式标识 / ProGuard / aapt）|
| `ios-app-store` | iOS App Store（TestFlight / Privacy Manifest / IAP JWS / APNs / train-closed）|
| `overseas-android-google-play` | 海外 Android（Firebase / Play Billing / GDPR / ProGuard）|
| `social-login` | 第三方登录（Apple / Google / 微信 / QQ + 服务端验签 + 账号打通 + 4.8 合规）|
| `flutter-testing` | 测试规范（Notifier/widget/golden + ★flavor 条件编译测试 + 多租户隔离）|
| `ci-cd-github-actions` | CI/CD（PR 门禁 + ★三 flavor 矩阵 + iOS 签名 + 产物守卫 + 部署）|
| `observability` | 可观测性（崩溃采集 + 结构化日志 + 健康告警 + PII 脱敏）|
| `_shared/rules.md` | 跨 skill 铁律单一真相源（扣费退款 / 持久化反查 / 版本号 / 切租户 / ICP 备案）|

---

## 快速开始（按你的 AI 助手选）

详见 [`docs/INSTALL.md`](docs/INSTALL.md)。摘要：

### Claude Code
```bash
# 复制到用户级 skill 目录，Claude Code 会自动按描述加载
cp -R skills/* ~/.claude/skills/
```
之后在会话里说"新开一个国内+海外的 Flutter App"，Claude 会自动命中 `flutter-multi-region-dev` 路由。

### Codex / 其他读 AGENTS.md 的 agent
本仓库根目录有 [`AGENTS.md`](AGENTS.md)。把本仓库作为上下文（或 clone 进项目），agent 读 `AGENTS.md` 即可拿到路由表与各 skill 路径。

### Cursor / Windsurf / 通用
把 `skills/` 目录纳入项目，或在你的规则文件里指向它。任何 agent 都能直接 **读 `skills/<name>/SKILL.md`**（纯 Markdown，无专有格式）。

> **路径映射注意**：skill 正文里的 `~/.claude/skills/X` 引用，等价于本仓库的 `skills/X`。Claude Code 用户 `cp` 到 `~/.claude/skills/` 后原样解析；其他 agent 按此映射理解即可（`AGENTS.md` 有说明）。

---

## 设计原则

1. **诚实优先**：宁可标"未覆盖"，不假装大全。
2. **铁律集中**：跨 skill 的规则写在 `_shared/rules.md` 单一真相源，子 skill 只补自己特有的接口，不复述。
3. **占位符化**：无任何真实 IP / 域名 / 密钥 / 备案号 / 包名（已脱敏，可放心公开）。
4. **agent 无关**：纯 Markdown + frontmatter，任何读文件的 agent 都能用。

---

## 联系 / Contact

- 问题 / 建议 / 合作：**lh17708357536@gmail.com**
- 也欢迎直接开 [issue](../../issues) 或提 PR。

## License

[MIT](LICENSE) © 2026 haoliu

欢迎 issue / PR。补充新 skill 时请沿用现有格式（frontmatter `name`+`description`、`<PLACEHOLDER>` 占位、铁律引 `_shared/rules.md`、末尾"参考"段）。
