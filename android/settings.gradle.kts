pluginManagement { repositories { google(); gradlePluginPortal(); mavenCentral() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = "ViewinAndroid"
include(":viewin-protocol", ":viewin-sdk", ":demo", ":viewin-compose")
