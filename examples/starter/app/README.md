# starter_app — 三 Flavor Flutter 骨架

演示"中国 / 海外 / iOS 三 flavor 架构 + 工厂条件加载"的**最小可跑 starter**。
推送用 stub 打桩，**无需任何密钥即可编译运行**——它演示的是架构，不是接真 SDK。

## 它演示了什么

- `lib/core/config/flavor_config.dart` — 用 `--dart-define=BUILD_FLAVOR` 解析当前 flavor
- `lib/core/config/push_service_factory.dart` — 按 flavor 返回 JPush/FCM/APNs（stub），全枚举无 default；顶层禁止 import 平台包（防「串味」）
- `lib/data/services/health_api.dart` — 调后端 `/api/v1/health`
- `android/app/build.gradle.kts` — `market` 维度下 cn / overseas 两个 flavor（overseas 用 `.intl` 包名隔离）
- `test/widget_test.dart` — 首页冒烟测试

## 运行

先起后端（见 `../server/README.md`，端口 3007），再跑前端：

```bash
flutter pub get

# 中国 flavor
flutter run --flavor cn       --dart-define=BUILD_FLAVOR=cn_android

# 海外 flavor
flutter run --flavor overseas --dart-define=BUILD_FLAVOR=overseas_android

# iOS（无需 android flavor）
flutter run                   --dart-define=BUILD_FLAVOR=ios
```

### 后端地址
- Android 模拟器访问宿主机本地后端用固定地址 `http://10.0.2.2:3007`（已是默认值）
- 真机 / 其它环境用 `--dart-define=API_BASE_URL=http://<你的IP>:3007` 覆盖

## 验证

```bash
flutter analyze     # 应 0 error 0 warning
flutter test        # 冒烟测试通过
```

## 延伸

- 架构与工厂模式：`skills/flutter-coding-conventions` §18
- 上架范围决策与总路由：`skills/flutter-multi-region-dev`
- 接真实 JPush：`skills/cn-android-flavor`；接真实 FCM：`skills/overseas-android-google-play`
- 防 flavor 串味的测试：`skills/flutter-testing` §6
