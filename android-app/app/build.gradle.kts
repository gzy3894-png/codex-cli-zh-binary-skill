import java.util.Properties
import java.security.MessageDigest
import org.gradle.api.GradleException

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

fun requireSigningProperty(properties: Properties, name: String): String {
    val value = properties.getProperty(name)?.trim()
    if (value.isNullOrEmpty()) {
        throw GradleException("Release signing property '$name' is required.")
    }
    return value
}

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(1024 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
}

val verifyCodexUpgradePayload by tasks.registering {
    val assetRoot = rootProject.file("core/main/src/main/assets")
    val payloadDir = assetRoot.resolve("codex-upgrade")
    inputs.dir(payloadDir)
    inputs.file(assetRoot.resolve("codex-apk-upgrade.sh"))
    doLast {
        val manifest = payloadDir.resolve("manifest.properties")
        val manifestSha = payloadDir.resolve("manifest.sha256")
        val launcherAsset = assetRoot.resolve("codex-apk-upgrade.sh")
        val canonicalUpgrade = rootProject.projectDir.parentFile
            .resolve("android-arm64-musl/codex-apk-upgrade.sh")
        listOf(manifest, manifestSha, launcherAsset, canonicalUpgrade).forEach { file ->
            if (!file.isFile || file.length() == 0L) {
                throw GradleException("Missing Codex APK upgrade payload file: $file")
            }
        }
        if (!launcherAsset.readBytes().contentEquals(canonicalUpgrade.readBytes())) {
            throw GradleException("Generated APK upgrade launcher is not synced with android-arm64-musl/codex-apk-upgrade.sh")
        }
        val values = manifest.readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }
            .associate { line ->
                val separator = line.indexOf('=')
                if (separator <= 0) {
                    throw GradleException("Invalid Codex APK manifest line: $line")
                }
                line.substring(0, separator) to line.substring(separator + 1)
            }
        if (values["release"] != "2.4.8" || values["version_code"] != "63") {
            throw GradleException("Codex APK payload release/versionCode mismatch: $values")
        }
        if (values["codex_version"] != "0.144.1" ||
            values["target"] != "aarch64-unknown-linux-musl"
        ) {
            throw GradleException("Codex APK payload binary identity mismatch: $values")
        }
        val expectedManifestSha = manifestSha.readText().trim().substringBefore(' ').lowercase()
        if (sha256(manifest) != expectedManifestSha) {
            throw GradleException("Codex APK manifest SHA256 mismatch")
        }
        val support = payloadDir.resolve(values["support_archive"] ?: "")
        val binary = payloadDir.resolve(values["binary_archive"] ?: "")
        if (support.name.endsWith(".gz") || binary.name.endsWith(".gz")) {
            throw GradleException("Codex APK archives must not end in .gz because AAPT strips that asset suffix; use .tgz")
        }
        if (!support.isFile || sha256(support) != values["support_sha256"]) {
            throw GradleException("Codex APK support archive SHA256 mismatch")
        }
        if (!binary.isFile || sha256(binary) != values["binary_archive_sha256"]) {
            throw GradleException("Codex APK binary archive SHA256 mismatch")
        }
        if (binary.length() < 70L * 1024L * 1024L) {
            throw GradleException("Codex APK binary archive is unexpectedly small")
        }
    }
}


android {
    namespace = "com.gzy3894.codexfortui"
    compileSdk = 36


    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    
    signingConfigs {
        create("release") {
            val isGITHUB_ACTION = System.getenv("GITHUB_ACTIONS") == "true"
            
            val propertiesFilePath = System.getenv("ANDROID_RELEASE_SIGNING_PROPERTIES")
                ?: if (isGITHUB_ACTION) {
                    "/tmp/signing.properties"
                } else {
                    "/home/rohit/Android/xed-signing/signing.properties"
                }
            
            val propertiesFile = File(propertiesFilePath)
            if (propertiesFile.exists()) {
                val properties = Properties()
                propertiesFile.inputStream().use {
                    properties.load(it)
                }
                storeFile = File(requireSigningProperty(properties, "storeFile"))
                keyAlias = requireSigningProperty(properties, "keyAlias")
                keyPassword = requireSigningProperty(properties, "keyPassword")
                storePassword = requireSigningProperty(properties, "storePassword")
            } else {
                println("Release signing properties file not found at $propertiesFilePath; release builds require GitHub Secrets or a local signing.properties file.")
            }
        }
    }
    
    
    buildTypes {
        release{
            isMinifyEnabled = false
            isCrunchPngs = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
            resValue("string","app_name","Codex for TUI")
        }
        debug{
            applicationIdSuffix = ".test"
            versionNameSuffix = "-TEST"
            resValue("string","app_name","Codex for TUI Test")
        }
    }

    
    defaultConfig {
        applicationId = "com.gzy3894.codexfortui"
        minSdk = 26
        targetSdk = 36
versionCode = 63
versionName = "2.4.8"
        vectorDrawables {
            useSupportLibrary = true
        }
    }


    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    
    buildFeatures {
        viewBinding = true
        compose = true
        resValues = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(verifyCodexUpgradePayload)
}

tasks.matching { it.name == "validateSigningRelease" }.configureEach {
    doFirst {
        val releaseSigning = android.signingConfigs.getByName("release")
        val signingFile = releaseSigning.storeFile
        if (
            signingFile == null ||
            signingFile.exists() != true ||
            releaseSigning.keyAlias.isNullOrBlank() ||
            releaseSigning.keyPassword.isNullOrBlank() ||
            releaseSigning.storePassword.isNullOrBlank()
        ) {
            throw GradleException("Release signing is required; refusing to build an unsigned, debug-signed, or repository-signed APK.")
        }
        val repositoryPath = rootProject.projectDir.parentFile.canonicalFile.toPath()
        val signingPath = signingFile.canonicalFile.toPath()
        if (signingPath.startsWith(repositoryPath)) {
            throw GradleException("Release signing keystore must be supplied outside the repository; repository keystore/testkey fallback is disabled.")
        }
    }
}

dependencies {
    implementation(project(":core:main"))
}
