import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chic.audiovisual_creator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chic.audiovisual_creator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// The single editable Dart template becomes bundled source before Flutter
// compiles shaders/assets. The friend only needs the normal Run action.
val compileCreatorVisuals by tasks.registering(Exec::class) {
    val properties = Properties().apply {
        rootProject.file("local.properties").inputStream().use { load(it) }
    }
    val sdk = properties.getProperty("flutter.sdk")
        ?: error("flutter.sdk is missing from local.properties")
    workingDir(project.file("../.."))
    if (System.getProperty("os.name").lowercase().startsWith("windows")) {
        commandLine("cmd", "/c", "$sdk/bin/dart.bat", "run", "tool/compile_visuals.dart")
    } else {
        commandLine("$sdk/bin/dart", "run", "tool/compile_visuals.dart")
    }
}
tasks.configureEach {
    if (name.startsWith("compileFlutterBuild")) dependsOn(compileCreatorVisuals)
}
