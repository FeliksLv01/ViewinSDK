plugins { id("com.android.library") }
android {
 namespace = "app.viewin.compose"; compileSdk = 36
 defaultConfig { minSdk = 29; consumerProguardFiles("consumer-rules.pro") }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies {
 api(project(":viewin-sdk"))
 implementation("androidx.compose.ui:ui:1.10.6")
 implementation("androidx.compose.ui:ui-tooling-data:1.10.6")
}
