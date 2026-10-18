plugins { id("com.android.library"); id("org.jetbrains.dokka") }
android {
    namespace = "app.viewin.sdk"
    compileSdk = 36
    defaultConfig { minSdk = 29; consumerProguardFiles("consumer-rules.pro") }
    publishing { singleVariant("release") { withSourcesJar() } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies { api(project(":viewin-protocol")) }
