import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-key signing config sourced from `android/key.properties`
// (gitignored — per-machine in dev, regenerated from GitHub Secrets in
// CI by .github/workflows/release-android.yml). Loaded once at config
// time and consumed by the signingConfigs block below.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.gilmoretech.myshopclient"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.gilmoretech.myshopclient"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps key resolution order:
        //   1. Gradle project property `MAPS_API_KEY` (sourced from
        //      android/gradle.properties, which `flutter run` does NOT
        //      regenerate — unlike local.properties, which it wipes on
        //      every debug build).
        //   2. `local.properties` fallback for legacy `tool/build.sh`
        //      release builds that already write there.
        val mapsApiKey: String = run {
            val fromGradle = (project.findProperty("MAPS_API_KEY") as String?)?.trim()
            if (!fromGradle.isNullOrEmpty()) return@run fromGradle
            val localProps = Properties()
            val localPropsFile = rootProject.file("local.properties")
            if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
            localProps.getProperty("MAPS_API_KEY", "")
        }
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        // Only register the release signing config if key.properties is
        // present. Lets `flutter run` / `flutter build apk --debug` work
        // on contributor machines that haven't set up signing — Gradle
        // would otherwise fail config-time with "storeFile not specified".
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Use the upload key when key.properties is configured;
            // otherwise fall back to the debug key so non-signing
            // builds (debug runs, contributor CI, etc.) keep working.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
   
}

flutter {
    source = "../.."
}
