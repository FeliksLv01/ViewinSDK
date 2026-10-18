plugins { id("com.android.application"); kotlin("plugin.compose") }
android {
    namespace = "app.viewin.demo"
    compileSdk = 36
    defaultConfig { applicationId = "app.viewin.demo.android"; minSdk = 29; targetSdk = 36; versionCode = 1; versionName = "0.1" }
    buildFeatures { buildConfig = true; compose = true }
    buildTypes { getByName("release") { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"); signingConfig = signingConfigs.getByName("debug") } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies {
    implementation(project(":viewin-compose"))
    implementation("androidx.compose.foundation:foundation:1.10.6")
    implementation("androidx.activity:activity:1.10.1")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
}
