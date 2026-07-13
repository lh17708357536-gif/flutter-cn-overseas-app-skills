---
name: cn-android-flavor
description: 中国大陆市场 Android Flavor — JPush 极光推送、微信 (fluwx) / 支付宝 (tobias) SDK、阿里云 Green 内容审核、`fonts.loli.net` 镜像、ICP 备案应用名规则、隐式标识技术说明文档模板、aapt 校验。**禁止包含 Firebase / Google Play Services**。
---

# 中国大陆 Android（cn flavor）发布 Skill

> 适用于华为 / 小米 / OPPO / vivo / 应用宝等国内市场。所有 `<PLACEHOLDER>` 替换为项目实际值。

## 1. 硬约束（不可违反）

- ❌ **cn flavor 禁止包含 Firebase / Google Services / Google Play Services SDK** — 华为 HMS 审核直接拒；国内用户无 Google 服务无法使用
- ❌ **cn flavor 禁止指向 `googleapis.com` / `gstatic.com` 等 Google CDN** — 国内被墙，加载失败
- ❌ **禁止采集 IMEI / MEID / IMSI / Settings.Secure.ANDROID_ID / MAC** — 工信部专项整治禁项
- ✅ **必须用 JPush（或同类国内推送）** — 不用境外 FCM
- ✅ **applicationId 与海外包隔离** — 例如 cn = `com.acme.myapp`、overseas = `com.acme.myapp.intl`
- ✅ **ICP 备案 App 名称必须与 `<application android:label>` 完全一致**

## 2. `build.gradle.kts` flavor 模板

> **前提**：`flutter create` 默认生成 Groovy DSL（`build.gradle`），本节模板是 Kotlin DSL。如果项目还没迁，先 `mv build.gradle build.gradle.kts` 并按 KTS 语法改写（`apply plugin: "x"` → `id("x")`、`def` → `val`）。

```kotlin
android {
    flavorDimensions += "market"
    productFlavors {
        create("cn") {
            dimension = "market"
            applicationId = "<APP_PACKAGE>"   // 例：com.acme.myapp
            manifestPlaceholders["MARKET"] = "cn"
            manifestPlaceholders["JPUSH_PKGNAME"] = applicationId as Any
            manifestPlaceholders["JPUSH_APPKEY"] = jpushAppKey   // 从 key.properties 读
            manifestPlaceholders["JPUSH_CHANNEL"] = jpushChannel  // 例：huawei / xiaomi / oppo / default
        }
        // overseas flavor 见 overseas-android-google-play skill
    }
}

// ⚠️ 不要在这里手动 add("cnImplementation", "cn.jiguang.sdk:jpush:x.y.z")。
// `jpush_flutter` Flutter 插件已经声明了 JPush native 依赖，再手动加会触发
// duplicate class / 版本冲突。版本统一由 pubspec.yaml 锁。
//
// 仅在不使用 jpush_flutter（直接调原生）时，才需要在这里手动 add cnImplementation。
```

`android/key.properties`（不进 git，CI 通过环境变量注入）：
```properties
storeFile=keystore/release.jks
storePassword=...
keyAlias=...
keyPassword=...
jpushAppKey=<JPUSH_APP_KEY>
jpushChannel=default
```

`build.gradle.kts` 顶部读取：
```kotlin
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.inputStream().use { keystoreProperties.load(it) }
}
val jpushAppKey = keystoreProperties.getProperty("jpushAppKey")?.takeIf { it.isNotBlank() }
    ?: System.getenv("JPUSH_APP_KEY")
    ?: throw GradleException("cn release build requires jpushAppKey in key.properties or JPUSH_APP_KEY env")
val jpushChannel = keystoreProperties.getProperty("jpushChannel")?.takeIf { it.isNotBlank() }
    ?: System.getenv("JPUSH_CHANNEL")
    ?: "default"
```

## 3. 目录隔离

```
android/app/src/
├── main/                       # 双 flavor 共用
│   └── AndroidManifest.xml     # ★ application label = ICP 备案名；activity label = 主屏短名
├── cn/
│   ├── AndroidManifest.xml     # JPush meta-data + 国内 receiver
│   └── kotlin/com/.../<app>/
│       └── <App>JPushReceiver.kt
└── overseas/                   # 见 overseas-android-google-play skill
```

