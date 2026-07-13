---
name: overseas-android-google-play
description: 海外 Google Play Android Flavor — Firebase / FCM 推送、Google Play Billing 内购、海外内容审核（Perspective / AWS Rekognition）、`google-services.json` 隔离、`.intl` 包名后缀。**禁止包含 JPush / 微信支付宝等中国市场 SDK**。
---

# 海外 Android（Google Play）发布 Skill

> 适用于 Flutter 应用同时上架国内与海外市场时，**海外**这条独立分支。所有 `<PLACEHOLDER>` 替换为项目实际值。

## 1. 硬约束（不可违反）

- ❌ **海外 flavor 禁止包含 JPush** — 海外用户接收不到 JPush，且部分海外市场（特别是 Google Play）合规审核会拦截不必要的中国推送 SDK
- ❌ **海外 flavor 禁止包含 WeChat / Alipay SDK** — Google Play 不接受未经合规审查的中国支付 SDK
- ❌ **海外 flavor 禁止指向中国本地 CDN（loli.net 等）** — 中国镜像在海外速度慢、可能被海外审计标为"可疑"
- ✅ **海外 flavor 必须包含 Firebase / FCM** — Google Play 上架对推送链路的合规默认方案
- ✅ **applicationId 必须有 `.intl` 后缀**（或类似），与国内包名隔离，避免商店冲突

## 2. `build.gradle.kts` flavor 模板

> **前提**：`flutter create` 默认生成 Groovy DSL（`build.gradle`），本节模板是 Kotlin DSL。如果项目还没迁，先 `mv build.gradle build.gradle.kts` 并按 KTS 语法改写。详见 `flutter-multi-region-dev` skill 第三节 Step 3 的 DSL 提示。

```kotlin
android {
    flavorDimensions += "market"
    productFlavors {
        create("cn") {
            // 国内 flavor 详见 cn-android-flavor skill
        }
        create("overseas") {
            dimension = "market"
            applicationId = "<APP_PACKAGE>.intl"   // 例：com.acme.myapp.intl
            manifestPlaceholders["MARKET"] = "overseas"
            // Flutter 插件清单仍可能解析这些 placeholder；海外包运行时不初始化 JPush
            manifestPlaceholders["JPUSH_PKGNAME"] = applicationId as Any
            manifestPlaceholders["JPUSH_APPKEY"] = "DISABLED_FOR_OVERSEAS"
            manifestPlaceholders["JPUSH_CHANNEL"] = "overseas"
        }
    }
}
```

## 3. 目录隔离

```
android/app/src/
├── main/                      # 双 flavor 共用源码与 manifest
├── cn/
│   ├── AndroidManifest.xml    # JPush meta-data 等中国相关
│   └── ... (cn 专属 Java/Kotlin)
└── overseas/
    ├── AndroidManifest.xml     # FCM meta-data
    ├── google-services.json    # ★ Firebase 配置文件，仅 overseas 编译时打包
    └── ... (overseas 专属 Java/Kotlin)
```

## 4. Firebase / FCM 集成

**`pubspec.yaml`**：
```yaml
dependencies:
  firebase_core: ^3.x.x
  firebase_messaging: ^15.x.x
```

**`android/app/build.gradle.kts`**：
```kotlin
dependencies {
    // 仅 overseas flavor 编译时引入 Firebase；cn flavor 自动排除
    add("overseasImplementation", "com.google.firebase:firebase-bom:33.x.x")
    add("overseasImplementation", "com.google.firebase:firebase-messaging")
}
```

**`google-services.json`** 放 `android/app/src/overseas/google-services.json`，cn flavor 不会读取。

**Flutter 端**：
```dart
// 启动时按 flavor 决定是否初始化 Firebase
const buildFlavor = String.fromEnvironment('BUILD_FLAVOR');
if (buildFlavor == 'overseas_android' || buildFlavor == 'ios') {
  await Firebase.initializeApp(/* options */);
  final fcmToken = await FirebaseMessaging.instance.getToken();
}
```

**后端**：
```
.env (overseas section):
FCM_PROJECT_ID=<FIREBASE_PROJECT_ID>
FCM_PRIVATE_KEY_PATH=<REMOTE_PROJECT_PATH>/keys/firebase-admin-sdk.json
```

后端用 firebase-admin Node SDK（或 google-auth + HTTP/2）发推送。

## 5. Google Play Billing 内购

**`pubspec.yaml`**：
```yaml
dependencies:
  in_app_purchase: ^3.x.x
```

**`AndroidManifest.xml`**：
```xml
<uses-permission android:name="com.android.vending.BILLING" />
```

