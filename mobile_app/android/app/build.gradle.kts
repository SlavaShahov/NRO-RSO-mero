import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Читаем key.properties (создаётся в CI или вручную на машине разработчика)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "ru.rso.nsk.events"        // ← applicationId
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "ru.rso.nsk.events"
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Конфиг подписи релизного APK
    signingConfigs {
        create("release") {
            storeFile = if (keystorePropertiesFile.exists())
                file(keystoreProperties["storeFile"] as String)
            else null
            storePassword = keystoreProperties["storePassword"] as? String ?: ""
            keyAlias      = keystoreProperties["keyAlias"]      as? String ?: ""
            keyPassword   = keystoreProperties["keyPassword"]   as? String ?: ""
        }
    }

    buildTypes {
        release {
            // Используем release-подпись если есть key.properties, иначе debug
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}