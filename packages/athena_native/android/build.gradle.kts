group = "dev.ehollbach.athena_native"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.ehollbach.athena_native"

    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 28
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake {
                // a kneejerk checkout elsewhere: -Pathena.kneejerkDir=/path/to/kneejerk
                (project.findProperty("athena.kneejerkDir") as String?)?.let { arguments += "-DKNEEJERK_DIR=$it" }
                arguments += listOf("-DCMAKE_BUILD_TYPE=Release", "-DANDROID_STL=c++_static")
                // no debug info: with it llama.cpp's objects take 2 GB and the library 118 MB
                cFlags += "-g0"
                cppFlags += "-g0"
            }
        }
    }

    // kneejerk + llama.cpp as libathena_engine.so, see ../src/CMakeLists.txt
    externalNativeBuild {
        cmake {
            path = file("../src/CMakeLists.txt")
            version = "4.1.2"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

