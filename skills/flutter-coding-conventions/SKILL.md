---
name: flutter-coding-conventions
description: Flutter 应用通用工程规范 — 目录布局、Riverpod 状态管理、go_router 路由、Freezed 数据类、多租户 Provider 重置、持久化 ID 反查、AI 扣费 try/catch refundWithRetry、i18n 多语言、Coach Mark / WizardExitGuard / Contra UI 原语、buildNumber + Changelog 纪律。
---

# Flutter 工程规范 Skill

> 适用于新建 Flutter + NestJS 项目时的前端工程基线。涵盖目录布局、状态管理、UI 原语、i18n、版本纪律。所有 `<PLACEHOLDER>` 替换为项目实际值。

## 1. 目录约定

```
lib/
├── core/                # 跨业务的通用基础
│   ├── config/          # 环境配置（API base URL / flavor / feature flag）
│   ├── constants/       # 常量（颜色 / 字体 / 语言列表）
│   ├── network/         # Dio interceptors / API client
│   ├── router/          # go_router 配置
│   ├── theme/           # ThemeData
│   ├── utils/           # 工具函数（日期 / 字符串 / locale 归一）
│   └── mixins/          # 共享 mixin（如 CoachMarkMixin / WizardDraftMixin）
├── data/                # 数据层
│   ├── models/          # Freezed model（DTO / VO / 业务实体）
│   ├── repositories/    # Repository 模式（封装多源数据）
│   └── services/        # API service / 本地存储 / 推送 SDK 包装
├── domain/              # 领域层
│   ├── modules/         # 工具模块注册表（业务功能定义）
│   ├── providers/       # Riverpod Provider
│   └── usecases/        # （可选）UseCase 层
├── presentation/        # UI 层
│   ├── screens/         # 页面（按模块分子目录）
│   ├── widgets/         # 共享 widget（如 ContraXxx 原语）
│   └── common/          # 通用 layout
├── l10n/                # 多语言 ARB
│   ├── app_zh.arb
│   ├── app_zh_HK.arb
│   ├── app_en.arb
│   └── ...
├── app.dart             # MaterialApp 入口
└── main.dart            # main() — 初始化、错误处理、Riverpod ProviderScope

assets/
├── fonts/
├── images/
├── icons/
├── lottie/
├── animations/
├── videos/
└── templates/           # 各模块 HTML 模板（用于 webview / 截图导出）
```

## 2. 技术栈

```yaml
dependencies:
  # 状态管理 & 路由
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  go_router: ^14.0.0

  # 数据类
  freezed_annotation: ^2.4.1
  json_annotation: ^4.8.1

  # 网络
  dio: ^5.4.0
  socket_io_client: ^2.0.3+1

  # i18n
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.0

  # UI
  flutter_animate: ^4.5.0
  shimmer: ^3.0.0
  cached_network_image: ^3.3.0

  # 本地存储
  shared_preferences: ^2.2.0

  # 工具
  uuid: ^4.3.0
  package_info_plus: ^8.0.0
  device_info_plus: ^10.1.2

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.4.5
  json_serializable: ^6.7.1
  riverpod_generator: ^2.3.0
```

## 3. 状态管理铁律

- **Riverpod 是唯一状态管理库**（不用 Provider / GetX / Bloc 混用）
- **业务逻辑放 Provider 不放 Widget** — Widget 只 `ref.watch` + 渲染；任何异步 / 业务规则 / API 调用都封到 Notifier 中
- **Freezed + json_serializable 是数据类标准**
- 跑代码生成：`dart run build_runner build --delete-conflicting-outputs`

## 4. 多租户 Provider 重置（"租户切换"模式）

详见 `~/.claude/skills/_shared/rules.md` §4（switchTenant 4 步时序、错误回滚、ConsumerStatefulWidget `ref.listen` 模板、新增按租户缓存 Provider 三方同步清单）。Flutter 项目特有的接入点：
- `lib/domain/providers/tenant_provider.dart`（顶层租户 Notifier）
- `lib/core/network/dio_client.dart` 拦截器读 jwt active 租户
- `docs/specs/tenant_switch_spec.md §3.3` 维护"按租户缓存的 Provider 清单"