## 4. ICP 备案应用名 + 主屏图标短名（双 label）

详见 `~/.claude/skills/_shared/rules.md` §5。本 skill 的 cn flavor `AndroidManifest.xml` 完整模板（含 networkSecurityConfig / enableOnBackInvokedCallback / launchMode / configChanges 等 Android 特有属性）：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 权限清单见第 6 节 -->
    <application
        android:label="<完整 ICP 备案 App 名称>"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:networkSecurityConfig="@xml/network_security_config"
        android:enableOnBackInvokedCallback="true">
        <activity
            android:name=".MainActivity"
            android:label="<App 短名>"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

## 5. JPush 极光推送集成

`pubspec.yaml`：
```yaml
dependencies:
  jpush_flutter: ^x.x.x   # 选当前最新稳定版
```

`android/app/src/cn/AndroidManifest.xml`：
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application>
        <meta-data
            android:name="JPUSH_APPKEY"
            android:value="${JPUSH_APPKEY}" />
        <meta-data
            android:name="JPUSH_CHANNEL"
            android:value="${JPUSH_CHANNEL}" />
        <receiver
            android:name=".<App>JPushReceiver"
            android:enabled="true"
            android:exported="false">
            <intent-filter>
                <action android:name="cn.jpush.android.intent.REGISTRATION" />
                <action android:name="cn.jpush.android.intent.MESSAGE_RECEIVED" />
                <action android:name="cn.jpush.android.intent.NOTIFICATION_RECEIVED" />
                <action android:name="cn.jpush.android.intent.NOTIFICATION_OPENED" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

Flutter 端：
```dart
const buildFlavor = String.fromEnvironment('BUILD_FLAVOR');
if (buildFlavor == 'cn_android') {
  final jpush = JPush();
  jpush.setup(appKey: '<JPUSH_APP_KEY>', channel: '<channel>');
  jpush.applyPushAuthority();
  jpush.addEventHandler(
    onReceiveNotification: (msg) async { /* ... */ },
    onOpenNotification: (msg) async { /* deeplink */ },
  );
  final regId = await jpush.getRegistrationID();
  // 把 regId 同步到后端
}
```

## 6. Android 权限清单（白名单）

`android/app/src/main/AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<!-- 业务必需，按需声明 -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<!-- Android 12 及以下选图 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

`android/app/src/cn/AndroidManifest.xml` 显式排除海外权限：
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" tools:node="remove" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" tools:node="remove" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" tools:node="remove" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" tools:node="remove" />
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" tools:node="remove" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />
    <uses-permission android:name="com.android.vending.BILLING" tools:node="remove" />
</manifest>
```

**禁止声明**：`READ_PHONE_STATE` / `READ_CONTACTS` / `READ_CALL_LOG` / `GET_ACCOUNTS` / `QUERY_ALL_PACKAGES` / `BILLING`（Google Play）

## 7. 微信支付 (fluwx) + 支付宝 (tobias) 集成

`pubspec.yaml`：
```yaml
dependencies:
  fluwx: ^4.x.x      # 微信
  tobias: ^3.x.x     # 支付宝

tobias:
  url_scheme: <APP_SHORT_NAME>   # 例：myapp
```

需要在微信开放平台 / 支付宝开放平台申请 AppID，配置签名包名。

## 8. 阿里云 Green 内容审核

后端集成（NestJS）：
- 文本：`AliyunGreenService.moderateText(text)` → block / review / pass 三档
- 图片：`AliyunGreenService.moderateImage(url)` → 同上
- **SDK 失败默认 review（挂起人工，绝不自动放行）**
- **图片审核要求公网 URL**（Local 上传模式需配 `BASE_URL` 或切 OSS）

UGC 入口（论坛 / 聊天 / 投诉 / 头像 / 用户上传图）必须接入审核。后端模板：
```typescript
const result = await aliyunGreen.moderateText(content);
if (result === 'block') throw new ForbiddenException('内容含违规信息');
if (result === 'review') {
  // 入数据库 status=pending，等管理员审
} else {
  // pass，正常入库
}
```

## 9. 中国网络适配（核心）

**Google Fonts → `fonts.loli.net` 镜像**：
```css
/* H5 / Web */
@import url('https://fonts.loli.net/css2?family=Noto+Sans+SC&display=swap');
```

