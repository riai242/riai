// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter Gradle Plugin（settings.gradle経由で解決されます）
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter プロジェクトのルート（必須）
flutter {
    // Flutter プロジェクトのルート相対パス
    //（この値は Flutter テンプレートと同じで OK）
    source = "../.."
}

android {
    namespace = "company.riai.shukkinbo"

    // Flutter プラグインが提供する推奨値を使うのが安全ですが、
    // 固定で指定しても問題ありません。両方記述可能です。
    // compileSdk = flutter.compileSdkVersion  // ← 有効でもOK
    compileSdk = 34

    defaultConfig {
        applicationId = "company.riai.shukkinbo"
        minSdk = 23
        // targetSdk = flutter.targetSdkVersion // ← 有効でもOK
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }

    // リリース署名は後で keystore を用意して置き換えてください
    signingConfigs {
        create("release") {
            // storeFile = file("/absolute/path/to/your.keystore")
            // storePassword = "******"
            // keyAlias = "your_key_alias"
            // keyPassword = "******"
        }
    }

    buildTypes {
        getByName("debug") {
            // デバッグはデフォルト署名（Android Studio / Flutter 標準）を使用
            // 必要ならここで設定を追加
        }
        getByName("release") {
            isMinifyEnabled = false
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )

            // まだ keystore を用意していない間の一時措置として
            // debug 署名を流用したい場合は下記を使用（後で必ず本番署名へ）
            // signingConfig = signingConfigs.getByName("debug")

            // 本番用 keystore を用意済みならこちらに切り替え
            // signingConfig = signingConfigs.getByName("release")
        }
    }

    // Java/Kotlin 17（Flutter 3.22+ 推奨）
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // CoreLibraryDesugaring を使う場合は true にし、依存も追加
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    // packager の重複を避けたい場合の例（必要時のみ）
    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1"
            )
        }
    }
}

// 依存関係
dependencies {
    // Flutter プラグイン（例：google_mobile_ads など）が Play Services 等を内部で解決します。
    // アプリ側で追加が必要な場合のみここに記述してください。

    // kotlinx / androidx のユーティリティを使いたい場合の例（任意）
    implementation("androidx.core:core-ktx:1.13.1")

// Java 8+ API の desugaring を使う場
