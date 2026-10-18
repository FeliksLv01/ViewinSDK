plugins {
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
    id("org.jetbrains.kotlin.plugin.compose") apply false
}

val sdkProperties = java.util.Properties().apply {
    rootProject.file("../gradle.properties").inputStream().use { load(it) }
}
extra["sdkVersion"] = sdkProperties.getProperty("viewinVersion")

// Keep AGP 8 and AGP 9 outputs separate when checking the compatibility matrix.
subprojects {
    layout.buildDirectory.set(layout.projectDirectory.dir(
        "build/agp-${providers.gradleProperty("consumerAgp").getOrElse("9.1.1")}"))
}
