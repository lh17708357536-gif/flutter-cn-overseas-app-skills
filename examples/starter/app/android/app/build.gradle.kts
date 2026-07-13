plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.starter.starter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.starter.starter_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 按市场维度拆分 Flavor：cn（中国大陆）/ overseas（海外 Google Play）。
    // iOS 不走 Android flavor，直接用 --dart-define=BUILD_FLAVOR=ios。
    flavorDimensions += "market"
    productFlavors {
        create("cn") {
            dimension = "market"
            // 中国包应用 ID
            applicationId = "com.example.starter"
            // 真实项目：此 flavor 接入 JPush / 微信 / 支付宝，禁止含 Firebase / Google Play Services
        }
        create("overseas") {
            dimension = "market"
            // 海外包应用 ID 加 .intl 后缀，与国内包区分
            applicationId = "com.example.starter.intl"
            // 真实项目：此 flavor 接入 Firebase / FCM / Google Play Billing，禁止含 JPush / 微信
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
