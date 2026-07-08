import java.util.Properties
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
        versionCode = 48
        versionName = "2.3.5"
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
