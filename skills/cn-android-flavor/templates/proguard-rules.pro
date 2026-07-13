# cn flavor ProGuard / R8 keep 规则模板
#
# 复制到 android/app/proguard-rules.pro。
# Release 构建默认开 R8 minify + obfuscate；JPush / fluwx / tobias 都用反射注册原生 callback，
# 混淆后类名变了 → 启动闪退 / 推送收不到 / 支付回调丢失。Release 必须 keep。

# ===== Flutter 基础 =====
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.embedding.** { *; }

# ===== JPush 极光推送 =====
-keep class cn.jpush.** { *; }
-keep class cn.jiguang.** { *; }
-dontwarn cn.jpush.**
-dontwarn cn.jiguang.**
# 用户自定义的 JPushReceiver 子类也要 keep
-keep class * extends cn.jpush.android.service.JPushMessageReceiver { *; }

# ===== 微信 fluwx =====
-keep class com.tencent.mm.opensdk.** { *; }
-keep class com.tencent.wxop.** { *; }
-keep class com.tencent.mm.sdk.** { *; }
-dontwarn com.tencent.mm.opensdk.**
# WXEntryActivity / WXPayEntryActivity 必须 keep
-keep class **.wxapi.** { *; }

# ===== 支付宝 tobias =====
-keep class com.alipay.** { *; }
-keep class com.ta.utdid2.** { *; }
-keep class com.ut.device.** { *; }
-dontwarn com.alipay.**
-dontwarn com.ta.utdid2.**

# ===== 阿里云 Green（如客户端有 SDK 调用，一般后端走，这条按需）=====
-keep class com.aliyun.** { *; }
-dontwarn com.aliyun.**

# ===== Gson / 反序列化 model（如使用）=====
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
