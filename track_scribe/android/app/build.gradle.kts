import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties, which is git-ignored and only
// written by CI. Without it the release build stays debug-signed, so `flutter run
// --release` still works but the APK cannot be uploaded anywhere.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

// Written by CI from the DEBUG_KEYSTORE_B64 secret; absent on a fresh clone, which
// leaves the debug build on AGP's own generated key.
val sharedDebugKeystore = file("shared-debug.jks")

android {
    namespace = "dev.toufik.track_scribe"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.toufik.track_scribe"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters.add("arm64-v8a") }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.getProperty("storeFile") != null) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
        // AGP generates a throwaway debug key per runner, so every CI debug APK carried
        // a different signature and the phone loop had to uninstall the app - deleting
        // the recordings with it - before installing the next one. ~/.android was
        // measured not to be honoured (CI restored the key there, the APK still got a
        // fresh cert), so the shared key is named here instead.
        if (sharedDebugKeystore.exists()) {
            getByName("debug") {
                storeFile = sharedDebugKeystore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // `androidx.core.content.FileProvider`, the one class the share sheet needs
    // (§2أ). Pinned to the lowest version whose compileSdk requirement this
    // project already satisfies — `flutter.compileSdkVersion` is 36, and a
    // newer core only raises that floor without adding anything we use.
    // A transitive copy from the plugins is not enough: `implementation`
    // deps are not on this module's compile classpath, so the import in
    // MainActivity.kt would not resolve.
    implementation("androidx.core:core:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
