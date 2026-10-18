#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import ViewinProtocol

/// Read-only, version-scoped reflection. No assumed Swift heap offsets or KVC.
@MainActor enum SwiftUIRenderCapture {
  struct Item {
    let path: String
    let parent: String?
    let identity: UInt32
    let kind: String
    let layer: CALayer?
    var identityInherited = false
  }
  struct Result {
    var items: [Item] = []
    var truncated = false
    var reason: String?
  }
  static func field(_ object: Any, _ label: String) -> Any? {
    Mirror(reflecting: object).children.first { $0.label == label }?.value
  }
  private static func unwrap(_ object: Any?) -> Any? {
    guard let object else { return nil }
    let mirror = Mirror(reflecting: object)
    return mirror.displayStyle == .optional ? mirror.children.first?.value : object
  }
  private static func identity(_ object: Any?) -> UInt32? {
    guard let object, let value = field(object, "value") as? UInt32,
          value > 0, value < UInt32.max else { return nil }
    return value
  }
  static func layerIdentity(_ layer: CALayer) -> UInt32? {
    guard SwiftUIRuntime.canAttemptInspection else { return nil }
    let selector = NSSelectorFromString("swiftUI_displayListID")
    guard let method = class_getInstanceMethod(type(of: layer), selector),
          method_getNumberOfArguments(method) == 2 else { return nil }
    let encoding = method_copyReturnType(method)
    defer { free(encoding) }
    guard String(cString: encoding) == "q" else { return nil }
    let getter = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (AnyObject, Selector) -> Int64).self)
    let value = getter(layer, selector)
    guard value > 0, value < Int64(UInt32.max) else { return nil }
    return UInt32(value)
  }
  static func read(host: UIView, maxDepth: Int = 64) -> Result {
    let depthLimit = min(64, max(0, maxDepth))
    guard SwiftUIRuntime.canAttemptInspection,
          let base = field(host, "_base"), String(reflecting: type(of: base)) == "UIKit.UIHostingViewBase",
          let graph = field(base, "viewGraph"), let renderer = field(graph, "renderer"),
          let updater = unwrap(field(renderer, "renderer")),
          String(reflecting: type(of: updater)).contains("DisplayList.ViewUpdater"),
          let cache = field(updater, "viewCache"), let map = field(cache, "map"),
          Mirror(reflecting: map).displayStyle == .dictionary,
          let list = field(updater, "lastList") else {
      return .init(reason: "此运行时未提供受支持的 SwiftUI 渲染缓存。")
    }
    var result = Result()
    var bindings: [UInt32: [CALayer]] = [:]
    for entry in Mirror(reflecting: map).children.prefix(512) {
      guard let key = field(entry.value, "key"), let index = field(key, "id"),
            let id = identity(field(index, "identity")),
            let value = field(entry.value, "value"),
            field(value, "isRemoved") as? Bool == false, field(value, "isInvalid") as? Bool == false,
            let layer = field(value, "layer") as? CALayer else { continue }
      // The cache can contain platform views belonging to another host.
      var cursor: CALayer? = layer
      var owned = false
      for _ in 0..<128 {
        guard let current = cursor else { break }
        if current === host.layer { owned = true; break }
        cursor = current.superlayer
      }
      guard owned else { continue }
      if !(bindings[id] ?? []).contains(where: { $0 === layer }) { bindings[id, default: []].append(layer) }
    }
    if Mirror(reflecting: map).children.count > 512 { result.truncated = true }
    func walk(_ list: Any, parent: String?, prefix: String, depth: Int) {
      guard depth < depthLimit, result.items.count < 512, let items = field(list, "items") else {
        result.truncated = true; return
      }
      for (offset, element) in Mirror(reflecting: items).children.enumerated() {
        guard result.items.count < 512 else { result.truncated = true; break }
        let item = element.value
        let path = "\(prefix).\(offset)"
        let id = identity(field(item, "identity")) ?? 0
        let value = field(item, "value")
        let variant = value.flatMap { Mirror(reflecting: $0).children.first }
        var kind = variant?.label ?? "unknown"
        var nested: Any?
        if variant?.label == "content", let content = variant?.value,
           let contentValue = field(content, "value") {
          kind = Mirror(reflecting: contentValue).children.first?.label ?? "content"
        } else if variant?.label == "effect", let effect = variant?.value {
          nested = field(effect, ".1")
          if let effectValue = field(effect, ".0") {
            let reflected = Mirror(reflecting: effectValue)
            kind = reflected.children.first?.label ?? String(describing: effectValue)
          }
        }
        let layers = bindings[id] ?? []
        result.items.append(.init(path: path, parent: parent, identity: id, kind: kind,
                                  layer: layers.count == 1 ? layers[0] : nil))
        if let nested { walk(nested, parent: path, prefix: path, depth: depth + 1) }
      }
    }
    walk(list, parent: nil, prefix: "render", depth: 0)
    // Anonymous content inside an identity effect inherits its parent's cache binding.
    let byPath = Dictionary(uniqueKeysWithValues: result.items.map { ($0.path, $0) })
    result.items = result.items.map { item in
      guard item.identity == 0, let parent = item.parent, let owner = byPath[parent],
            owner.kind == "identity", let layer = owner.layer else { return item }
      return .init(path: item.path, parent: item.parent, identity: owner.identity, kind: item.kind, layer: layer, identityInherited: true)
    }
    if result.items.isEmpty { result.reason = "渲染器尚未完成本帧 Display List。" }
    return result
  }

  struct Export {
    let nodes: [SnapshotNode]
    let roots: [String]
    let relations: [NodeRelation]
    let bindingCount: Int
    let inferredCount: Int
    let layerImages: Int
    let truncated: Bool
    let reason: String?
  }
  static func export(host: UIView, window: UIWindow, hostId: String, logical: [SnapshotNode],
                     storeImage: (CGImage) -> String?) -> Export {
    var hostDepth = 0
    var ancestor = host.superview
    while let parent = ancestor { hostDepth += 1; ancestor = parent.superview }
    let capture = read(host: host, maxDepth: max(0, 126 - hostDepth))
    func id(_ path: String) -> String { "\(hostId):\(path)" }
    func property(_ id: String, _ title: String, _ value: JSONValue) -> NodeProperty {
      .init(id: id, title: title, value: value, availability: "available", reason: nil)
    }
    var layerImages: [ObjectIdentifier: String] = [:]
    let nodes: [SnapshotNode] = capture.items.map { item in
      var properties = [property("displayListId", "Display List ID", .integer(Int64(item.identity))),
                        property("renderKind", "Content", .string(item.kind)),
                        property("identityScope", "Identity Scope", .string(item.identityInherited ? "inheritedIdentityEffect" : "itemIdentity"))]
      var geometry: NodeGeometry?
      var groupImage: String?
      var address: String?
      if let layer = item.layer {
        address = "0x" + String(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque()), radix: 16)
        properties += [property("backingLayerAddress", "CALayer", .string(address!)),
                       property("bindingSource", "Binding Source", .string("SwiftUI renderer viewCache"))]
        let frame = layer.convert(layer.bounds, to: window.layer)
        let bounds = layer.bounds
        let corners = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                       CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
          .map { layer.convert($0, to: window.layer) }.map { LayoutPoint(x: $0.x, y: $0.y) }
        if [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) {
          geometry = .init(localBounds: .init(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
            frameInWindow: .init(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
            cornersInWindow: corners, clipInWindow: nil)
        }
        if let cached = layerImages[ObjectIdentifier(layer)] { groupImage = cached }
        else if !layer.isHidden, layer.opacity > 0, bounds.width > 0, bounds.height > 0,
           bounds.width.isFinite, bounds.height.isFinite, max(bounds.width, bounds.height) < 100_000 {
          let format = UIGraphicsImageRendererFormat()
          format.scale = min(window.screen.scale, 1400 / max(bounds.width, bounds.height))
          format.opaque = false
          let bitmap = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
            layer.render(in: context.cgContext)
          }
          if let cg = bitmap.cgImage {
            groupImage = storeImage(cg)
            if let groupImage { layerImages[ObjectIdentifier(layer)] = groupImage }
          }
        }
      }
      if let layer = item.layer, let taggedId = layerIdentity(layer) {
        properties.append(property("layerDisplayListId", "CALayer Display List ID", .integer(Int64(taggedId))))
      }
      var identifiers = address.map { ["objectAddress": $0] } ?? [:]
      if item.parent == nil { identifiers["renderingRoot"] = "true" }
      let rendering = [property("imageRepresentation", "Image Source", .string("真实 CALayer 子树；不等同于独立 SwiftUI View"))]
      return .init(id: id(item.path), windowId: String(UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()), radix: 16),
        parentId: item.parent.map(id) ?? hostId,
        childIds: capture.items.filter { $0.parent == item.path }.map { id($0.path) },
        framework: "swiftuiRendering", kind: "renderItem", typeName: item.layer.map { NSStringFromClass(type(of: $0)) } ?? "SwiftUI.DisplayList.Item",
        name: item.parent == nil ? "SwiftUI 渲染图层" : "\(item.kind) · #\(item.identity)", identifiers: identifiers, geometry: geometry,
        visibility: .init(hidden: item.layer?.isHidden ?? false, alpha: Double(item.layer?.opacity ?? 1)), properties: [.init(id: "swiftuiRendering", title: "SwiftUI Rendering", properties: properties),
          .init(id: "rendering", title: "Rendering", properties: rendering),
          .init(id: "hierarchy", title: "Hierarchy", properties: [property("hierarchyHints", "Hierarchy", .object(["prefersCollapse": .bool(true)]))])], sourceLocation: nil,
        imageId: item.layer?.sublayers?.isEmpty != false && !capture.items.contains(where: { $0.parent == item.path && $0.layer != nil && $0.layer === item.layer }) ? groupImage : nil, groupImageId: groupImage)
    }
    let relations = SwiftUIRenderAssociation.resolve(logical: logical, rendering: nodes)
    return .init(nodes: nodes, roots: capture.items.filter { $0.parent == nil }.map { id($0.path) }, relations: relations,
      bindingCount: capture.items.filter { $0.layer != nil }.count, inferredCount: relations.count, layerImages: layerImages.count,
      truncated: capture.truncated, reason: capture.reason)
  }
}
#endif
