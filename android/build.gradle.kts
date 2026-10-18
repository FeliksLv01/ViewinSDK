import org.gradle.api.publish.maven.MavenPublication
import org.gradle.api.publish.PublishingExtension

plugins {
    kotlin("plugin.compose") version "2.2.20" apply false
    kotlin("jvm") version "2.2.20" apply false
    kotlin("plugin.serialization") version "2.2.20" apply false
    id("com.android.library") version "9.1.1" apply false
    id("com.android.application") version "9.1.1" apply false
}

val libraryModules = setOf("viewin-protocol", "viewin-sdk", "viewin-compose")
subprojects {
    if (name in libraryModules) {
        group = "io.github.felikslv01.viewin"
        version = providers.gradleProperty("viewinVersion").get()
        apply(plugin = "maven-publish")
        tasks.withType<Jar>().configureEach {
            from(rootProject.file("../LICENSE")) {
                into("META-INF")
                rename { "LICENSE-${project.name}" }
            }
        }

        val libraryProject = this
        gradle.projectsEvaluated {
            libraryProject.extensions.configure<PublishingExtension> {
                publications {
                    create<MavenPublication>("release") {
                        from(libraryProject.components[if (libraryProject.name == "viewin-protocol") "java" else "release"])
                        artifactId = libraryProject.name
                        pom {
                            name.set(libraryProject.name)
                            description.set("Read-only mobile UI capture for Viewin")
                            url.set("https://github.com/FeliksLv01/ViewinSDK")
                            licenses {
                                license {
                                    name.set("MIT License")
                                    url.set("https://opensource.org/license/mit")
                                    distribution.set("repo")
                                }
                            }
                            developers {
                                developer {
                                    id.set("FeliksLv01")
                                    name.set("FeliksLv01")
                                    url.set("https://github.com/FeliksLv01")
                                }
                            }
                            scm {
                                url.set("https://github.com/FeliksLv01/ViewinSDK")
                                connection.set("scm:git:https://github.com/FeliksLv01/ViewinSDK.git")
                                developerConnection.set("scm:git:ssh://git@github.com/FeliksLv01/ViewinSDK.git")
                            }
                        }
                    }
                }
                repositories {
                    maven {
                        name = "Staging"
                        url = rootProject.layout.buildDirectory.dir("maven").get().asFile.toURI()
                    }
                }
            }
        }
    }
}

tasks.register("stageMaven") {
    group = "publishing"
    description = "Build all SDK artifacts and metadata into build/maven without uploading."
    dependsOn(libraryModules.map { ":$it:publishReleasePublicationToStagingRepository" })
}
