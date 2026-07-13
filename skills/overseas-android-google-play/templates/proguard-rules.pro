# overseas flavor ProGuard / R8 keep 规则模板
#
# 复制到 android/app/proguard-rules.pro。
# Release 构建默认开 R8。Firebase / Play Billing 通过反射加载 metadata，
# 混淆后 token 注册 / 内购回调可能 silent fail（不闪退但功能失效）。Release 必须 keep。

# ===== Flutter 基础 =====
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# ===== Firebase / FCM =====
# Firebase 大部分 keep 由 firebase-messaging AAR 自带 consumer-rules.pro 提供，
# 但 Application 子类、自定义 FirebaseMessagingService 子类必须 keep
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class * extends android.app.Application { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ===== Google Play Billing / in_app_purchase =====
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**
-keep class io.flutter.plugins.inapppurchase.** { *; }

# ===== Gson / 反序列化 model（如使用）=====
-keep class com.google.gson.** { *; }