## 5. 编辑型页面保存前 race 守卫

详见 `~/.claude/skills/_shared/rules.md` §4 末尾"编辑型页面保存前 race 守卫"模板。

## 6. 持久化 ID 反查模式（防 race）

详见 `~/.claude/skills/_shared/rules.md` §2（典型场景表 + 前端反例正例 + 后端反查模板）。Flutter 端核心规则：长生命周期资源（reserve→consume / 异步任务 / 长会话 / 推送点击）必须用持久化的 `tenantId`，不读 jwt active。

## 7. AI 扣费 try/catch refundWithRetry 双保险

详见 `~/.claude/skills/_shared/rules.md` §1（Dart + TS 双模板 + 边界条件 + 三方同步铁律 + 自检脚本）。Flutter 端落地：
- `lib/data/services/<feature>_api_service.dart` 中 `consume → try → catch → refundCreditsWithRetry → rethrow`
- 新增扣费 action 必须同步 `lib/core/utils/credit_log_label.dart` 的 switch 分支 + ARB 三档 `creditAction<Action>` key

## 8. AI Prompt 注入：Raw 语言码 vs 归一码

**核心规则**：LLM Prompt 中要指定输出语言时，**用 raw `tenant.workingLanguage` 原值**（如 `zh-HK`），**不能**先经业务二元归一（`normalizeBusinessLanguageCode` → `zh`）。

```typescript
// ❌ 错：归一后传 LLM
const lang = normalizeBusinessLanguageCode(workingLang);  // zh-HK → zh
const prompt = `请用 ${getLanguageName(lang)} 输出`;       // 输出"中文"，模型默认简体

// ✅ 对：用 raw code
const langName = getLanguageNameForPrompt(workingLanguage);  // zh-HK → "繁體中文"
const prompt = `请用 ${langName} 输出`;
```

**业务二元分支**（如"中文 vs 英文"切换 UI 文案路径）才用归一后的二元码。

## 9. i18n 规范

**ARB 文件结构**：
- `lib/l10n/app_<locale>.arb`，每个 locale 一个文件
- 模板 locale 在 `l10n.yaml` 配置：
```yaml
arb-dir: lib/l10n
template-arb-file: app_zh.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

**强约束**：
- 所有 UI 文案使用 `AppLocalizations`，禁止硬编码中文
- 修改中文 UI 文案时，**必须**同步更新 `app_zh.arb` + `app_en.arb`（最少双语对齐；如支持更多语言则全量）
- 新增 key 后跑 `flutter gen-l10n`
- 用法：`final l = AppLocalizations.of(context); l.xxx`

**Provider 层无 BuildContext** 时用 `localizedError` helper：
```dart
import 'package:.../core/utils/error_l10n.dart';

throw localizedError('积分不足', 'Insufficient credits');
// 多语言扩展用 localizedErrorMulti
throw localizedErrorMulti({
  'zh': '积分不足',
  'zh-HK': '積分不足',
  'en': 'Insufficient credits',
  'ja': 'クレジット不足',
});
```

**系统语言 / UI 语言 / 工作语言 三档区分**：
- **系统语言**（`Platform.localeName` / iOS Settings / Android Settings）— 用户手机系统的语言
- **UI 语言**（应用内设置 → 语言切换；持久化在 `SharedPreferences app_locale`）— 应用界面文案的语言
- **工作语言**（`tenant.workingLanguage`）— 业务逻辑用，驱动 AI 回复 / TTS / 翻译方向 / 默认生成语言

**业务文本分支**用 `normalizeBusinessLanguageCode()`：
```dart
String normalize(String? code) {
  final n = code?.trim().replaceAll('_', '-').toLowerCase();
  if (n == null || n.isEmpty) return 'zh';
  if (n.startsWith('en')) return 'en';
  if (n.startsWith('zh')) return 'zh';
  return 'zh';   // 默认中文业务分支
}
```

**系统语言映射**（locale 归一）：
- `zh / zh-CN / zh-Hans` → `zh`
- `zh-HK / zh-MO / zh-TW / zh-Hant` → `zh-HK`
- 其他 → `en`

`localeProvider` 持久化完整 locale code：`zh | zh-HK | en | null`

## 10. UI 原语规范（Contra 系列）

> 命名 prefix 项目自定（如 `Contra` / `Wally` / `Acme`）。本规范用 `Contra` 占位。

```dart
// ❌ 禁止
ScaffoldMessenger.of(context).showSnackBar(...)
showDialog(context: ..., builder: (c) => AlertDialog(...))
const CircularProgressIndicator()

