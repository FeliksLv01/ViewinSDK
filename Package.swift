// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ViewinSDK",
  platforms: [.iOS(.v15), .macOS(.v15)],
  products: [
    .library(name: "ViewinSDK", targets: ["ViewinSDK"]),
    // Shared with the desktop client; app integrations only select ViewinSDK.
    .library(name: "ViewinProtocol", targets: ["ViewinProtocol"]),
    .library(name: "ViewinTransport", targets: ["ViewinTransport"]),
  ],
  targets: [
    .target(name: "ViewinProtocol", path: "ios/Protocol"),
    .target(name: "ViewinTransport", path: "ios/Transport"),
    .target(name: "ViewinSDK", dependencies: ["ViewinProtocol", "ViewinTransport"], path: "ios/SDK"),
  ]
)
