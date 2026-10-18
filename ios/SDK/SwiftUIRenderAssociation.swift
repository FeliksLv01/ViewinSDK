#if canImport(UIKit)
import ViewinProtocol

/// Conservative fallback when the runtime omits a logical node's Display List IDs.
/// Co-located siblings are ambiguous; only an ancestor chain has a deepest owner.
enum SwiftUIRenderAssociation {
  static func resolve(logical: [SnapshotNode], rendering: [SnapshotNode]) -> [NodeRelation] {
    let byId = Dictionary(uniqueKeysWithValues: logical.map { ($0.id, $0) })
    func isAncestor(_ ancestor: String, of node: SnapshotNode) -> Bool {
      var parent = node.parentId
      for _ in 0..<128 {
        guard let id = parent else { return false }
        if id == ancestor { return true }
        parent = byId[id]?.parentId
      }
      return false
    }
    func sameFrame(_ a: NodeGeometry?, _ b: NodeGeometry?) -> Bool {
      guard let a, let b, a.cornersInWindow.count == 4, b.cornersInWindow.count == 4 else { return false }
      // Compare corners as well as the bounding box: rotated surfaces can share a box.
      return zip(a.cornersInWindow, b.cornersInWindow).allSatisfy {
        $0.x.isFinite && $0.y.isFinite && $1.x.isFinite && $1.y.isFinite
          && abs($0.x - $1.x) < 1 && abs($0.y - $1.y) < 1
      }
    }
    var proposals: [String: [SnapshotNode]] = [:]
    for layer in rendering where layer.identifiers["objectAddress"] != nil {
      guard let kind = layer.properties.flatMap(\.properties).first(where: { $0.id == "renderKind" }),
            case .string(let source) = kind.value, ["text", "image"].contains(source) else { continue }
      let candidates = logical.filter { $0.kind == source && sameFrame($0.geometry, layer.geometry) }
      let deepest = candidates.filter { candidate in
        !candidates.contains { $0.id != candidate.id && isAncestor(candidate.id, of: $0) }
      }
      guard deepest.count == 1, let owner = deepest.first else { continue }
      proposals[owner.id, default: []].append(layer)
    }
    return logical.compactMap { node in
      guard let matches = proposals[node.id], matches.count == 1, let layer = matches.first else { return nil }
      return .init(fromNodeId: node.id, toNodeId: layer.id, kind: "renderedByGeometry")
    }
  }

  /// Use actual leaf-layer pixels only when their geometry and unique owner match.
  /// Composed crops are only for collapsed subtrees, never an expanded node's own pixels.
  static func applyingImages(to logical: [SnapshotNode], rendering: [SnapshotNode],
                            relations: [NodeRelation]) -> [SnapshotNode] {
    let rendered = Dictionary(uniqueKeysWithValues: rendering.map { ($0.id, $0) })
    let links = Dictionary(grouping: relations, by: \.fromNodeId)
    return logical.map { node in
      let layer = links[node.id].flatMap { $0.count == 1 ? rendered[$0[0].toNodeId] : nil }
      let actual = node.childIds.isEmpty ? layer?.imageId : nil
      var properties = node.properties
      if actual != nil {
        properties.removeAll { $0.id == "rendering" }
        properties.append(.init(id: "rendering", title: "Rendering", properties: [
          .init(id: "imageRepresentation", title: "Image Source", value: .string("真实 CALayer；通过唯一类型及几何推断关联"), availability: "available", reason: nil),
          .init(id: "associationConfidence", title: "Association", value: .string("geometryInference"), availability: "available", reason: nil)
        ]))
      }
      return .init(id: node.id, windowId: node.windowId, parentId: node.parentId, childIds: node.childIds,
        framework: node.framework, kind: node.kind, typeName: node.typeName, name: node.name,
        identifiers: node.identifiers, geometry: node.geometry, visibility: node.visibility,
        properties: properties, sourceLocation: node.sourceLocation,
        imageId: actual, groupImageId: actual ?? node.groupImageId)
    }
  }
}
#endif