后端 brand-vi 服务生成 fontLink：
```typescript
const url = `https://fonts.loli.net/css2?${fonts.join('&')}&display=swap`;
return `<link rel="preconnect" href="https://fonts.loli.net">
<link rel="preconnect" href="https://gstatic.loli.net" crossorigin>
<link href="${url}" rel="stylesheet">`;
```

**Gemini API 通过新加坡节点中转**：
- `.env`: `GEMINI_BASE_URL=https://<SINGAPORE_PROXY>/v1beta`
- 国内主服务器 → 新加坡 Nginx 8443 → `generativelanguage.googleapis.com`

**自检命令**：
```bash
grep -rE "fonts\.googleapis\.com|generativelanguage\.googleapis\.com" \
  android/ ios/ lib/ server/src/
# 期望：无残留（都已替换为 loli.net / SINGAPORE_PROXY）
```

## 10. 字体栈兜底（繁体中文渲染）

H5 CSS 字体栈追加 Traditional Chinese fallback，保证 zh-HK 用户字形正确：
```css
--vi-font-serif: "<userSerif>", "Noto Serif TC", "PingFang TC", "Microsoft JhengHei", serif;
--vi-font-sans: "<userSans>", "Noto Sans TC", "PingFang TC", "Microsoft JhengHei", sans-serif;
--vi-font-body: "<userSans>", "<userSerif>", "Noto Sans TC", "PingFang TC", sans-serif;
--vi-font-heading: "<userSerif>", "<userSans>", "Noto Serif TC", "PingFang TC", serif;
```

iOS / macOS 自带 PingFang TC；Win10+ 自带 Microsoft JhengHei；Android 7+ 自带 Noto Sans/Serif TC。仅声明 fallback，不强加载远程字体。

## 10.5 ProGuard / R8 混淆规则

> Release 构建默认开 R8 minify + obfuscate。JPush / fluwx / tobias 都用反射注册原生 callback，混淆后类名变了 → 启动闪退 / 推送收不到 / 支付回调丢失。**release 构建必须配 keep 规则**。

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

**完整 keep 规则**（Flutter + JPush + 微信 + 支付宝 + 阿里云 + Gson）：[`templates/proguard-rules.pro`](templates/proguard-rules.pro)。落地：
```bash
cp ~/.claude/skills/cn-android-flavor/templates/proguard-rules.pro android/app/proguard-rules.pro
```

**注意**：大多数三方 SDK 通过 AAR 自带 `consumer-rules.pro`，会自动合并到最终 ProGuard 配置。但如果实测启动闪退，**先关 minify 验证是否混淆问题**：

```kotlin
// 临时排查
isMinifyEnabled = false
isShrinkResources = false
```

如关掉 minify 后正常 → 把对应 SDK 的 `keep` 规则加到 `proguard-rules.pro`。

## 11. APK 验证清单

构建完成后必须用 `aapt` 校验：

```bash
# 找到 aapt（Android SDK build-tools 下）
AAPT=$HOME/Library/Android/sdk/build-tools/35.0.0/aapt   # macOS
# AAPT=$ANDROID_HOME/build-tools/35.0.0/aapt              # Linux/Windows WSL

$AAPT dump badging build/app/outputs/flutter-apk/app-cn-release.apk \
  | grep -E "package|application:|launchable-activity"
```

**期望输出**：
```
package: name='<APP_PACKAGE>' versionCode='<n>' versionName='<x.y.z>'
application: label='<完整 ICP 备案 App 名称>' icon='res/...'
launchable-activity: name='<APP_PACKAGE>.MainActivity' label='<App 短名>'
```

`application: label` 是工信部备案查询命中的字段；`launchable-activity: label` 是主屏图标显示的字段。

**APK 解包确认无 Firebase / 海外 SDK**：
```bash
unzip -l build/app/outputs/flutter-apk/app-cn-release.apk \
  | grep -iE 'firebase|google-services|play-services' \
  || echo "✅ 无 Google SDK"
```

## 12. 隐式标识技术说明文档（合规材料模板）

