#if canImport(UIKit)
import UIKit
import ViewinProtocol

/// Projects runtime implementation details into a view tree. Wrapper paths stay
/// in modifier group IDs so attributes remain traceable without becoming rows.
@MainActor enum SwiftUITreeProjection {
  typealias Node = SwiftUIDebugDecoder.Node

  static func project(_ raw: [Node], maxDepth: Int) -> SwiftUIDebugDecoder.Result {
    let byPath = Dictionary(uniqueKeysWithValues: raw.map { ($0.path, $0) })
    var result = SwiftUIDebugDecoder.Result()
    result.canvasFrame = raw.first(where: { $0.parentPath == nil })?.hostFrame
    let structural: Set<String> = [
      "ModifiedContent", "StaticIf", "EmptyModifier", "ResolvedLabelStyle",
      "StyledTextContentView", "MergePlatformItemsView", "CountViews",
    ]
    let modifierTitles = [
      "_SafeAreaInsetsModifier": "Safe Area", "_OpacityEffect": "Opacity",
      "_OffsetEffect": "Offset", "_TransformEffect": "Transform",
      "_RotationEffect": "Rotation", "_ScaleEffect": "Scale", "_ShadowEffect": "Shadow",
      "AccessibilityAttachmentModifier": "Accessibility", "_PaddingLayout": "Padding", "_FrameLayout": "Frame", "_FlexFrameLayout": "Frame",
      "_BackgroundStyleModifier": "Background", "_ForegroundStyleModifier": "Foreground Style",
      "_ClipEffect": "Clip Shape", "_ContentShapeModifier": "Content Shape",
      "ContentShapeModifier_v2": "Content Shape", "_EnvironmentKeyWritingModifier": "Environment",
    ]
    func displayName(_ node: Node) -> String {
      if node.name == "_ShapeView" {
        for shape in ["RoundedRectangle", "UnevenRoundedRectangle", "Rectangle", "Circle", "Ellipse", "Capsule"]
        where node.type.contains("SwiftUI.\(shape)") { return shape }
      }
      return node.name
    }
    func isView(_ node: Node, parent: String?) -> Bool {
      if node.type.hasPrefix("(extension in SwiftUI):") { return false }
      guard node.type.hasPrefix("SwiftUI.") else { return true }
      if node.name == "_ShapeView" { return true }
      if structural.contains(node.name) || node.name.hasPrefix("_")
        || node.name.contains("Modifier") || node.name.contains("(unknown context") { return false }
      // Label's style pipeline can produce repeated Label wrappers for one view.
      if node.name == "Label", let parent,
         result.nodes.first(where: { $0.path == parent })?.name == "Label" { return false }
      return true
    }
    func modifierProperties(_ wrappers: [Node]) -> ([PropertyGroup], [JSONValue]) {
      var groups: [PropertyGroup] = []
      var gestures: [JSONValue] = []
      for wrapper in wrappers {
        let fields = wrapper.properties.flatMap(\.properties)
        for field in fields where field.id == "eventHandlers" {
          if case .array(let handlers) = field.value { gestures.append(contentsOf: handlers) }
        }
        let values = fields.filter { $0.id.hasPrefix("value.") }
        guard modifierTitles[wrapper.name] != nil else { continue }
        guard groups.count < 32 else { continue }
        let type = NodeProperty(id: "modifierType", title: "Type", value: .string(wrapper.type),
                                availability: "available", reason: nil)
        groups.append(.init(id: "modifier:\(wrapper.path)",
          title: modifierTitles[wrapper.name] ?? wrapper.name, properties: [type] + values))
      }
      return (groups, gestures)
    }
    func walk(_ path: String, parent: String?, depth: Int, pending: [Node]) -> [String] {
      guard let node = byPath[path] else { return [] }
      if !isView(node, parent: parent) {
        return node.children.flatMap { walk($0, parent: parent, depth: depth, pending: pending + [node]) }
      }
      guard depth <= maxDepth else { result.truncated = true; return [] }
      let (modifiers, gestures) = modifierProperties(pending)
      var properties = node.properties
      if !gestures.isEmpty {
        properties.append(.init(id: "swiftuiGestures", title: "Gestures", properties: [
          .init(id: "eventHandlers", title: "手势", value: .array(gestures), availability: "available", reason: nil)
        ]))
      }
      properties += modifiers
      let index = result.nodes.count
      let name = displayName(node)
      let kind = node.name == "_ShapeView" ? "shape" : node.kind
      result.nodes.append(.init(path: node.path, parentPath: parent, children: [], type: node.type,
        name: name, kind: kind, hostFrame: node.hostFrame, properties: properties))
      let children = node.children.flatMap { walk($0, parent: node.path, depth: depth + 1, pending: []) }
      result.nodes[index] = .init(path: node.path, parentPath: parent, children: children, type: node.type,
        name: name, kind: kind, hostFrame: node.hostFrame, properties: properties)
      return [node.path]
    }
    for root in raw where root.parentPath == nil {
      _ = walk(root.path, parent: nil, depth: 0, pending: [])
    }
    return result
  }
}
#endif
