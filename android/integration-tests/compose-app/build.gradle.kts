import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

plugins { id("com.android.application") ; id("org.jetbrains.kotlin.plugin.compose") }
if (providers.gradleProperty("consumerAgp").getOrElse("9.1.1").startsWith("8.")) {
    apply(plugin = "org.jetbrains.kotlin.android")
}
android {
    namespace = "app.viewin.consumer"
    compileSdk = 36
    defaultConfig {
        applicationId = "app.viewin.consumer.compose"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    buildFeatures { compose = true }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
tasks.withType<KotlinJvmCompile>().configureEach {
    compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
}
dependencies {
    implementation("io.github.felikslv01.viewin:viewin-compose:${providers.gradleProperty("viewinVersion").getOrElse("0.1.0")}")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.foundation:foundation:1.10.6")
}
