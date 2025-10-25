plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")      // ← ここが重要（kotlin-android ではない）
    id("dev.flutter.flutter-gradle-plugin") // ← Flutter プラグイン
}

android {
    namespace = "com.riai.shukkinbo"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.riai.shukkinbo"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}
dependencies {
    // Kotlin を 2.0.21 に揃える（stdlbや反映される関連ライブラリを固定）
    implementation(platform("org.jetbrains.kotlin:kotlin-bom:2.0.21"))
}