// ✅ 用项目原语
ContraToast.success(context, l.commonSaved);
ContraModal.showConfirm(context, title: ..., message: ..., onConfirm: ...);
ContraSkeleton(width: 200, height: 20);
```

**强约束清单**：
- **反馈**：`ContraToast`，禁止 `ScaffoldMessenger.showSnackBar`
- **破坏性确认**：`ContraModal.showConfirm()`，不要 `showDialog + AlertDialog`
- **空状态**：`ContraEmptyState` + 必传 `action` 参数（CTA 按钮）
- **加载状态**：优先 `ContraSkeleton`（骨架屏），禁止裸 `CircularProgressIndicator`
- **≥3 步向导**：`WizardExitGuard` + `WizardDraftMixin`（防止用户中途离开丢失数据）
- **Coach Mark 引导**：`ContraCoachMark` + `CoachMarkMixin`，首次进入自动 + 右上角 `?` 重看
  - 状态存 `SharedPreferences` `coach_mark_${toolId}_done`
- **Service 入口开关**：`GatedSwitch`（不是裸 `SwitchListTile`），前置条件未满足时弹 ConfirmModal 跳转目标配置页
- **页组级提醒**：`DependencyBanner`（如"请先设置位置"）

## 11. buildNumber + Changelog 纪律（双平台共用）

详见 `~/.claude/skills/_shared/rules.md` §3（pubspec/iOS/Android 版本号联动 + 触发判定 + 四件套清单 + 编译前硬性检查）。本 skill 不重述模板。

## 12. Code Style

- **文件**：`snake_case`
- **类**：`PascalCase`
- **常量**：`camelCase` 或 `SCREAMING_SNAKE_CASE`（按项目偏好选一）
- **注释**：中文（如团队全中文）
- **业务逻辑**：放 Provider，不放 Widget
- **避免**：emoji icon（用 `Icons.*` 或 PhosphorIcons）；硬编码中文（用 ARB）；暴露第三方 AI 品牌名（统一用产品名）

## 13. 代码生成

```bash
# 一次性生成
dart run build_runner build --delete-conflicting-outputs

# 监听模式（开发时用）
dart run build_runner watch --delete-conflicting-outputs

# i18n 单独生成
flutter gen-l10n
```

`build_runner` 处理：
- Freezed `*.freezed.dart`
- json_serializable `*.g.dart`
- riverpod_generator（如用 `@riverpod`）

## 14. 调试与日志

```dart
// 前端
debugPrint('[ClassName] 业务上下文 detail');
```

```typescript
// 后端 NestJS
private readonly logger = new Logger(ClassName.name);
this.logger.log(`[methodName] ...`);
this.logger.warn(`[methodName] ...`);
this.logger.error(`[methodName] ${e.message}`, e.stack);
```

**强约束**：
- 异步操作必须有日志，禁止 try/catch 吞掉错误
- 每个 Service / Provider 关键方法：入口 + 出口 + 错误三类日志

## 15. 自检模板（每次完成 task 输出）

```
修改文件：
主要实现：
涉及高风险区域：（Riverpod 状态 / JWT / WebSocket / 异步时序 / API 字段映射 / Prisma 迁移 / 积分 / 品牌 VI / 环境变量 / 文件上传）
验证命令：（curl 或 dart analyze 或 flutter test，无则 N/A）
文档同步：（已更新 / 不涉及）
潜在风险：
```

## 16. 文档同步规范

**强约束**：改了代码必须同步文档。文档过时比没文档更危险。

| 改动类型 | 必须更新文档 |
|---|---|
| 新增/修改 API 端点 | `docs/backend_spec.md` + `docs/api_contracts/` |
| 新增/修改前端页面/组件 | `docs/cards/<tool>.md`（5 章节）|
| 新增/修改数据库表/字段 | `docs/backend_spec.md` 表定义 |
| 新增/修改积分定价 | `docs/credits_pricing.md` |
| 新增/修改工具模块 | `docs/FEATURE_REGISTRY.md` |
| 涉及跨业务协同 | `docs/cross_business_relations.md` |

文档 5 章节：
1. 功能概述
2. UI 组件清单
3. 数据流
4. 文件清单
5. 修改记录（仅保留关键里程碑，≤10 条）

## 17. 中国网络适配（如多市场发布）

参见 `cn-android-flavor` skill 第 9 节。要点：
- Google Fonts → `fonts.loli.net`
- Gemini API → 通过新加坡节点中转
- 自检：`grep -rE "fonts\.googleapis\.com|generativelanguage\.googleapis\.com"` 应无残留

## 18. Build Flavor 三分支架构

如果要同时上架 iOS + 国内 Android + 海外 Android：

```
flavor:
  iOS               # APNs + App Store IAP — 见 ios-app-store skill
  cn_android        # JPush + 微信支付宝 + 阿里云 Green — 见 cn-android-flavor skill
  overseas_android  # FCM + Google Play Billing + Perspective/Rekognition — 见 overseas-android-google-play skill
