# AGENTS.md — 给 AI 编码助手的入口

> 本文件是 **agent 无关**的使用说明（Codex、Cursor、Windsurf、Claude Code 及任何会读仓库文件的助手都适用）。核心：这是一套多区域 Flutter + NestJS 工程规范 Skill，**从路由器进，按需读单个 SKILL.md**。

## 这是什么

`skills/` 下有 13 个规范文件，每个是一份自洽的 Markdown（带 `name` / `description` frontmatter）。它们把"中国 + 海外、iOS + Android、Flutter + NestJS 三 flavor 发布"的铁律固化下来，供 agent 在相关任务时加载，避免重复踩坑。

## 怎么用（agent 执行约定）

1. **任何多区域 Flutter/NestJS 任务，先读 `skills/flutter-multi-region-dev/SKILL.md`**（路由器）。它会按"上架范围"告诉你该加载哪些子 skill。
2. **按需读子 skill**，不要一次性全读——按下面路由表挑相关的。
3. **遇到跨 skill 铁律**（扣费退款 / 持久化反查 / 版本号 / 切租户 / ICP 备案），读 `skills/_shared/rules.md`。
4. 所有代码片段是**模板**，`<PLACEHOLDER>` 换成项目实际值；不要把占位符原样写进产物。

## 路由表（任务 → 该读哪个 skill）

| 你要做的事 | 读这个 |
|---|---|
| 新开多区域项目 / 决定上架范围 | `flutter-multi-region-dev` |
| 写 Flutter 前端（状态/路由/UI/i18n） | `flutter-coding-conventions` |
| 写 NestJS 后端（模块/DTO/Prisma/多租户） | `nestjs-backend-conventions` |
| 对齐前后端字段/文档/版本 | `frontend-backend-alignment` |
| 部署后端到生产 | `backend-production-deploy` |
| 打国内 Android 包（JPush/微信/备案） | `cn-android-flavor` |
| 上架 iOS（TestFlight/IAP/隐私） | `ios-app-store` |
| 打海外 Android 包（FCM/Play Billing） | `overseas-android-google-play` |
| 接第三方登录（Apple/Google/微信/QQ） | `social-login` |
| 接地图/定位（高德/Google/Mapbox） | `maps-location` |
| 接对象存储（OSS/COS/S3） | `object-storage` |
| 写测试 / 防 flavor 串味 | `flutter-testing` |
| 配 CI/CD / 三 flavor 矩阵构建 | `ci-cd-github-actions` |
| 接崩溃采集 / 日志 / 监控告警 | `observability` |

## 路径映射（重要）

Skill 正文里出现的 `~/.claude/skills/X` 引用，**等价于本仓库的 `skills/X`**。原因：这套 skill 最初为 Claude Code 编写，其规范安装位置是用户级目录 `~/.claude/skills/`。

- **Claude Code**：`cp -R skills/* ~/.claude/skills/` 后，路径原样解析。
- **其他 agent**：把 `~/.claude/skills/` 读作仓库内 `skills/`。例如 `~/.claude/skills/_shared/rules.md` → `skills/_shared/rules.md`。

## 三条互斥硬约束（最容易被拒/翻车，任何 agent 必须记住）

1. **cn_android 包禁止含 Firebase / Google Play Services**（华为等国内商店审核直接拒）。
2. **overseas_android 包禁止含 JPush / 微信 / 支付宝 SDK**（Google Play 合规）。
3. **iOS 只要有任一第三方登录（微信/Google），必须同时提供 Apple Sign In**（App Store 4.8）。

## 安装细节

见 [`docs/INSTALL.md`](docs/INSTALL.md)（各 agent 的具体接入方式 + 更新方式）。
