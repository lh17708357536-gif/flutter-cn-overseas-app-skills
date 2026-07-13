import 'package:flutter/foundation.dart';

/// 三个发布 Flavor：
/// - cnAndroid：中国大陆安卓（华为/小米/OPPO/vivo/应用宝），推送用极光 JPush
/// - overseasAndroid：海外安卓（Google Play），推送用 Firebase FCM
/// - ios：iOS（App Store），推送用 APNs
enum Flavor { cnAndroid, overseasAndroid, ios }

/// Flavor 配置中心。
///
/// current 由编译期 `--dart-define=BUILD_FLAVOR=xxx` 决定：
///   - `cn_android`      → Flavor.cnAndroid
///   - `overseas_android`→ Flavor.overseasAndroid
///   - `ios`             → Flavor.ios
/// 未传或无法识别时默认回落到 cnAndroid，保证本地开发可直接跑。
class FlavorConfig {
  FlavorConfig._();

  /// 测试期可覆盖的当前 Flavor（仅用于单测）。
  static Flavor? _testOverride;

  /// 编译期注入的原始 Flavor 字符串。
  static const String _rawFlavor =
      String.fromEnvironment('BUILD_FLAVOR', defaultValue: 'cn_android');

  /// 当前 Flavor。
  static Flavor get current {
    if (_testOverride != null) return _testOverride!;
    switch (_rawFlavor) {
      case 'overseas_android':
        return Flavor.overseasAndroid;
      case 'ios':
        return Flavor.ios;
      case 'cn_android':
      default:
        return Flavor.cnAndroid;
    }
  }

  /// 后端 API 基址。
  ///
  /// 默认 `http://10.0.2.2:3007`：安卓模拟器访问宿主机本地后端的固定地址。
  /// 真机 / 生产用 `--dart-define=API_BASE_URL=http://<你的IP>:3007` 覆盖。
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3007');

  /// 仅供测试：临时覆盖当前 Flavor，用完请调用 [resetTestOverride] 还原。
  @visibleForTesting
  static void overrideForTest(Flavor flavor) {
    _testOverride = flavor;
  }

  /// 仅供测试：清除覆盖，还原为编译期解析值。
  @visibleForTesting
  static void resetTestOverride() {
    _testOverride = null;
  }
}
