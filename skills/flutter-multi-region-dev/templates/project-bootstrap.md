# Flutter 多区域项目 Bootstrap 详细模板

> 由 `flutter-multi-region-dev` skill 按需 Read 加载。装项目启动 checklist、milestone DoD、构建命令、决策点表。

## Build Flavor 三分支架构（核心约束）

```
┌──────────────────────────────────────────────────────────────┐
│ 共享代码：lib/  &  server/  （单 codebase）                    │
└──────────────────────────────────────────────────────────────┘
       │                   │                       │
       ▼                   ▼                       ▼
   ┌────────┐       ┌────────────┐         ┌──────────────────┐
   │ iOS    │       │ cn_android │         │ overseas_android │
   │  flavor│       │   flavor   │         │      flavor       │
   ├────────┤       ├────────────┤         ├──────────────────┤
   │ APNs   │       │ JPush      │         │ FCM (Firebase)   │
   │ App    │       │ 微信/支付宝│         │ Google Play      │
   │ Store  │       │ 阿里云Green│         │  Billing         │
   │ IAP    │       │ loli.net   │         │ Perspective /    │
   │        │       │ 字体镜像   │         │  Rekognition     │
   │        │       │            │         │ google CDN 直连  │
   └────────┘       └────────────┘         └──────────────────┘
```

**互斥约束**（详见 SKILL.md 头部）：
- ❌ cn 包不能含 Firebase / Google Services / Google Play Services
- ❌ overseas 包不能含 JPush / 微信 SDK / 支付宝 SDK
- ✅ iOS 包同时支持 firebase_messaging（仅 messaging 部分）+ APNs（双层）
- ✅ 后端单部署，按用户 locale 路由 API（不需要分国内/海外两套）

## 新项目启动 8 步 checklist

### Step 1：项目骨架
```bash
flutter create --org com.<org> <app_name_snake>
cd <app_name_snake>
```

选 `<org>` + `<app_name_snake>`：要让 iOS Bundle ID（`com.<org>.<app>`）和 Android applicationId 在两边都干净。海外 Android applicationId 后续用 `.intl` 后缀。

### Step 2：配 pubspec.yaml + 目录骨架
- 拷 `flutter-coding-conventions` skill 第 2 节技术栈到 `pubspec.yaml`
- 按 `flutter-coding-conventions` skill 第 1 节建 `lib/` 子目录
- 配 `l10n.yaml`，建 `lib/l10n/app_zh.arb` + `app_zh_HK.arb` + `app_en.arb`（最少这三档）

### Step 3：决定 flavor + 抽象工厂

> **Gradle DSL 注意**：`flutter create` 当前默认生成 **Groovy DSL**。本 skill 系列模板用 **Kotlin DSL**（`.kts`），需要在 Step 3 开始时手动迁移：
> ```bash
> mv android/app/build.gradle android/app/build.gradle.kts
> mv android/build.gradle android/build.gradle.kts
> mv android/settings.gradle android/settings.gradle.kts
> ```
> 然后按 KTS 语法改写：`apply plugin: "x"` → `id("x")`、`def` → `val`、字符串只用双引号。

按上面"上架范围"决策，建 flavor 目录（如同时国内 + 海外）：
- `android/app/src/main/AndroidManifest.xml` — 双 flavor 共用 + ICP 备案 application label + 主屏短 activity label
- `android/app/src/cn/AndroidManifest.xml` — JPush meta-data + 排除 Google 权限
- `android/app/src/overseas/AndroidManifest.xml` — FCM meta-data + Google Services
- `android/app/build.gradle.kts` — `flavorDimensions += "market"`，每个 flavor 单独的 manifestPlaceholders

抽象工厂（`lib/core/config/`）：
- `flavor_config.dart`
- `push_service_factory.dart`
- `payment_factory.dart`
- `content_moderation_factory.dart`
- `font_source_factory.dart`

详见 `flutter-coding-conventions` skill 第 18 节。

### Step 4：后端骨架
按 `backend-production-deploy` skill 第 9 节建 `scripts/deploy-backend.sh`。后端只一套（NestJS + Prisma），按用户 locale 路由：
- 中国用户 → 阿里云 Green / Qwen
- 海外用户 → Perspective / Gemini（通过新加坡中转）

### Step 5：i18n 多语言
按 `flutter-coding-conventions` skill 第 9 节配 ARB；最少 3 档：`zh / zh-HK / en`。如海外多语言扩展，加 `ja / ko / fr / de / es / th / ms / ru` 等。

### Step 6：版本号 + Changelog 初始化
- `pubspec.yaml: version: 1.0.0+1`
- 建 `docs/changelog/CHANGELOG.md` + `ios/1.0.0+1.md` + `android/1.0.0+1.md` 骨架
- 写第一版"四件套"模板（参见 `~/.claude/skills/_shared/rules.md` §3）

### Step 7：CLAUDE.md（项目级规范）
本 skill **不**进项目 git。把项目特定信息固化到 `<PROJECT>/CLAUDE.md`：
- 项目名、生产服务器 IP、域名、应用包名
- ICP 备案号、应用名称、版号
- JPush AppKey、APNs Key ID、FCM Project ID
- 产品模块清单（如有）
- 各 skill 引用：`参见 ~/.claude/skills/<name>/SKILL.md`

