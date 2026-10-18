# Development and publishing

## Build and test

The iOS demo is `examples/ios/ViewinDemo.xcodeproj`, scheme `ViewinDemo`, with unit tests in `ViewinSDKTests`. Regenerate with XcodeGen when changing `project.yml`. Pipe `xcodebuild` output through `xcbeautify`. Distributed iOS frameworks and XCFrameworks must use Git LFS.

For Android, use Android Studio's bundled JDK locally and Android SDK 36. No JDK belongs in this repository. From `android/`:

```sh
./gradlew :viewin-protocol:test :demo:assembleDebug :demo:assembleRelease
./gradlew stageMaven
```

`viewinVersion` in `android/gradle.properties` is the single Android version source. Independent consumer fixtures automatically read it. `stageMaven` generates all three modules in `android/build/maven`, including POM / Gradle metadata, sources, Dokka HTML documentation JARs, checksums, and MIT notices. It does not upload anything and needs no publishing credentials.

```sh
python3 scripts/publish-maven.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/publish-maven.py --archive android/build/distributions/android-maven.zip
```

The **Android Maven compatibility** workflow verifies published-file consumption on AGP 8.13.0 / Gradle 8.14.3 and AGP 9.1.1 / Gradle 9.3.1, using View and Compose consumers in Debug and minified Release. CI uses JDK 21, so testing Gradle 8 does not require changing the local Android Studio JDK.

## Maven Central setup (maintainer action)

Maven Central is the intended distribution channel for new versions. The existing `maven` branch and its `0.1.0` files remain available for consumers who already configured that repository. Neither Central nor the legacy repository may overwrite published versions. The next candidate is `0.1.1`; it is not a Central release until publication and downloads are verified.

Before the first Central publication:

1. Sign in to [Central Portal](https://central.sonatype.com/) with the owner's GitHub account and complete account registration and any producer terms yourself. GitHub sign-in normally provisions the corresponding `io.github.<username>` namespace automatically. Confirm the verified namespace covers `io.github.felikslv01.viewin`; do not assume verification based on the GitHub repository alone.
2. Generate a **Portal User Token** on the account page. The token username/password are different from your account login credentials.
3. Use a production GPG signing key, publish its public key to a supported keyserver, and retain a secure backup of the private key. See [Sonatype's GPG guide](https://central.sonatype.org/publish/requirements/gpg/). Local test keys must never be used for release publication.
4. Add these [repository Actions Secrets](https://github.com/FeliksLv01/ViewinSDK/settings/secrets/actions):

| Secret | Value |
| --- | --- |
| `MAVEN_CENTRAL_USERNAME` | Portal User Token username |
| `MAVEN_CENTRAL_PASSWORD` | Portal User Token password |
| `MAVEN_SIGNING_KEY` | Complete ASCII-armored private signing key |
| `MAVEN_SIGNING_PASSWORD` | Key passphrase, if protected |

Never send tokens or private keys in chat, commit them, or put them in project `gradle.properties`. The workflow exposes secrets only to the publishing step and uses Gradle's in-memory signing support. An existing key can be sent directly to GitHub Secrets without printing or saving a private-key file:

```sh
# KEY_ID is a public key identifier, not the private key.
gpg --armor --export-secret-keys KEY_ID | gh secret set MAVEN_SIGNING_KEY --repo FeliksLv01/ViewinSDK
```

## Publish a version

1. Increment `viewinVersion` and add `changelog/<version>.md`. Commit and push the source changes.
2. Run **Maven Central release** manually from the intended commit on `main`.
3. The workflow first runs both compatibility matrix entries. After they pass, it checks the required secrets, signs all publications and uses the Vanniktech Maven Publish plugin to upload/release all three modules through the Central Portal API. Publication waits for the Portal's `PUBLISHED` state.
4. It verifies public Maven Central POM downloads, then creates a GitHub Release at the exact source revision. Assets include the signed Maven repository backup ZIP, its SHA-256, and the standalone AAR / JAR binaries. The version notes come from `changelog/<version>.md`.
5. After confirming the first Central release can be consumed, update the public installation instructions to `mavenCentral()` and the new version. Keep the legacy repository instructions for `0.1.0`; do not advertise a pending version as downloadable.

The publishing job requires `-PsignPublications=true`. Missing credentials or signing configuration fail before an upload. Local staging remains unsigned unless that flag is explicitly set. For a local authorized publication, supply the same values through the documented `ORG_GRADLE_PROJECT_...` environment variables and run:

```sh
android/gradlew -p android -PsignPublications=true stageMaven publishAndReleaseToMavenCentral
python3 scripts/publish-maven.py --require-signatures --archive android/build/distributions/android-maven.zip
```

The project uses `com.vanniktech.maven.publish.base` with the existing publications and Dokka for API documentation. Do not add an SDK-runtime dependency on these build plugins. Sources and POM metadata must match the released binaries. A failed upload is not a published release, and a Portal `PUBLISHED` result alone does not replace verifying public downloads.

### Recovering an interrupted release

If Central publication succeeded but a later availability check or GitHub upload failed, do not rerun the publishing step or bump the version blindly. Confirm the existing deployment and public artifacts, then create the GitHub Release from those exact artifacts and the original source revision. Never replace existing Maven coordinates with different binaries.

### Legacy repository

`scripts/publish-maven.py --push` remains available for explicit legacy maintenance, validates hashes and immutable version directories, and writes only generated artifacts to the `maven` branch. It is no longer an automatic publication job. Normal releases use Central and GitHub Releases.
