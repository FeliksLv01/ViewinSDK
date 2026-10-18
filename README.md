# ViewinSDK

English · [简体中文](README.zh-CN.md)

Read-only UI capture for **UIKit, SwiftUI, Android View / XML, and Jetpack Compose**. Use it with the [Viewin](https://github.com/FeliksLv01/Viewin) macOS inspector and its bundled CLI to inspect your own apps, or capture snapshots for AI agents without opening the desktop app.

> Early development. Android Maven artifacts are hosted in this public GitHub repository; SwiftPM version tags have not been published yet. The desktop repository may require access while its public release is being prepared.

## Capabilities

| Framework | Capture support | Current limits |
| --- | --- | --- |
| UIKit | View / Layer hierarchy, geometry, properties, images, constraints, gestures, control events, and list positions | Some system and hardware rendering effects cannot be reproduced |
| SwiftUI | Logical tree, recognized modifiers and static gestures, Display List / CALayer associations | Private runtime integration currently tested on the iOS 27 simulator; some logical-to-layer associations use explicitly marked geometry inference |
| Android View / XML | View hierarchy, properties, images, resource IDs, RecyclerView / AdapterView metadata | No XML source navigation; only attached list items are captured |
| Jetpack Compose | Composition, layout, modifiers, parameters, and semantics in Debug; semantics fallback in Release | Tested with Compose UI / tooling-data 1.10.6; only placed Lazy items; no independent drawing-layer textures |

All inspection is read-only. Capturing does not invoke actions or modify properties. Missing data and partial results are reported in snapshot capabilities rather than presented as complete captures. Details are available in the [Chinese SDK guide](README.zh-CN.md) and [Android guide](android/README.md).

## iOS

Requires **iOS 15+**. In Xcode, add `https://github.com/FeliksLv01/ViewinSDK` as a Swift package and select the **ViewinSDK** product. Until version tags are published, use the `main` branch or a local checkout.

Start before creating the first SwiftUI host when inspecting SwiftUI:

```swift
import ViewinSDK

try Viewin.start()
// Viewin.stop()
```

The host explicitly decides whether to include and enable the SDK in Debug and internal Release builds. Optional `buildType: .debug` or `.internalRelease` reports the host’s declared build type; the default is `unknown`. It is diagnostic metadata, not authentication or a guarantee of capture capabilities.

SwiftUI capture attempts actual runtime reads regardless of that declaration. Unsupported or unavailable runtime data falls back to the UIKit host hierarchy. Debug and ordinary Release demo captures have been tested on the iOS 27 simulator; physical devices and other OS versions are not yet validated. Some leaves have real CALayer textures; other nodes only have collapsed-subtree composite crops. Expanded logical containers do not repeat the subtree image. Full Display List replay is not implemented.

## Android

Requires **API 29+**. Add the public Maven repository once, then choose one dependency. No GitHub login, token, source checkout, or SDK build plugins are needed. The repository serves standard AAR / JAR, POM, Gradle metadata, and source artifacts; this is not Maven Central.

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        exclusiveContent {
            forRepository {
                maven("https://raw.githubusercontent.com/FeliksLv01/ViewinSDK/maven")
            }
            filter { includeGroup("io.github.felikslv01.viewin") }
        }
    }
}
```

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("io.github.felikslv01.viewin:viewin-sdk:0.1.0")
    // Compose: use this instead; it includes the base SDK.
    // implementation("io.github.felikslv01.viewin:viewin-compose:0.1.0")
}
```

Use `viewin-sdk` for View apps, or `viewin-compose`, which includes the base SDK, for Compose apps.

Start in `Application.onCreate`, before the first `setContent` call:

```kotlin
Viewin.start(
    this,
    buildType = if (BuildConfig.DEBUG) Viewin.BuildType.DEBUG
                else Viewin.BuildType.INTERNAL_RELEASE
)
// Viewin.stop()
```

Consumers require compileSdk 36, Java 17 bytecode support, and a Kotlin compiler compatible with Kotlin 2.2.20 metadata. Compatibility checks cover AGP 8.13.0 and 9.1.1, View and Compose, Debug and minified Release. Older toolchains have not been verified. Compose dependencies currently use UI / tooling-data 1.10.6 and may upgrade an older host’s Compose libraries.