### Step 8：合规材料骨架（如发布国内市场）
- `docs/compliance/implicit_identifier_spec.md`（隐式标识技术说明文档，参见 `cn-android-flavor` skill `templates/implicit_identifier_spec.md`）
- `docs/legal/privacy.html`（隐私政策，部署到 `<PROD_DOMAIN>/legal/privacy`）
- `docs/legal/terms.html`（用户协议）

## M1-M7 里程碑（按依赖顺序，前置全绿才进下一阶段）

| 里程碑 | 完成判据（DoD） |
|---|---|
| **M1: 工程骨架** | `flutter create` + `pubspec.yaml` 锁版本 + `l10n.yaml` + 版本号 `1.0.0+1` 写入 |
| **M2: Flavor 决策与抽象工厂** | 决定上架范围；`lib/core/config/` 下 push / payment / moderation / font 工厂可编译；不同 flavor `flutter run` 都能跑 |
| **M3: 后端最小可用** | NestJS + Prisma 起来 + `/health` 200 + `scripts/deploy-backend.sh` 在 staging 跑通一次 |
| **M4: i18n 基础** | `lib/l10n/` 三档 ARB（zh / zh-HK / en）+ `AppLocalizations` 生成 + `localizedError` helper |
| **M5: UI 原语** | `ContraToast` / `ContraModal` / `ContraSkeleton` / `WizardExitGuard` / Coach Mark + go_router 全局壳 |
| **M6: 端到端跑通** | 登录页接通后端 → 真机跑通一次 cn APK + iOS IPA + overseas AAB（视上架范围） |
| **M7: 文档纪律就位** | `CLAUDE.md`（项目级）+ 第一版 changelog 四件套 + `docs/compliance/` 骨架（如发国内）|

不要绕过 DoD 进下一里程碑（例如 M2 没跑通 flavor 切换就堆 UI，后续会补一堆 import 错位的坑）。

## 跨 skill 协同点

| 协同点 | 涉及 skill |
|---|---|
| 一次发版双平台同步 buildNumber | `ios-app-store` + `cn-android-flavor` + `overseas-android-google-play` 三方共用 `pubspec.yaml: x.y.z+n` |
| 后端部署影响 changelog 内容（仅当含用户可感知改动）| `backend-production-deploy` + `ios-app-store` |
| ICP 备案名同步 iOS / Android | `~/.claude/skills/_shared/rules.md` §5 |
| `loli.net` 字体镜像（H5 + Flutter Web）| `cn-android-flavor` 第 9 节 |
| 双向 uploads 同步（涉及 H5 静态资源）| `backend-production-deploy` 第 4 节 |
| 隐私字段（IDFV vs Build.id）跨平台一致 | `ios-app-store` 第 6 节 + `cn-android-flavor` 第 12 节 |

## 构建命令速查

```bash
# iOS（含 TestFlight）
./scripts/build_ios_testflight.sh \
  --build-name <x.y.z> \
  --build-number <n> \
  --api-base-url https://<PROD_DOMAIN>

# 国内 Android（cn flavor）
flutter build apk --flavor cn --release \
  --dart-define=BUILD_FLAVOR=cn_android \
  --dart-define=API_BASE_URL=https://<PROD_DOMAIN>

# 国内 Android AAB（小米 / OPPO / vivo 部分市场要求）
flutter build appbundle --flavor cn --release \
  --dart-define=BUILD_FLAVOR=cn_android \
  --dart-define=API_BASE_URL=https://<PROD_DOMAIN>

# 海外 Android（overseas flavor）
flutter build appbundle --flavor overseas --release \
  --dart-define=BUILD_FLAVOR=overseas_android \
  --dart-define=API_BASE_URL=https://<PROD_DOMAIN>
```

## 常见决策点

| 决策点 | 推荐 | 备注 |
|---|---|---|
| 状态管理 | Riverpod | 不混用 Provider / GetX / Bloc |
| 路由 | go_router | 类型安全 + nested |
| 数据类 | Freezed + json_serializable | 跑 `build_runner` 生成 |
| 网络 | Dio | interceptor + 重试 + 进度 |
| 多语言最少集 | `zh / zh-HK / en` | 中国发布的最少要求 |
| iOS 推送 | APNs（直连）+ firebase_messaging（包装）| 不弹 ATT 不集成 IDFA |
| 国内 Android 推送 | JPush 极光 6.x | 排除 Firebase |
| 海外 Android 推送 | FCM | 通过 Firebase Console 配置 |
| 后端部署 | rsync + pm2 + Nginx | 单服务器 + 新加坡 Gemini 中转 |
| 上传文件存储 | local 起步，OSS / S3 切换 | `UPLOAD_STORAGE=oss` env 切 |
| 内容审核（中国）| 阿里云 Green | 三档 block / review / pass |
| 内容审核（海外）| Google Perspective + AWS Rekognition | 按 locale 路由 |
| iOS IAP | Apple StoreKit + `in_app_purchase` | 服务端用 `.p8` JWS 验证 |
| 国内 Android 支付 | fluwx + tobias | 微信开放平台 + 支付宝开放平台 |
| 海外 Android 支付 | Google Play Billing + `in_app_purchase` | service account JSON 验证 |
