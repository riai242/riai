plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Manifest の package は使わない。ここが正
    namespace = "company.riai.shukkinbo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "company.riai.shukkinbo"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    buildTypes {
        getByName("release") { signingConfig = signingConfigs.getByName("debug") }
        getByName("debug") { }
    }
}

flutter { source = "../.." }
