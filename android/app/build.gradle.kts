import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé d'upload Play Store : android/key.properties (jamais commité) ou, en CI,
// variables d'environnement remplies depuis les secrets GitHub (voir
// docs/MISE_EN_LIGNE.md). Sans clé : signature de debug (APK de test).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun keyValue(name: String, env: String): String? =
    (keyProps.getProperty(name) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val uploadStoreFile = keyValue("storeFile", "ANDROID_KEYSTORE_PATH")

android {
    namespace = "com.kjtech.game304"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kjtech.game304"
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
    }

    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                storeFile = file(uploadStoreFile!!)
                storePassword = keyValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = keyValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = keyValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadStoreFile != null)
                signingConfigs.getByName("upload")
            else
                signingConfigs.getByName("debug") // APK de test uniquement
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