Compose Debug collection enables inspector data before compositions are created. Release builds fall back to semantics when composition data is unavailable. Actions remain read-only. See the [Android integration guide](android/README.md) for modules, RecyclerView metadata, explicit Dialog window registration, and rendering limits.

## Connection and agents

The SDK listens only on `127.0.0.1:48721` by default. Data is captured on request. Use Viewin or its CLI to discover apps and save a `.viewin` snapshot or export JSON and images.

- **iOS simulator:** direct local connection, verified.
- **Android emulator:** ADB forwarding, verified. Start the local ADB server using Android Studio or `adb start-server` first.
- **Android USB:** implemented, requires USB debugging authorization; physical-device validation is pending.
- **iOS USB and wireless pairing:** not implemented yet.

The CLI can discover and capture apps without opening Viewin. Install its agent skill through **Viewin → Settings → Agent**. The SDK does not require MCP.

## Repository

```text
Package.swift       # SwiftPM entry point; no third-party Swift dependencies
ios/
  SDK/              # UIKit / SwiftUI capture
  Protocol/         # Shared Swift models
  Transport/        # Length-prefixed Network transport
android/            # SDK, optional Compose module, protocol, and demo
protocol/           # JSON schema and contract fixtures
examples/ios/       # UIKit / SwiftUI demo and tests
```

For desktop development, place this checkout in a directory named `ViewinSDK` beside the desktop checkout. The desktop app uses the `ViewinProtocol` and `ViewinTransport` products; app integrations only need `ViewinSDK`.

- [Snapshot schema](protocol/schema/snapshot.schema.json)
- [Contract fixtures](protocol/fixtures/)
- [iOS demo](examples/ios/)
- [Android guide and demo](android/README.md)

The wire service identifier is `app.viewin.inspection`. Use matching desktop and SDK versions. Historical snapshot compatibility is handled by the desktop app.

## Development

Open `examples/ios/ViewinDemo.xcodeproj` and run the `ViewinDemo` scheme. Its `ViewinSDKTests` target covers UIKit events, SwiftUI decoding, runtime capture, and rendering associations. Regenerate with XcodeGen if changing `project.yml`; pipe `xcodebuild` output through `xcbeautify`.

For Android, use Android Studio’s bundled JDK and Android SDK 36. The project uses Gradle 9.3.1 and AGP 9.1.1 with Java 17 bytecode. Do not download or store a JDK in the repository. From `android/`, run:

```sh
./gradlew :viewin-protocol:test :demo:assembleDebug :demo:assembleRelease
```

The Release demo uses a development signature for internal validation. iOS framework / XCFramework distribution artifacts must use Git LFS; local build outputs, developer settings, and research notes are excluded from Git.

## Android Maven maintenance

The shared Android version is `viewinVersion` in `android/gradle.properties`. Run `android/gradlew -p android stageMaven` to stage all three modules, then `python3 scripts/publish-maven.py` to validate checksums and transitive dependencies without uploading.

The **Android Maven compatibility** workflow checks independent consumers against AGP 8 and 9. To publish, run it manually with `publish` enabled. Publication waits for both checks and pushes to the `maven` branch. Existing version directories cannot be overwritten; increment the version for a new release. `python3 scripts/publish-maven.py --push` provides the equivalent local upload after validation and a clean source commit. Source revisions and SHA-256 manifests are recorded under `versions/` on that branch. No Maven consumer credentials are required.

## References

Interaction and capture approaches draw inspiration from [Lookin](https://github.com/QMUI/Lookin), [LookInside](https://github.com/LookInsideApp/LookInside), and [CodeLocator](https://github.com/bytedance/CodeLocator). ViewinSDK implements its own protocol and collectors without embedding these projects’ runtime code. SwiftUI private APIs and runtime layouts may change across OS releases.

## License

[MIT](LICENSE). Gradle wrapper files retain their upstream Apache-2.0 notices.
