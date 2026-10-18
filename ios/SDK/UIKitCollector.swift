#if canImport(UIKit)
  import UIKit
  import CryptoKit
  import ViewinProtocol

  @MainActor final class UIKitCollector {
    private let sessionID = UUID().uuidString
    private let buildType: ViewinBuildType
    init(buildType: ViewinBuildType = .unknown) { self.buildType = buildType }
    var target: Target {
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
        buildType: buildType.rawValue,
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
      var relations: [NodeRelation] = []
      var swiftUIHosts = 0
      var capturedSwiftUIHosts = 0
      var swiftUIIssues = Set<String>()
      var swiftUIGeometry = 0
      var swiftUINodes = 0
      var swiftUIRenderBindings = 0
      var swiftUIRenderRelations = 0
      var swiftUIRenderImages = 0
      var swiftUIRenderIssues = Set<String>()
      var swiftUIImages = 0
      var swiftUITruncated = false
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
        return store(data, cg: cg)
      }
      func store(_ data: Data, cg: CGImage) -> String {
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
        var logical: SwiftUICaptureAdapter.Result?
        if SwiftUIRuntime.isHostingView(view) {
          swiftUIHosts += 1
          logical = SwiftUICaptureAdapter.capture(host: view, window: window, hostId: key,
            screenshot: group.flatMap { images[$0] }) { cg in
              guard let data = UIImage(cgImage: cg).pngData() else { return nil }
              return store(data, cg: cg)
            }
          if let logical {
            if logical.nodes.contains(where: { $0.framework == "swiftui" }) { capturedSwiftUIHosts += 1 }
            swiftUINodes += logical.nodes.filter { $0.framework == "swiftui" }.count
            swiftUIGeometry += logical.nodes.filter { $0.framework == "swiftui" && $0.geometry != nil }.count
            swiftUIImages += logical.imageCount
            swiftUIRenderBindings += logical.renderBindings
            swiftUIRenderRelations += logical.renderRelations
            swiftUIRenderImages += logical.renderImages
            if let reason = logical.renderReason { swiftUIRenderIssues.insert(reason) }
            swiftUITruncated = swiftUITruncated || logical.truncated
            if let reason = logical.reason { swiftUIIssues.insert(reason) }
            relations.append(contentsOf: logical.relations)
          }
        }
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
        var propertyGroups = UIKitProperties.groups(
          for: view, references: references[ObjectIdentifier(view)] ?? [], eventReferences: references)
        if let logical {
          propertyGroups.append(.init(id: "swiftuiSupport", title: "SwiftUI", properties: [
            .init(id: "swiftuiBackend", title: "Backend", value: .string(logical.nodes.contains(where: { $0.framework == "swiftui" }) ? "SwiftUI Runtime" : "UIKit Hosting View"),
                  availability: "available", reason: nil),
            .init(id: "swiftuiLogicalTree", title: "Logical Tree", value: .string("\(logical.nodes.filter { $0.framework == "swiftui" }.count) nodes"),
                  availability: logical.nodes.contains(where: { $0.framework == "swiftui" }) ? "available" : "unavailable", reason: logical.reason),
          ]))
        }
        nodes.append(
          SnapshotNode(
            id: key, windowId: id(window), parentId: parent, childIds: view.subviews.map(id) + (logical?.roots ?? []),
            framework: "uikit", kind: kind, typeName: type,
            name: type.components(separatedBy: ".").last ?? type,
            identifiers: identifiers,
            geometry: .init(
              localBounds: rect(bounds), frameInWindow: rect(view.convert(bounds, to: window)),
              cornersInWindow: corners, clipInWindow: nil),
            visibility: .init(hidden: view.isHidden, alpha: view.alpha),
            properties: propertyGroups, sourceLocation: nil,
            // A hosting view draws its SwiftUI descendants without UIKit subviews.
            // Its "solo" UIKit image therefore still contains the whole composition.
            imageId: logical?.nodes.contains(where: { $0.framework == "swiftui" }) == true ? nil : solo,
            groupImageId: group))
        for child in view.subviews { visit(child, window: window, parent: key) }
        if let logical { nodes.append(contentsOf: logical.nodes) }
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
      // Texture promotion can orphan a composed crop. Do not retain or transmit it.
      let usedImages = Set(nodes.flatMap { [$0.imageId, $0.groupImageId].compactMap { $0 } }
        + windowModels.compactMap(\.screenshotId))
      resources.removeAll { !usedImages.contains($0.id) }
      images = images.filter { usedImages.contains($0.key) }
      let logicalLayerImages = nodes.filter { $0.framework == "swiftui" && $0.properties
        .flatMap(\.properties).contains { $0.id == "associationConfidence" && $0.value == .string("geometryInference") } }.count
      let done = ISO8601DateFormatter().string(from: Date())
      let swiftUIReason = swiftUIHosts == 0 ? "当前页面没有 SwiftUI 宿主。" : swiftUIIssues.sorted().joined(separator: "；")
      let logicalStatus = capturedSwiftUIHosts == 0 ? "unsupported"
        : (capturedSwiftUIHosts < swiftUIHosts || swiftUITruncated) ? "partial" : "supported"
      let snapshot = Snapshot(
        protocolVersion: .current, snapshotId: UUID().uuidString, sessionId: sessionID,
        capturedAt: done, source: "runtime",
        target: target,
        capabilities: [
          .init(name: "uikit.hierarchy", status: "supported", reason: nil),
          .init(name: "view.images", status: "supported", reason: nil),
           .init(name: "swiftui.logicalTree", status: logicalStatus, reason: swiftUIReason.isEmpty ? nil : swiftUIReason),
          .init(name: "swiftui.backend", status: capturedSwiftUIHosts > 0 ? "supported" : "partial",
                reason: capturedSwiftUIHosts > 0 ? "runtimeData" : "hostOnly"),
          .init(name: "swiftui.geometry", status: swiftUIGeometry == 0 ? "unsupported" : "partial",
                reason: "\(swiftUINodes) 个逻辑节点中 \(swiftUIGeometry) 个具有可解析的布局；仅支持已验证的坐标变换。"),
          .init(name: "swiftui.compositedImages", status: swiftUIImages == 0 ? "unsupported" : "partial",
                reason: "\(swiftUIImages) 份宿主合成截图裁切，不是独立图层纹理。"),
          .init(name: "swiftui.layerBindings", status: swiftUIRenderBindings > 0 ? "partial" : "unsupported",
                reason: "\(swiftUIRenderBindings) 个渲染项通过 ViewCache 关联 CALayer；\(swiftUIRenderRelations) 个逻辑视图通过唯一几何/内容类型推断关联。" + swiftUIRenderIssues.sorted().joined(separator: "；")),
          .init(name: "swiftui.layerImages", status: swiftUIRenderImages > 0 ? "partial" : "unsupported",
                reason: "\(swiftUIRenderImages) 份实际 CALayer 子树截图。"),
          .init(name: "swiftui.logicalLayerImages", status: logicalLayerImages > 0 ? "partial" : "unsupported",
                reason: "\(logicalLayerImages) 个逻辑叶子节点使用唯一类型/几何推断关联的真实图层纹理；其余保留合成图。"),
          .init(name: "swiftui.independentImages", status: "unsupported", reason: "已有 CALayer 子树图像；尚不保证逐 SwiftUI View 独立像素或 Display List 重放。"),
          .init(name: "swiftui.gestures", status: capturedSwiftUIHosts > 0 ? "partial" : "unsupported",
                reason: "仅识别调试树中可见的静态手势 modifier；不保证完整枚举或命中区域。"),
          .init(name: "swiftui.gestureEvents", status: "unsupported", reason: "当前仅提取调试树中的静态手势描述，未启用执行事件录制。"),
        ],
        capture: .init(
          startedAt: started, completedAt: done, completeness: swiftUITruncated ? "partial" : "complete",
          consistency: "bestEffort",
          warnings: [
            .init(
              code: "layer-rendering", message: "截图使用 CALayer.render，部分系统特效和外部渲染表面可能无法完整呈现。",
              nodeId: nil)
          ]),
        windows: windowModels, nodes: nodes, relations: relations, images: resources)
      return Capture(snapshot: snapshot, images: images)
    }
  }
#endif
