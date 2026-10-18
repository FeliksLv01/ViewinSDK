import XCTest
@testable import ViewinSDK

@MainActor final class SwiftUIDebugDecoderTests: XCTestCase {
  private func node(position: [Double], transform: [String: Any]? = nil, children: [[String: Any]] = []) -> [String: Any] {
    var properties: [[String: Any]] = [
      ["id": 0, "attribute": ["type": "SwiftUI.Text"]],
      ["id": 3, "attribute": ["value": position]],
      ["id": 4, "attribute": ["value": [4, 5]]],
    ]
    if let transform { properties.append(["id": 2, "attribute": ["value": transform]]) }
    return ["properties": properties, "children": children]
  }

  func testPositionsAreNotMistakenForParentRelativeCoordinates() throws {
    let root = node(position: [10, 20], transform: ["items": [["translation": [1, 2]]]],
                    children: [node(position: [30, 40])])
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]))
    XCTAssertEqual(result.nodes[1].hostFrame?.origin, CGPoint(x: 31, y: 42))
  }

  func testUnknownTransformDoesNotProduceInventedGeometry() throws {
    let root = node(position: [10, 20], transform: ["items": [["unknownTransform": [2, 3]]]],
                    children: [node(position: [30, 40])])
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]))
    XCTAssertEqual(result.nodes.count, 2)
    XCTAssertTrue(result.nodes.allSatisfy { $0.hostFrame == nil })
  }

  func testDeepDebugTreeStopsWithinBudgetAndKeepsReferencesConsistent() throws {
    var root = node(position: [0, 0])
    for _ in 0..<200 { root = node(position: [0, 0], children: [root]) }
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]))
    XCTAssertTrue(result.truncated)
    XCTAssertLessThanOrEqual(result.nodes.count, 113)
    let ids = Set(result.nodes.map(\.path))
    XCTAssertTrue(result.nodes.allSatisfy { $0.children.allSatisfy(ids.contains) })
  }
  func testRuntimeWrappersDoNotBecomeRowsOrConsumeViewDepth() throws {
    var root = node(position: [10, 20])
    for _ in 0..<180 {
      root = ["properties": [["id": 0, "attribute": ["type": "SwiftUI.ModifiedContent<SwiftUI.Text, SwiftUI.EmptyModifier>"]]],
              "children": [root]]
    }
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]), maxDepth: 3)
    XCTAssertFalse(result.truncated)
    XCTAssertEqual(result.nodes.map(\.name), ["Text"])
    XCTAssertNil(result.nodes[0].parentPath)
    XCTAssertEqual(result.nodes[0].hostFrame?.origin, CGPoint(x: 10, y: 20))
  }

  func testModifierPropertiesAndGesturesSurviveProjection() throws {
    let text = node(position: [10, 20])
    let gesture: [String: Any] = ["properties": [["id": 0, "attribute":
      ["type": "SwiftUI.AddGestureModifier<SwiftUI.TapGesture, SwiftUI.DefaultGestureCombiner>"]]], "children": [text]]
    let padding: [String: Any] = ["properties": [
      ["id": 0, "attribute": ["type": "SwiftUI._PaddingLayout"]],
      ["id": 1, "attribute": ["subattributes": [["name": "length", "value": 16]]]],
    ], "children": [gesture]]
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [padding]))
    XCTAssertEqual(result.nodes.map(\.name), ["Text"])
    XCTAssertTrue(result.nodes[0].properties.contains { $0.title == "Padding" })
    let events = result.nodes[0].properties.flatMap(\.properties).first { $0.id == "eventHandlers" }
    XCTAssertNotNil(events)
  }

  func testCustomViewsWithModifierInTheirNameAreRetained() throws {
    let root: [String: Any] = ["properties": [["id": 0, "attribute": ["type": "MyApp.CustomModifierView"]]],
                               "children": [node(position: [10, 20])]]
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]))
    XCTAssertEqual(result.nodes.map(\.name), ["MyApp.CustomModifierView", "Text"])
    XCTAssertEqual(result.nodes[1].parentPath, result.nodes[0].path)
    XCTAssertEqual(result.nodes[0].children, [result.nodes[1].path])
  }

  func testStructuralFlagsAreNotMovedIntoInspectorCards() throws {
    let root: [String: Any] = ["properties": [
      ["id": 0, "attribute": ["type": "SwiftUI.StaticIf"]],
      ["id": 1, "attribute": ["name": "flag", "value": true]],
    ], "children": [node(position: [10, 20])]]
    let result = try SwiftUIDebugDecoder.decode(JSONSerialization.data(withJSONObject: [root]))
    XCTAssertEqual(result.nodes.map(\.name), ["Text"])
    XCTAssertFalse(result.nodes[0].properties.contains { $0.id.hasPrefix("modifier:") })
  }

}
