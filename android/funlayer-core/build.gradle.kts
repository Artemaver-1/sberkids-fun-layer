// Модуль ядра слоя приколов для Android. Зависимостей нет: только Kotlin stdlib
// и org.json, который входит в Android SDK.
plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "ru.sberkids.funlayer.core"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    kotlinOptions { jvmTarget = "21" }
    sourceSets["main"].java.srcDirs("src/main/kotlin")
}
