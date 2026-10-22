import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (gitignored), e.g.:
//
//   storeFile=C:/keys/afyasmart-upload.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
//
// Create the keystore once with:
//   keytool -genkey -v -keystore afyasmart-upload.jks -keyalg RSA //     -keysize 2048 -validity 10000 -alias upload
//
// Without the file, release builds fall back to the debug key so
// `flutter run --release` still works locally — but Play Console rejects
// those, so a store build must have it.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

// Local, gitignored values such as the Mapbox token (see secrets.properties.example).
val secretProperties = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.afyasmart.afyasmart"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Must stay identical to the React Native app's package name
        // (app.json -> expo.android.package). A different applicationId is a
        // different app to the Play Store, so changing it would ship this as
        // a new listing rather than an update to the existing one.
        applicationId = "com.afyasmart.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The Maps key is injected at build time via -PmapsApiKey=... so it
        // never enters version control. It falls back to empty, which renders
        // a blank grey map rather than failing the build.
        manifestPlaceholders["mapsApiKey"] =
            (project.findProperty("mapsApiKey") as String?) ?: ""
        // Mapbox public token: -PmapboxApiKey=... or android/secrets.properties
        // (gitignored). Kept out of git because GitHub push protection rejects
        // Mapbox tokens even though pk.* tokens are public by design.
        manifestPlaceholders["mapboxApiKey"] =
            (project.findProperty("mapboxApiKey") as String?)
                ?: secretProperties.getProperty("mapboxApiKey")
                ?: ""

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("android/key.properties not found: release build is signed with the DEBUG key and cannot be uploaded to Play.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
