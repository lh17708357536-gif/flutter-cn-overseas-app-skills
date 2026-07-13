---
name: flutter-multi-region-dev
description: Flutter 全区开发总入口路由器 — 启动新的多市场（中国 + 海外 + iOS）Flutter + NestJS 项目时优先调用。按上架范围决定加载哪些子 skill：backend-production-deploy / flutter-coding-conventions / nestjs-backend-conventions / frontend-backend-alignment / cn-android-flavor / ios-app-store / overseas-android-google-play。
---

# Flutter 全区开发 — 路由入口

> 触发场景：用户说"新开 Flutter 项目"、"做一个酒店 / SaaS / 工具型 app"、"要上架国内 + 海外"、"Flutter + NestJS 全栈"。本 skill 是**路由器**，详细 bootstrap 步骤在 `templates/project-bootstrap.md`。

## 一、上架范围决策（5 分钟决策）

新项目第一步必问用户：**目标市场是哪些**？按下表决定加载哪些 skill：

| 场景 | 引用的 skill |
|---|---|
| 仅 iOS — **不发**中国区 App Store | `ios-app-store` + `flutter-coding-conventions` + `backend-production-deploy` |
| 仅 iOS — **发**中国区 App Store | 同上 + `cn-android-flavor` 第 4、12 节（ICP 备案名 + 隐式标识合规文档同样适用 iOS）|
| 仅国内 Android（不含 iOS / 海外）| `cn-android-flavor` + `flutter-coding-conventions` + `backend-production-deploy` |
| 仅海外 Android（Google Play）| `overseas-android-google-play` + `flutter-coding-conventions` + `backend-production-deploy` |
| **全区**（iOS + 国内 Android + 海外 Android）| 全部 7 个 skill |

> **注意**：iOS 应用如果上架中国区 App Store，依然受工信部 ICP 备案约束 — `CFBundleDisplayName` 必须等于备案名（详见 `~/.claude/skills/_shared/rules.md` §5）。

> **三个横切 skill 不分市场，任何上架范围都建议加载**：`flutter-testing`（测试规范 + flavor 条件编译测试）、`ci-cd-github-actions`（三 flavor 矩阵构建 + 部署流水线）、`observability`（崩溃采集 + 结构化日志 + 健康告警）。

## 二、三 flavor 互斥硬约束

| 约束 | 详情 |
|---|---|
| ❌ cn 包不能含 Firebase / Google Services / Google Play Services | 详见 `cn-android-flavor` skill |
| ❌ overseas 包不能含 JPush / 微信 SDK / 支付宝 SDK | 详见 `overseas-android-google-play` skill |
| ✅ 后端单部署，按用户 locale 路由 API | 不需要分国内/海外两套 |

## 三、子 skill 索引

| Skill | 用途 |
|---|---|
| `backend-production-deploy` | NestJS + Prisma 部署 SOP（rsync / uploads / pm2 restart / 健康检查）|
| `flutter-coding-conventions` | Flutter 前端工程规范（Riverpod / 多租户 / i18n / UI 原语）|
| `nestjs-backend-conventions` | NestJS 后端规范（分层 / DTO / Prisma 多租户 / Wave 流程 / Redis / BullMQ / 内容审核）|
| `frontend-backend-alignment` | 前后端对齐（API 字段 / 文档同步 / 跨业务协同）|
| `cn-android-flavor` | 中国 Android（JPush / 微信支付宝 / ICP 备案 / 隐式标识合规文档）|
| `ios-app-store` | iOS App Store（TestFlight / IDFV / Privacy Manifest / IAP 服务端验证）|
| `overseas-android-google-play` | 海外 Android（Firebase / Play Billing / GDPR / ProGuard）|
| `social-login` | 第三方登录（Apple / Google / 微信 / QQ）flavor 感知 + 服务端验签 + 账号打通 + App Store 4.8 合规 |
| `flutter-testing` | 测试规范（Notifier/widget/golden + ★flavor 条件编译测试 + 多租户隔离 + 扣费退款）|
| `ci-cd-github-actions` | CI/CD（PR 门禁 + ★三 flavor 矩阵构建 + iOS 签名 + 产物守卫 + 部署流水线）|
| `observability` | 可观测性（flavor 感知崩溃采集 + 结构化日志 + 健康告警 + PII 脱敏）|

## 四、跨 skill 共享规则（防止重复）

以下铁律在 `~/.claude/skills/_shared/rules.md` 中作为唯一真相源：

- §1 AI 扣费 try/catch refundWithRetry 双保险
- §2 持久化 ID 反查（防 reserve→consume race）
- §3 buildNumber + Changelog 三件套
- §4 多租户 Provider 重置时序（switchTenant）
- §5 ICP 备案应用名 / 双 label

子 skill 中遇到这些主题时只补充本 skill 特有的接口签名/路径，不复述模板。

## 五、详细 bootstrap

新项目从 0 启动时，按 `templates/project-bootstrap.md` 执行 8 步 + 7 个里程碑（M1-M7）。本 SKILL.md 仅做路由决策；具体 milestone DoD、构建命令、决策点表都在 templates 文件里。

> 一句话总结：**全区 = 三 flavor + 一后端 + 7 个子 skill**。本 skill 是路由表；要细节去 templates/ 或对应子 skill。
