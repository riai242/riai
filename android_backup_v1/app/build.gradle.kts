// android/app/build.gradle.kts
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "company.riai.shukkinbo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "company.riai.shukkinbo"
        // ★ ここを修正：23 を下回らない
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // --- keystore を読む ---
    val keystorePropsFile = rootProject.file("android/key.properties")
    val keystoreProps = Properties()
    if (keystorePropsFile.exists()) {
        keystorePropsFile.inputStream().use { ins ->
            keystoreProps.load(ins)
        }
    }

    val hasKeystore =
        keystoreProps.getProperty("storeFile")?.isNotBlank() == true &&
                keystoreProps.getProperty("storePassword")?.isNotBlank() == true &&
                keystoreProps.getProperty("keyAlias")?.isNotBlank() == true &&
                keystoreProps.getProperty("keyPassword")?.isNotBlank() == true

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                val storeFilePath = keystoreProps.getProperty("storeFile")
                storeFile = file(storeFilePath)
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (hasKeystore)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources.excludes += setOf(
            "META-INF/LICENSE*",
            "META-INF/DEPENDENCIES",
            "META-INF/NOTICE*",
        )
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // 追加不要（Flutter が解決）
}
