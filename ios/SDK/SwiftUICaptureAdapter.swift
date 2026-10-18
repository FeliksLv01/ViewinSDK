#if canImport(UIKit)
import UIKit
import ViewinProtocol

@MainActor enum SwiftUICaptureAdapter {
  struct Result {
    let nodes: [SnapshotNode]
    let roots: [String]
    let relations: [NodeRelation]
    let reason: String?
    let truncated: Bool
    let imageCount: Int
    let renderBindings: Int
    let renderRelations: Int
    let renderImages: Int
    let renderReason: String?
  }

  static func capture(host: UIView, window: UIWindow, hostId: String, screenshot: Data?,
                      storeImage: (CGImage) -> String?) -> Result {
    var hostDepth = 0
    var ancestor = host.superview
    while let parent = ancestor { hostDepth += 1; ancestor = parent.superview }
    let capture = SwiftUIRuntime.capture(host, maxDepth: max(0, 126 - hostDepth))
    func id(_ path: String) -> String { "\(hostId):swiftui:\(path)" }
    let bitmap = screenshot.flatMap { UIImage(data: $0)?.cgImage }
    var imageCount = 0
    func property(_ id: String, _ title: String, _ value: JSONValue, kind: String = "scalar") -> NodeProperty {
      .init(id: id, title: title, value: value, availability: "available", reason: nil,
            presentation: .init(kind: kind))
    }
    func rect(_ value: CGRect) -> JSONValue {
      .object(["x": .number(value.minX), "y": .number(value.minY), "width": .number(value.width), "height": .number(value.height)])
    }
    // Debug transforms include the UIKit hosting origin. Anchor the graph once
    // before converting host coordinates to the window, rather than adding it twice.
    let canvas = capture.canvasFrame
    let origin = canvas.flatMap { frame -> CGPoint? in
      guard abs(frame.width - host.bounds.width) < 1,
            abs(frame.height - host.bounds.height) < 1 else { return nil }
      return CGPoint(x: frame.minX - host.bounds.minX, y: frame.minY - host.bounds.minY)
    }
    let nodes = capture.nodes.map { value -> SnapshotNode in
      var geometry: NodeGeometry?
      var imageId: String?
      var properties = value.properties
      if let origin, let rawFrame = value.hostFrame {
        let frame = rawFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        if frame.width.isFinite, frame.height.isFinite,
           frame.minX.isFinite, frame.minY.isFinite, frame.width <= 100_000, frame.height <= 100_000 {
          let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
            .map { host.convert($0, to: window) }.map { LayoutPoint(x: $0.x, y: $0.y) }
          let inWindow = host.convert(frame, to: window)
          geometry = .init(localBounds: .init(x: 0, y: 0, width: frame.width, height: frame.height),
            frameInWindow: .init(x: inWindow.minX, y: inWindow.minY, width: inWindow.width, height: inWindow.height),
            cornersInWindow: corners, clipInWindow: nil)
          properties.append(.init(id: "layout", title: "Layout", properties: [
            property("frame", "Frame", rect(inWindow), kind: "rect"),
            property("hostFrame", "Frame in Hosting View", rect(frame), kind: "rect"),
          ]))
          if let bitmap, frame.width > 0, frame.height > 0, host.bounds.contains(frame),
             host.bounds.width > 0, host.bounds.height > 0 {
            let sx = CGFloat(bitmap.width) / host.bounds.width
            let sy = CGFloat(bitmap.height) / host.bounds.height
            let crop = CGRect(x: (frame.minX - host.bounds.minX) * sx, y: (frame.minY - host.bounds.minY) * sy,
                              width: frame.width * sx, height: frame.height * sy).integral
            if let pixels = bitmap.cropping(to: crop) {
              imageId = storeImage(pixels)
              if imageId != nil { imageCount += 1 }
            }
          }
        }
      }
      if imageId != nil {
        properties.append(.init(id: "rendering", title: "Rendering", properties: [
          property("imageRepresentation", "Image Source", .string("Hosting View 合成截图裁切；不是独立渲染图层"))
        ]))
      }
      return .init(id: id(value.path), windowId: String(UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()), radix: 16),
        parentId: value.parentPath.map(id) ?? hostId, childIds: value.children.map(id), framework: "swiftui",
        kind: value.kind, typeName: value.type, name: value.name,
        identifiers: ["hostingViewId": hostId, "identityScope": "capturePath"], geometry: geometry,
        visibility: .init(hidden: host.isHidden, alpha: host.alpha), properties: properties, sourceLocation: nil,
        imageId: nil, groupImageId: imageId)
    }
    let roots = capture.nodes.filter { $0.parentPath == nil }.map { id($0.path) }
    let rendered = SwiftUIRenderCapture.export(host: host, window: window, hostId: hostId,
      logical: nodes, storeImage: storeImage)
    let associated = SwiftUIRenderAssociation.applyingImages(to: nodes, rendering: rendered.nodes, relations: rendered.relations)
    return .init(nodes: associated + rendered.nodes, roots: roots + rendered.roots,
      relations: roots.map { .init(fromNodeId: $0, toNodeId: hostId, kind: "hostedBy") } + rendered.relations,
      reason: capture.reason, truncated: capture.truncated || rendered.truncated, imageCount: imageCount,
      renderBindings: rendered.bindingCount, renderRelations: rendered.inferredCount, renderImages: rendered.layerImages,
      renderReason: rendered.reason)
  }
}
#endif
