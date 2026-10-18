import org.jetbrains.dokka.gradle.tasks.DokkaGeneratePublicationTask
import com.vanniktech.maven.publish.MavenPublishBaseExtension
import com.vanniktech.maven.publish.DeploymentValidation
import org.gradle.api.publish.maven.tasks.PublishToMavenRepository

import org.gradle.api.publish.maven.MavenPublication
import org.gradle.api.publish.PublishingExtension

plugins {
    id("com.vanniktech.maven.publish.base") version "0.37.0" apply false
    id("org.jetbrains.dokka") version "2.2.0" apply false
    kotlin("plugin.compose") version "2.2.20" apply false
    kotlin("jvm") version "2.2.20" apply false
    kotlin("plugin.serialization") version "2.2.20" apply false
    id("com.android.library") version "9.1.1" apply false
    id("com.android.application") version "9.1.1" apply false
}

val libraryModules = setOf("viewin-protocol", "viewin-sdk", "viewin-compose")
subprojects {
    if (name in libraryModules) {
        val libraryProject = this
        group = "io.github.felikslv01.viewin"
        version = providers.gradleProperty("viewinVersion").get()
        apply(plugin = "com.vanniktech.maven.publish.base")
        val signingEnabled = providers.gradleProperty("signPublications").orElse("false").get().toBoolean()
        extensions.configure<MavenPublishBaseExtension> {
            coordinates(project.group.toString(), project.name, project.version.toString())
            publishToMavenCentral(automaticRelease = false, validateDeployment = DeploymentValidation.PUBLISHED)
            if (signingEnabled) signAllPublications()
        }
        val validateCentralCredentials = tasks.register("validateCentralCredentials") {
            doLast {
                check(signingEnabled) { "Central publishing requires -PsignPublications=true" }
                for (key in listOf("mavenCentralUsername", "mavenCentralPassword", "signingInMemoryKey")) {
                    check(providers.gradleProperty(key).orNull?.isNotBlank() == true) {
                        "Missing $key; configure it outside the repository"
                    }
                }
            }
        }
        tasks.matching { it.name == "prepareMavenCentralPublishing" }.configureEach {
            dependsOn(validateCentralCredentials)
        }
        tasks.withType<PublishToMavenRepository>().configureEach {
            if (name.endsWith("ToMavenCentralRepository")) dependsOn(validateCentralCredentials)
        }
        val javadocJar = tasks.register<Jar>("javadocJar") {
            archiveClassifier.set("javadoc")
            dependsOn("dokkaGeneratePublicationHtml")
            from(libraryProject.tasks.named<DokkaGeneratePublicationTask>("dokkaGeneratePublicationHtml").flatMap { it.outputDirectory })
        }
        tasks.withType<Jar>().configureEach {
            from(rootProject.file("../LICENSE")) {
                into("META-INF")
                rename { "LICENSE-${project.name}" }
            }
        }

        gradle.projectsEvaluated {
            libraryProject.extensions.configure<PublishingExtension> {
                publications {
                    create<MavenPublication>("release") {
                        from(libraryProject.components[if (libraryProject.name == "viewin-protocol") "java" else "release"])
                        artifactId = libraryProject.name
                        artifact(javadocJar)
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
                        url = rootProject.providers.gradleProperty("viewinStagingDirectory")
                            .map { rootProject.file(it).toURI() }
                            .orElse(rootProject.layout.buildDirectory.dir("maven").map { it.asFile.toURI() }).get()
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