```

**代码层抽象**：
```
lib/core/config/
├── app_config.dart                  # 基础配置
├── flavor_config.dart               # 读 BUILD_FLAVOR env
├── push_service_factory.dart        # 按 flavor 返回 ApnsPush / JPush / FcmPush 实现
├── payment_factory.dart             # 按 flavor 返回 WechatPay/Alipay / AppStoreIAP / GooglePlayBilling
└── content_moderation_factory.dart  # 按 flavor 返回 AliyunGreen / GooglePerspective / AwsRekognition
```

每个工厂内**条件 import**确保 cn flavor 不引入 Firebase native lib，overseas 不引入 JPush native lib：

```dart
// push_service_factory.dart
import 'flavor_config.dart';

PushService createPushService() {
  final flavor = FlavorConfig.current;
  switch (flavor) {
    case Flavor.ios:
      return ApnsPushService();   // iOS 用 firebase_messaging 包装的 APNs
    case Flavor.cnAndroid:
      return JPushService();      // 仅 cn flavor 编译时存在
    case Flavor.overseasAndroid:
      return FcmPushService();    // 仅 overseas flavor 编译时存在
  }
}
```

**禁止**在 `flavor_config_factory` 之外（如顶层 import）直接 import 平台特定包：
```dart
// ❌ 禁止：顶层 import 会让 cn flavor 也打包 jpush_flutter
import 'package:jpush_flutter/jpush_flutter.dart';

// ✅ 工厂内部根据 flavor 决定 import
```

## 19. 项目启动 checklist

新建 Flutter 项目时按顺序执行：
- [ ] `flutter create --org com.<org> <app_name_snake>`
- [ ] 拷 `analysis_options.yaml` 启用 `flutter_lints`
- [ ] 拷 `lib/` 目录结构骨架
- [ ] `pubspec.yaml` 锁版本（参考第 2 节技术栈）
- [ ] 配置 `l10n.yaml` + 创建 `lib/l10n/app_<locale>.arb`
- [ ] 跑 `dart run build_runner build` 验证代码生成正常
- [ ] 决定多市场上架范围 → 选 1-3 个 skill：`cn-android-flavor` / `ios-app-store` / `overseas-android-google-play`
- [ ] 配置后端 → 参考 `backend-production-deploy` skill
- [ ] 写 `CLAUDE.md` 把项目特定信息固化（IP / 包名 / 备案号 / 模块清单等）

## 参考

- 配套 skill：
  - `backend-production-deploy`（部署 SOP）
  - `ios-app-store`（iOS + buildNumber 纪律）
  - `cn-android-flavor`（中国 Android 发布）
  - `overseas-android-google-play`（海外 Android 发布）
  - `flutter-multi-region-dev`（项目启动总入口）
- Riverpod 文档：https://riverpod.dev/
- go_router：https://pub.dev/packages/go_router
- Freezed：https://pub.dev/packages/freezed