**Flutter 端**：
```dart
final products = await InAppPurchase.instance.queryProductDetails({'pro_monthly_v1'});
final purchaseParam = PurchaseParam(productDetails: products.productDetails.first);
await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
```

**后端验证**：用 Google Play Developer API 验证 purchaseToken。`.env`：
```
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=<REMOTE_PROJECT_PATH>/keys/play-developer.json
```

订阅 / IAP 收据验证流程：
1. 客户端拿到 `purchaseToken`
2. POST 给后端 `/api/v1/payment/google/verify`
3. 后端用 service account 调 `purchases.subscriptionsv2.get` / `purchases.products.get`
4. 校验 productId / purchaseState / orderId 一致后入账

## 6. 海外内容审核

国内用阿里云 Green，海外可选：

| 服务 | 适用 | 备注 |
|---|---|---|
| **Google Perspective API** | 文本毒性检测（评论 / 聊天） | 免费层 1 QPS |
| **AWS Rekognition** | 图像审核（NSFW / 暴力 / 文字识别） | 按调用次数计费 |
| **Cloudflare Workers AI** | 文本 + 图像，低延迟 | 较新，覆盖度看具体模型 |

**按 locale 路由**：
```typescript
async function moderateText(text: string, locale: string): Promise<ModerationResult> {
  if (locale.startsWith('zh') || locale === 'zh-HK') {
    return aliyunGreenService.moderate(text);
  } else {
    return perspectiveService.moderate(text);
  }
}
```

## 7. 后端配置（共用同一台后端）

后端用国内服务器 + 通过新加坡节点中转 Google API：
- 国内主服务器跑业务逻辑
- 海外 Google 服务（Gemini / Firebase / Translate）通过新加坡节点 Nginx 8443 → `generativelanguage.googleapis.com` 中转
- 后端不分国内/海外两套，按用户 locale 路由 API 调用

`.env`：
```
GEMINI_BASE_URL=https://<SINGAPORE_PROXY>/v1beta
FCM_PROJECT_ID=<FIREBASE_PROJECT_ID>
```

## 8. 构建命令

```bash
# 海外 Android（推 Google Play 推荐用 appbundle）
flutter build appbundle \
  --flavor overseas \
  --release \
  --dart-define=BUILD_FLAVOR=overseas_android \
  --dart-define=API_BASE_URL=<PROD_API_URL>

# 输出：build/app/outputs/bundle/overseasRelease/app-overseas-release.aab
```

或 APK（侧载 / 海外其他商店）：
```bash
flutter build apk \
  --flavor overseas \
  --release \
  --dart-define=BUILD_FLAVOR=overseas_android \
  --dart-define=API_BASE_URL=<PROD_API_URL>
```

## 8.5 ProGuard / R8 混淆规则

> Release 构建默认开 R8。Firebase / Play Billing 通过反射加载 metadata，混淆后 token 注册 / 内购回调可能 silent fail（不闪退但功能失效）。**release 必须 keep**。

**`android/app/build.gradle.kts` release buildType**：

```kotlin
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
        signingConfig = signingConfigs.getByName("release")
    }
}
```

**完整 keep 规则**（Flutter + Firebase + Play Billing + Gson）：[`templates/proguard-rules.pro`](templates/proguard-rules.pro)。落地：
```bash
cp ~/.claude/skills/overseas-android-google-play/templates/proguard-rules.pro android/app/proguard-rules.pro
```

**注意**：Firebase BoM 较新版本（33.x+）的子库基本都自带 `consumer-rules.pro`。但**自定义** `FirebaseMessagingService` 子类的项目代码不在 SDK keep 范围内，必须自己 keep；否则 onMessageReceived 不被回调。

**排查闪退 / token 拿不到的步骤**：
1. 关 minify 重 build → 如果正常，确认是混淆问题
2. `pm2 logs` / logcat 看 `ClassNotFoundException` 提示哪个类被剥
3. 把对应类加到 `keep` 列表

## 9. APK / AAB 验证清单

解包验证海外包**必须含** Firebase native lib，**不得含**国内 SDK：

```bash
unzip -l build/app/outputs/bundle/overseasRelease/app-overseas-release.aab \
  | grep -E 'firebase|jpush|wechat|alipay'
```

期望：
- ✅ `lib/.../libfirebase_*.so` 出现
- ❌ `lib/.../libjcore*.so`（JPush native）不出现
- ❌ `lib/.../libwechat*.so` 不出现

## 10. Google Play Console 上架配置

