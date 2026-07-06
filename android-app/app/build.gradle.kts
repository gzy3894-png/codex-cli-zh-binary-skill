import java.util.Properties
import org.gradle.api.GradleException

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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
            val repositoryReleaseKeystore = file("codex-for-tui-2x-release.keystore")
            
            val propertiesFilePath = if (isGITHUB_ACTION) {
                "/tmp/signing.properties"
            } else {
                "/home/rohit/Android/xed-signing/signing.properties"
            }
            
            val propertiesFile = File(propertiesFilePath)
            if (propertiesFile.exists()) {
                val properties = Properties()
                properties.load(propertiesFile.inputStream())
                keyAlias = properties["keyAlias"] as String?
                keyPassword = properties["keyPassword"] as String?
                storeFile = if (isGITHUB_ACTION) {
                    File("/tmp/xed.keystore")
                } else {
                    (properties["storeFile"] as String?)?.let { File(it) }
                }
                
                storePassword = properties["storePassword"] as String?
            } else {
                println("Signing properties file not found at $propertiesFilePath; using repository 2.x release keystore.")
                keyAlias = "testkey"
                keyPassword = "testkey"
                storeFile = repositoryReleaseKeystore
                storePassword = "testkey"
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
        versionCode = 41
        versionName = "2.2.8"
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

tasks.matching { it.name == "validateSigningRelease" }.configureEach {
    doFirst {
        val releaseSigning = android.signingConfigs.getByName("release")
        if (releaseSigning.storeFile == null || releaseSigning.storeFile?.exists() != true) {
            throw GradleException("Release signing is required; refusing to fall back to debug/test signing.")
        }
    }
}

dependencies {
    implementation(project(":core:main"))
}
