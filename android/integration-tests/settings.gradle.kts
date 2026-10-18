pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
    plugins {
        id("com.android.application") version providers.gradleProperty("consumerAgp").getOrElse("9.1.1")
        id("org.jetbrains.kotlin.android") version "2.2.20"
        id("org.jetbrains.kotlin.plugin.compose") version "2.2.20"
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        exclusiveContent {
            forRepository {
                maven {
                    url = uri(providers.gradleProperty("viewinMavenUrl")
                        .getOrElse(file("../build/maven").toURI().toString()))
                }
            }
            filter { includeGroup("io.github.felikslv01.viewin") }
        }
    }
}
rootProject.name = "ViewinMavenConsumers"
include(":view-app", ":compose-app")