**首次上架步骤**：
1. Google Play Console 创建 App
2. 填基本信息：标题（≤ 50 chars）、简短说明（≤ 80 chars）、完整说明
3. 上传 AAB（不是 APK，Google Play 优先 AAB）
4. 内容评级问卷
5. 隐私政策 URL（必填，链接到 `<PROD_DOMAIN>/legal/privacy`）
6. 数据安全（Data Safety）问卷 — 列明用了哪些标识
7. 国家 / 地区可见性

**Data Safety 填写**（用 IDFV / FCM token 时）：
- "Personal info" → User IDs（对应 FCM registration token）
- "App activity" → 看实际是否记录用户操作
- 不要勾"Tracking"（除非真用了 FCM Analytics 跨 App 跟踪）

## 11. 隐私 / GDPR / CCPA

海外发布额外合规：
- **GDPR**（欧盟）：
  - 隐私政策必须明示数据收集 / 处理目的 / 保留时长
  - 用户有权访问、删除、导出其个人数据
  - Cookie / 跟踪需明示同意（CMP）
- **CCPA**（加州）：
  - "Do Not Sell My Personal Information" 入口
  - 用户可请求删除其数据
- **数据驻留**：欧盟用户数据建议存欧盟 region；本应用后端在国内主服务器 + 新加坡中转，欧盟用户数据合规层面属灰区，建议初期只面向亚太 + 北美

实现方式：
- 提供"账号注销"入口（应用内 → 账户安全 → 注销账号）
- 提供"数据导出"入口（→ 联系客服 → 30 天内 email 发送 JSON 数据包）
- 隐私政策中文 + 英文双版本，部署在 `<PROD_DOMAIN>/legal/privacy?lang=en`

## 12. ATT 跨平台一致性

iOS 应用如果不弹 ATT（参见 `ios-app-store` skill 第 6 节），Android 海外版也应保持**不读 GAID**：
- 不集成 Google Mobile Ads SDK
- 不调用 `AdvertisingIdClient.getAdvertisingIdInfo()`
- Data Safety 中 "Advertising or marketing" → 未收集

如果未来要做广告归因，再单独添加并同步两端。

## 13. Changelog（与 iOS 版本号同步）

参见 `ios-app-store` skill 第 11 节。Android 商店文案 ≤ 500 字符（各市场字数取最严）：

```markdown
# x.y.z+n · Android（Google Play / 海外）

> 字数限制：≤ 500 字符。

## 中文（zh-Hans / zh-Hant 投放）

- [一句话要点 1]
- [一句话要点 2]

## English (used for Google Play global locales)

- [Short bullet 1]
- [Short bullet 2]
```

## 14. 上传 Google Play

```bash
# 选项 A：直接拖 AAB 到 Google Play Console "Internal Testing" → "Production"
# 选项 B：用 fastlane 自动上传（推荐 CI/CD）
fastlane supply --aab build/app/outputs/bundle/overseasRelease/app-overseas-release.aab \
  --track production
```

`fastlane` 需要 `keys/play-developer.json`（service account JSON）。

## 15. 跨 flavor 包名隔离

| | cn | overseas |
|---|---|---|
| applicationId | `com.acme.myapp` | `com.acme.myapp.intl` |
| Firebase | ❌ 排除 | ✅ |
| Play Billing | ❌ 排除 | ✅ |
| JPush | ✅ | ❌ |
| WeChat | ✅ | ❌ |
| Alipay | ✅ | ❌ |
| 字体 CDN | `fonts.loli.net` | `fonts.googleapis.com` |
| 内容审核 | 阿里云 Green | Perspective / Rekognition |

如果海外用户切换中国 SIM 卡或访问中国服务器：海外 flavor 的 app 应**仍然**用 Firebase / Play Billing，与服务器端 locale 无关。

## 16. 编译前自检清单

发版前必须确认：
- [ ] `pubspec.yaml` `version: x.y.z+n` buildNumber +1
- [ ] `docs/changelog/android/<v>.md` ≤ 500 字符 + 含 zh / en 双语
- [ ] AAB 解包验证含 Firebase、不含 JPush
- [ ] Google Play Console 隐私政策 URL 可访问
- [ ] Data Safety 问卷与实际行为一致

## 参考

- 配套 skill：`backend-production-deploy`（FCM `.env`）、`flutter-coding-conventions`（buildNumber 纪律）、`ios-app-store`（双平台共用版本号）、`cn-android-flavor`（互斥的中国市场分支）
- Google Play Console：https://play.google.com/console/
- Firebase Console：https://console.firebase.google.com/
- Play Billing 文档：https://developer.android.com/google/play/billing