国内市场审核常要求《隐式标识技术说明文档》。完整模板见 [`templates/implicit_identifier_spec.md`](templates/implicit_identifier_spec.md)（覆盖：方案总览、标识清单、第三方 SDK 隐式标识声明、权限对照、用户撤回路径、合规对照、7 张截图清单）。落地：

```bash
mkdir -p docs/compliance
cp ~/.claude/skills/cn-android-flavor/templates/implicit_identifier_spec.md \
   docs/compliance/implicit_identifier_spec.md
# 替换 <APP_DISPLAY_NAME> / <APP_PACKAGE> / <x.y.z+n> 等占位符
```

## 13. 构建命令

```bash
# APK（应用宝 / 华为部分市场）
flutter build apk \
  --flavor cn \
  --release \
  --dart-define=BUILD_FLAVOR=cn_android \
  --dart-define=API_BASE_URL=<PROD_API_URL>

# AAB（小米 / OPPO / vivo 部分市场要求 AAB）
flutter build appbundle \
  --flavor cn \
  --release \
  --dart-define=BUILD_FLAVOR=cn_android \
  --dart-define=API_BASE_URL=<PROD_API_URL>
```

## 14. 各国内市场差异要点

| 市场 | 备注 |
|---|---|
| **华为应用市场** | 必须有 ICP 备案；无 Google Services；可选 HMS 套件（不强制）；要求"隐式标识技术说明文档" |
| **小米应用商店** | ICP + 软件著作权登记证；APK 签名要求 V2 + V3 |
| **OPPO** | ICP + 备案；接口规范类似小米 |
| **vivo** | ICP + 备案；首发要求较多 |
| **应用宝（腾讯）** | ICP + 软著；下载量大但审核较慢 |
| **抖音 / 快手 / 360** | 各家差异，按各自后台填写 |

## 15. 上传到自家官网（统一 APK 下载）

部分情况下用户绕过商店直接访问官网下载。后端 `server/src/h5/public/downloads/<APP_NAME>-cn.apk` 静态文件，HTTPS 提供：

```bash
# 备份 + 上传 + sha1 校验 + 原子替换（详见 backend-production-deploy skill 第 10 节）
TS=$(date +%Y%m%d-%H%M%S)
ssh -i $SSH_KEY $REMOTE_HOST "cp $REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk \
  $REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk.backup-$TS"

scp -i $SSH_KEY ./build/app/outputs/flutter-apk/app-cn-release.apk \
  $REMOTE_HOST:$REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk.uploading

# sha1 校验后原子 mv
LOCAL_SHA=$(shasum -a 1 ./build/app/outputs/flutter-apk/app-cn-release.apk | awk '{print $1}')
REMOTE_SHA=$(ssh -i $SSH_KEY $REMOTE_HOST "sha1sum $REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk.uploading | awk '{print \$1}'")
[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] || { echo "❌ sha1 不一致"; exit 1; }

ssh -i $SSH_KEY $REMOTE_HOST "mv $REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk.uploading \
  $REMOTE_PATH/src/h5/public/downloads/<APP_NAME>-cn.apk"

curl -sI https://<PROD_DOMAIN>/static/downloads/<APP_NAME>-cn.apk | head -8
```

## 16. 编译前自检清单

发版前必须确认：
- [ ] `pubspec.yaml` `version: x.y.z+n` buildNumber +1
- [ ] `docs/changelog/android/<v>.md` ≤ 500 字符 + 含 zh / en 双语
- [ ] `aapt dump badging` `application-label` = ICP 备案名（**逐字符**核对）
- [ ] `aapt dump badging` `launchable-activity-label` = 主屏短名
- [ ] APK 解包验证：含 JPush 相关 so，**不含** Firebase / Google Services
- [ ] `docs/compliance/implicit_identifier_spec.md` 与版本号一致
- [ ] 7 张合规截图准备好（首次启动隐私政策、登录页、设备列表、系统权限页、通知开关、退出设备、注销账号）

## 参考

- 配套 skill：`backend-production-deploy`、`flutter-coding-conventions`、`ios-app-store`（双平台共用版本号）、`overseas-android-google-play`（互斥的海外分支）
- JPush 集成文档：https://docs.jiguang.cn/jpush/client/Android/android_guide
- 工信部 164 号文：信息通信领域用户权益保护监督检查工作要求
- ICP 备案：https://beian.miit.gov.cn/
