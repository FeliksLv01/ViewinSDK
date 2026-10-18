#if canImport(UIKit)
import UIKit
import ViewinProtocol

/// Version-scoped decoder for the system's debug representation, never a mirror of View.body.
@MainActor enum SwiftUIDebugDecoder {
  struct Node {
    let path: String
    let parentPath: String?
    let children: [String]
    let type: String
    let name: String
    let kind: String
    let hostFrame: CGRect?
    let properties: [PropertyGroup]
  }
  struct Result {
    var nodes: [Node] = []
    var truncated = false
    var canvasFrame: CGRect?
  }

  static func decode(_ data: Data, maxDepth: Int = 112) throws -> Result {
    let depthLimit = min(126, max(0, maxDepth))
    guard data.count <= 8 * 1024 * 1024,
          let roots = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw CocoaError(.coderReadCorrupt)
    }
    var result = Result()
    func property(_ id: String, _ title: String, _ value: JSONValue, kind: String = "scalar") -> NodeProperty {
      .init(id: id, title: title, value: value, availability: "available", reason: nil,
            presentation: .init(kind: kind))
    }
    func pair(_ value: Any?) -> CGPoint? {
      guard let values = value as? [NSNumber], values.count == 2,
            values.allSatisfy({ $0.doubleValue.isFinite }) else { return nil }
      return CGPoint(x: values[0].doubleValue, y: values[1].doubleValue)
    }
    // Position is in the host graph's coordinate space, not relative to the
    // preceding logical node. A supplied transform replaces the inherited one.
    func translation(_ value: Any?) -> CGPoint? {
      guard let transform = value as? [String: Any], let items = transform["items"] as? [[String: Any]] else { return nil }
      var offset = pair(transform["positionAdjustment"]) ?? .zero
      for item in items {
        if item.isEmpty { continue }
        if let delta = pair(item["translation"]) {
          offset.x += delta.x; offset.y += delta.y
        } else if item.keys.allSatisfy({ ["space", "sizedSpace"].contains($0) }) {
          continue
        } else { return nil }
      }
      return offset
    }
    func visit(_ raw: [String: Any], path: String, parent: String?, inherited: CGPoint?, depth: Int) {
      guard depth <= 240, result.nodes.count < 5000 else { result.truncated = true; return }
      var attributes: [Int: [String: Any]] = [:]
      for value in raw["properties"] as? [[String: Any]] ?? [] {
        if let id = value["id"] as? Int, let attribute = value["attribute"] as? [String: Any] { attributes[id] = attribute }
      }
      let type = attributes[0]?["type"] as? String ?? attributes[1]?["type"] as? String ?? "SwiftUI.Unknown"
      let base = String(type.split(separator: "<", maxSplits: 1).first ?? Substring(type))
      let name = base.hasPrefix("SwiftUI.") ? String(base.dropFirst(8)) : base
      let modifier = name.contains("Modifier") || name == "ModifiedContent"
      let kind = name == "Text" ? "text" : name == "Image" ? "image"
        : name.contains("Stack") ? "stack" : name.contains("Button") ? "button" : modifier ? "modifier" : "component"
      let offset = attributes[2] == nil ? inherited : translation(attributes[2]?["value"])
      var frame: CGRect?
      if let position = pair(attributes[3]?["value"]), let size = pair(attributes[4]?["value"]),
         let offset, size.x >= 0, size.y >= 0 {
        frame = CGRect(x: position.x + offset.x, y: position.y + offset.y, width: size.x, height: size.y)
      }
      var properties = [property("swiftuiType", "Type", .string(type)),
        property("captureBackend", "Backend", .string("SwiftUI Runtime"))]
      // Preserve bounded scalar modifier fields; do not expose the raw debug JSON
      // or display-list payload as an inspector value.
      var scalarCount = 0
      func scalars(_ attribute: [String: Any], prefix: String, depth: Int) {
        guard depth < 6, scalarCount < 40 else { return }
        if let value = attribute["value"], value is String || value is NSNumber {
          let json = (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
            .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
          if let json {
            scalarCount += 1
            let label = prefix.isEmpty ? "Value" : prefix
            let bounded: JSONValue
            if case .string(let text) = json { bounded = .string(String(text.prefix(2000))) }
            else { bounded = json }
            properties.append(property("value.\(scalarCount)", label, bounded))
          }
        }
        for child in attribute["subattributes"] as? [[String: Any]] ?? [] {
          let name = child["name"] as? String ?? "value"
          scalars(child, prefix: prefix.isEmpty ? name : "\(prefix).\(name)", depth: depth + 1)
        }
      }
      if let value = attributes[1] { scalars(value, prefix: "", depth: 0) }
      if frame == nil {
        properties.append(.init(id: "geometryStatus", title: "Geometry", value: .null,
          availability: "unavailable", reason: "此逻辑节点没有独立布局数据，或变换尚不支持。"))
      }
      let isGesture = modifier && name != "ModifiedContent" && name.contains("Gesture")
      if isGesture {
        let gestureTypes = ["SpatialTapGesture", "TapGesture", "LongPressGesture", "DragGesture", "MagnifyGesture", "RotateGesture"]
          .filter { type.contains($0) }
        let composition = ["SimultaneousGesture", "SequenceGesture", "ExclusiveGesture"].filter { type.contains($0) }
        let handler: JSONValue = .object([
          "handlerType": .string("gesture"), "origin": .string("swiftuiRuntime"), "typeName": .string(type),
          "gestureType": .string(gestureTypes.isEmpty ? name : gestureTypes.joined(separator: ", ")),
          "composition": .string(composition.isEmpty ? "未提供" : composition.joined(separator: ", ")),
          "handlerDescription": .string("Swift 闭包，无法按 UIKit Target/Action 枚举"),
        ])
        properties.append(property("eventHandlers", "手势", .array([handler])))
      }
      let rawChildren = raw["children"] as? [[String: Any]] ?? []
      let index = result.nodes.count
      result.nodes.append(.init(path: path, parentPath: parent, children: [], type: type, name: name,
        kind: kind, hostFrame: frame, properties: [.init(id: "swiftui", title: "SwiftUI", properties: properties)]))
      var children: [String] = []
      for (childIndex, child) in rawChildren.enumerated() {
        guard result.nodes.count < 5000, depth < 240 else { result.truncated = true; break }
        let childPath = "\(path).\(childIndex)"
        children.append(childPath)
        visit(child, path: childPath, parent: path, inherited: offset, depth: depth + 1)
      }
      let node = result.nodes[index]
      result.nodes[index] = .init(path: node.path, parentPath: node.parentPath, children: children,
        type: node.type, name: node.name, kind: node.kind, hostFrame: node.hostFrame, properties: node.properties)
    }
    for (index, root) in roots.enumerated() { visit(root, path: "\(index)", parent: nil, inherited: .zero, depth: 0) }
    var projected = SwiftUITreeProjection.project(result.nodes, maxDepth: depthLimit)
    projected.truncated = projected.truncated || result.truncated
    return projected
  }
}
#endif
