// 必须写成顶层 import，不能就地写 `java.util.Properties()`：在 Gradle Kotlin DSL 里
// `java` 这个名字会被 Java 插件扩展遮蔽，`java.util` 于是被当成「扩展上的 util 成员」，
// 编译期直接报 `Unresolved reference 'util'`（2026-10-12 首次发布时 CI 就死在这里）。
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名。密钥与口令放在 android/key.properties（已被 .gitignore 忽略）；
// CI 由 .github/workflows/release.yml 从 GitHub Secrets 写出同名的文件，
// 于是本机与流水线走的是同一条路径、同一个约定。
//
// 没有这个文件时退回调试签名，这样 `flutter run --release` 在任何机器上都还能跑，
// 但打出来的**不是**发布包。这是刻意的取舍：让构建永远能成功，把「这是不是一个
// 正式包」的判定交给流水线 —— release.yml 会在构建之后用 apksigner 核对证书里
// 确实有 CN=LocalTransfer，对不上就失败，而不是发出一批调试签名的包
// （调试签名无法覆盖升级正式签名，用户将来必须卸载重装）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.menghun3_cn.zhu_ye_local_im"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.menghun3_cn.zhu_ye_local_im"
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
        if (hasReleaseKey) {
            create("release") {
                // 相对路径按模块目录（android/app）解析，所以 key.properties 里写
                // storeFile=local_transfer-release.p12，密钥就放在 android/app/ 下。
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeType = keystoreProperties.getProperty("storeType") ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
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
