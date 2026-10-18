#if canImport(UIKit)
  import UIKit
  import CryptoKit
  import ViewinProtocol

  @MainActor final class UIKitCollector {
    private let sessionID = UUID().uuidString
    var target: Target {
      #if DEBUG
        let buildType = "debug"
      #else
        let buildType = "internalRelease"
      #endif
      return Target(
        platform: "ios",
        deviceId: ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? UIDevice.current
          .identifierForVendor?.uuidString ?? "device",
        deviceName: ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
          ?? UIDevice.current.name,
        appId: Bundle.main.bundleIdentifier ?? "app",
        appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App",
        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
          as? String ?? "1", osVersion: UIDevice.current.systemVersion,
        buildType: buildType,
        frameworks: [.init(name: "UIKit", version: UIDevice.current.systemVersion)])
    }
    func previewImages() -> [(String, Data)] {
      guard UIApplication.shared.applicationState == .active,
        let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
          .flatMap(\.windows).first(where: \.isKeyWindow), window.bounds.width > 0,
        window.bounds.height > 0
      else { return [] }
      let format = UIGraphicsImageRendererFormat()
      format.scale = 440 / max(window.bounds.width, window.bounds.height)
      format.opaque = false
      let preview = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image {
        window.layer.render(in: $0.cgContext)
      }
      return preview.pngData().map { [("app-preview", $0)] } ?? []
    }

    struct Capture {
      let snapshot: Snapshot
      let images: [String: Data]
    }
    func capture() -> Capture {
      let started = ISO8601DateFormatter().string(from: Date())
      let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
        .sorted { $0.isKeyWindow && !$1.isKeyWindow }
      var nodes: [SnapshotNode] = []
      var resources: [ViewinProtocol.ImageResource] = []
      var images: [String: Data] = [:]
      var windowModels: [SnapshotWindow] = []
      var views: [UIView] = []
      func collect(_ view: UIView) {
        views.append(view)
        view.subviews.forEach(collect)
      }
      windows.forEach(collect)
      let references = UIKitProperties.memberReferences(in: views)
      func id(_ object: AnyObject) -> String {
        String(UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque()), radix: 16)
      }
      func image(_ view: UIView, solo: Bool) -> String? {
        guard !view.isHidden, view.alpha > 0, view.bounds.width > 0, view.bounds.height > 0 else {
          return nil
        }
        let longest = max(view.bounds.width, view.bounds.height)
        guard longest.isFinite, longest < 100_000 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(view.window?.screen.scale ?? 2, 1400 / longest)
        format.opaque = false
        let children = solo ? view.subviews.map { ($0, $0.isHidden) } : []
        defer { for (child, hidden) in children { child.isHidden = hidden } }
        for (child, _) in children { child.isHidden = true }
        let bitmap = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
          context.cgContext.translateBy(x: -view.bounds.minX, y: -view.bounds.minY)
          view.layer.render(in: context.cgContext)
        }
        guard let data = bitmap.pngData(), let cg = bitmap.cgImage else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if images[key] == nil {
          images[key] = data
          resources.append(
            .init(
              id: key, path: "images/\(key).png", mimeType: "image/png", pixelWidth: cg.width,
              pixelHeight: cg.height))
        }
        return key
      }
      func rect(_ r: CGRect) -> LayoutRect {
        .init(x: r.minX, y: r.minY, width: r.width, height: r.height)
      }
      func visit(_ view: UIView, window: UIWindow, parent: String?) {
        let key = id(view)
        let group = autoreleasepool { image(view, solo: false) }
        let solo = view.subviews.isEmpty ? group : autoreleasepool { image(view, solo: true) }
        let bounds = view.bounds
        let corners = [
          CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
          CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
        ]
        .map { view.convert($0, to: window) }.map { LayoutPoint(x: $0.x, y: $0.y) }
        let type = NSStringFromClass(type(of: view))
        var identifiers = ["objectAddress": "0x" + key]
        if let value = view.accessibilityIdentifier {
          identifiers["accessibilityIdentifier"] = value
        }
        let kind =
          view is UIWindow
          ? "window"
          : view is UILabel
            ? "text"
            : view is UIButton
              ? "button"
              : view is UIImageView
                ? "image" : view is UIStackView ? "stack" : view is UIScrollView ? "scroll" : "view"
        nodes.append(
          SnapshotNode(
            id: key, windowId: id(window), parentId: parent, childIds: view.subviews.map(id),
            framework: "uikit", kind: kind, typeName: type,
            name: type.components(separatedBy: ".").last ?? type,
            identifiers: identifiers,
            geometry: .init(
              localBounds: rect(bounds), frameInWindow: rect(view.convert(bounds, to: window)),
              cornersInWindow: corners, clipInWindow: nil),
            visibility: .init(hidden: view.isHidden, alpha: view.alpha),
            properties: UIKitProperties.groups(
              for: view, references: references[ObjectIdentifier(view)] ?? [],
              eventReferences: references), sourceLocation: nil,
            imageId: solo, groupImageId: group))
        for child in view.subviews { visit(child, window: window, parent: key) }
      }
      for window in windows {
        visit(window, window: window, parent: nil)
        windowModels.append(
          .init(
            id: id(window),
            title: window.isKeyWindow ? "KeyWindow" : NSStringFromClass(type(of: window)),
            size: .init(width: window.bounds.width, height: window.bounds.height), unit: "pt",
            pixelsPerUnit: window.screen.scale, rootNodeIds: [id(window)],
            screenshotId: nodes.first { $0.id == id(window) }?.groupImageId))
      }
      let done = ISO8601DateFormatter().string(from: Date())
      let snapshot = Snapshot(
        protocolVersion: .current, snapshotId: UUID().uuidString, sessionId: sessionID,
        capturedAt: done, source: "runtime",
        target: target,
        capabilities: [
          .init(name: "uikit.hierarchy", status: "supported", reason: nil),
          .init(name: "view.images", status: "supported", reason: nil),
          .init(name: "swiftui.logicalTree", status: "unsupported", reason: "当前仅采集 UIKit 宿主视图。"),
        ],
        capture: .init(
          startedAt: started, completedAt: done, completeness: "complete",
          consistency: "bestEffort",
          warnings: [
            .init(
              code: "layer-rendering", message: "截图使用 CALayer.render，部分系统特效和外部渲染表面可能无法完整呈现。",
              nodeId: nil)
          ]),
        windows: windowModels, nodes: nodes, relations: [], images: resources)
      return Capture(snapshot: snapshot, images: images)
    }
  }
#endif
