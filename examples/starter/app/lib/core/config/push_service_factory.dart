import 'package:flutter/foundation.dart';

import 'flavor_config.dart';

/// 推送服务工厂 —— 演示"按 Flavor 条件加载不同推送实现"的架构骨架。
///
/// ⚠️ 本 starter 只做架构演示，三个实现都是 **stub（打桩）**，不引入任何真实 SDK，
/// 因此无需任何密钥即可编译运行。真实接入方式：
///   - 中国大陆（JPush 极光推送）：见 skills/cn-android-flavor
///   - 海外（Firebase FCM）：见 skills/overseas-android-google-play
///
/// ★ 铁律：禁止在本文件顶层 `import` 任何平台推送包
///   （如 `package:jpush_flutter/...` 或 `package:firebase_messaging/...`）。
///   顶层 import 会把该 SDK 打进所有 Flavor 的产物，导致「串味」：
///   中国包混入 Firebase（华为审核拒），海外包混入 JPush。
///   真实项目里应把各实现拆到独立文件，仅在 flavor 判定成立后再 import。
abstract class PushService {
  /// 供应商名称，用于 UI 展示与日志。
  String get providerName;

  /// 初始化推送（注册、申请权限、拿 token 等）。
  Future<void> init();
}

/// 中国大陆：极光 JPush（stub）。
class JPushStub implements PushService {
  @override
  String get providerName => 'JPush(cn)';

  @override
  Future<void> init() async {
    // 真实实现见 skills/cn-android-flavor（注册 JPush AppKey、监听等）。
    debugPrint('[JPushStub] init() 打桩调用，未接入真实 JPush SDK');
  }
}

/// 海外：Firebase Cloud Messaging（stub）。
class FcmStub implements PushService {
  @override
  String get providerName => 'FCM(overseas)';

  @override
  Future<void> init() async {
    // 真实实现见 skills/overseas-android-google-play（google-services.json + FCM）。
    debugPrint('[FcmStub] init() 打桩调用，未接入真实 Firebase SDK');
  }
}

/// iOS：Apple Push Notification service（stub）。
class ApnsStub implements PushService {
  @override
  String get providerName => 'APNs(ios)';

  @override
  Future<void> init() async {
    // 真实实现走原生 APNs（可配合 Firebase 或直连），此处仅打桩。
    debugPrint('[ApnsStub] init() 打桩调用，未接入真实 APNs');
  }
}

/// 按当前 Flavor 返回对应推送实现（全枚举覆盖，无 default 兜底）。
PushService createPushService() {
  switch (FlavorConfig.current) {
    case Flavor.cnAndroid:
      return JPushStub();
    case Flavor.overseasAndroid:
      return FcmStub();
    case Flavor.ios:
      return ApnsStub();
  }
}
