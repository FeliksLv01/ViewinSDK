import XCTest
import SwiftUI
import UIKit
import ViewinProtocol
@testable import ViewinSDK

@MainActor final class SwiftUIRuntimeTests: XCTestCase {
  func testBuildTypeIsDeclaredByHostInsteadOfGuessedFromSDK() {
    XCTAssertEqual(UIKitCollector().target.buildType, "unknown")
    XCTAssertEqual(UIKitCollector(buildType: .debug).target.buildType, "debug")
    XCTAssertEqual(UIKitCollector(buildType: .internalRelease).target.buildType, "internalRelease")
  }

  func testRendererCacheBindsDisplayListToActualLayers() async throws {
    SwiftUIRuntime.prepare()
    let host = UIHostingController(rootView: VStack {
      Text("Display list probe").font(.system(size: 24)).foregroundStyle(.red)
      Image(systemName: "star.fill").foregroundStyle(.blue)
    }.padding(20).background(.green).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(radius: 4))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    await Task.yield()
    CATransaction.flush()
    let rendered = SwiftUIRenderCapture.read(host: host.view)
    XCTAssertNil(rendered.reason)
    XCTAssertFalse(rendered.truncated)
    XCTAssertTrue(rendered.items.contains { $0.kind == "text" && $0.layer != nil })
    XCTAssertTrue(rendered.items.contains { $0.kind == "image" && $0.layer != nil })
    XCTAssertTrue(rendered.items.filter { $0.layer != nil }.allSatisfy { $0.identity > 0 && $0.identity < UInt32.max })
    let capture = SwiftUICaptureAdapter.capture(host: host.view, window: window,
      hostId: "host", screenshot: nil, storeImage: { _ in "test-image" })
    XCTAssertGreaterThan(capture.renderBindings, 0)
    XCTAssertGreaterThan(capture.renderImages, 0)
    #if DEBUG
    XCTAssertGreaterThan(capture.renderRelations, 0)
    for link in capture.relations where link.kind == "renderedByGeometry" {
      let logical = try XCTUnwrap(capture.nodes.first { $0.id == link.fromNodeId })
      let rendering = try XCTUnwrap(capture.nodes.first { $0.id == link.toNodeId })
      if logical.childIds.isEmpty, let image = rendering.imageId {
        XCTAssertEqual(logical.imageId, image)
        XCTAssertEqual(logical.groupImageId, image)
      }
    }
    #endif
    let ids = Set(capture.nodes.map(\.id)).union(["host"])
    XCTAssertTrue(capture.nodes.allSatisfy { $0.childIds.allSatisfy(ids.contains) && ids.contains($0.parentId ?? "") })
    XCTAssertTrue(capture.relations.allSatisfy { ids.contains($0.fromNodeId) && ids.contains($0.toNodeId) })
  }

  func testGeometryAssociationRejectsOverlapsAndUsesDeepestAncestor() {
    func node(_ id: String, parent: String? = nil, children: [String] = [], rendering: Bool = false,
              shiftedCorner: Bool = false) -> SnapshotNode {
      .init(id: id, windowId: "window", parentId: parent, childIds: children,
        framework: rendering ? "swiftuiRendering" : "swiftui", kind: rendering ? "renderItem" : "text",
        typeName: "Text", name: "Text", identifiers: rendering ? ["objectAddress": "0x1"] : [:],
        geometry: .init(localBounds: .init(x: 0, y: 0, width: 80, height: 20),
          frameInWindow: .init(x: 0, y: 0, width: 80, height: 20),
          cornersInWindow: [.init(x: shiftedCorner ? 4 : 0, y: 0), .init(x: 80, y: 0),
                            .init(x: 80, y: 20), .init(x: 0, y: 20)], clipInWindow: nil),
        visibility: .init(hidden: false, alpha: 1),
        properties: rendering ? [.init(id: "rendering", title: "Rendering", properties: [
          .init(id: "renderKind", title: "Content", value: .string("text"), availability: "available", reason: nil)
        ])] : [], sourceLocation: nil, imageId: rendering ? "actual" : "crop", groupImageId: "crop")
    }
    let layer = node("layer", rendering: true)
    let parent = node("parent", children: ["child"])
    let child = node("child", parent: "parent")
    let links = SwiftUIRenderAssociation.resolve(logical: [parent, child], rendering: [layer])
    XCTAssertEqual(links.map(\.fromNodeId), ["child"])
    let updated = SwiftUIRenderAssociation.applyingImages(to: [parent, child], rendering: [layer], relations: links)
    XCTAssertEqual(updated[1].imageId, "actual")
    XCTAssertEqual(updated[1].groupImageId, "actual")
    XCTAssertNil(updated[0].imageId, "A parent's composed crop must never become its own texture")
    XCTAssertEqual(updated[0].groupImageId, "crop")
    let unmatched = SwiftUIRenderAssociation.applyingImages(to: [child], rendering: [], relations: [])
    XCTAssertNil(unmatched[0].imageId)
    XCTAssertEqual(unmatched[0].groupImageId, "crop", "Retain the collapsed fallback")
    XCTAssertTrue(SwiftUIRenderAssociation.resolve(logical: [child, node("sibling")], rendering: [layer]).isEmpty)
    XCTAssertTrue(SwiftUIRenderAssociation.resolve(logical: [child], rendering: [layer, node("otherLayer", rendering: true)]).isEmpty)
    XCTAssertTrue(SwiftUIRenderAssociation.resolve(logical: [child], rendering: [node("rotated", rendering: true, shiftedCorner: true)]).isEmpty)
  }

  #if DEBUG
  func testDebugHostingGraphExposesTypesAndLayout() throws {
    SwiftUIRuntime.prepare()
    let host = UIHostingController(rootView: VStack {
      Text("Viewin SwiftUI probe")
      Image(systemName: "star")
    }.padding(16))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    let inspection = try XCTUnwrap(host.view as? any SwiftUIHostingInspection)
    let data = inspection.viewinDebugData()
    XCTAssertFalse(data.isEmpty, "SwiftUI graph recording was not enabled before host creation")
    let encoded = try XCTUnwrap(_ViewDebug.serializedData(data))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
    XCTAssertFalse(object.isEmpty)
    let description = String(decoding: encoded, as: UTF8.self)
    XCTAssertTrue(description.contains("Text"))
    XCTAssertTrue(description.contains("CGSize"))
    let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
    attachment.name = "swiftui-debug-probe.json"
    attachment.lifetime = .keepAlways
    add(attachment)
    window.isHidden = true
  }

  func testLogicalGeometryAndHostAssociationUseRealLayout() throws {
    SwiftUIRuntime.prepare()
    let host = UIHostingController(rootView:
      Rectangle().fill(.green).frame(width: 80, height: 30).position(x: 70, y: 90))
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    let capture = SwiftUICaptureAdapter.capture(host: host.view, window: window,
      hostId: "host", screenshot: nil, storeImage: { _ in nil })
    XCTAssertNil(capture.reason)
    XCTAssertFalse(capture.nodes.isEmpty)
    let frames: [LayoutRect] = capture.nodes.compactMap { $0.geometry?.frameInWindow }
    let matches: [LayoutRect] = frames.filter { frame in
      abs(frame.width - 80.0) < 0.1 && abs(frame.height - 30.0) < 0.1
    }
    XCTAssertTrue(matches.contains { abs($0.x - 30) < 0.1 && abs($0.y - 75) < 0.1 }, "Measured frames: \(matches)")
    let ids = Set(capture.nodes.map(\.id)).union(["host"])
    XCTAssertTrue(capture.nodes.allSatisfy { $0.childIds.allSatisfy(ids.contains) && ids.contains($0.parentId ?? "") })
    XCTAssertTrue(capture.relations.allSatisfy { $0.kind == "renderedByGeometry" || ($0.kind == "hostedBy" && $0.toNodeId == "host") })
  }

  func testNestedUIKitHostingOriginIsAppliedExactlyOnce() throws {
    SwiftUIRuntime.prepare()
    let container = UIViewController()
    let host = UIHostingController(rootView:
      Rectangle().fill(.green).frame(width: 80, height: 30).position(x: 70, y: 40))
    if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = container
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    container.addChild(host)
    container.view.addSubview(host.view)
    host.view.frame = CGRect(x: 24, y: 100, width: 200, height: 100)
    host.didMove(toParent: container)
    host.view.layoutIfNeeded()
    let capture = SwiftUICaptureAdapter.capture(host: host.view, window: window,
      hostId: "host", screenshot: nil, storeImage: { _ in nil })
    let frames: [LayoutRect] = capture.nodes.compactMap { $0.geometry?.frameInWindow }
    XCTAssertTrue(frames.contains { frame in
      abs(frame.x - 54) < 0.1 && abs(frame.y - 125) < 0.1 && abs(frame.width - 80) < 0.1
    }, "Measured frames: \(frames)")
  }

  func testActualGestureModifiersAreCapturedWithoutAddingInspectionModifiers() throws {
    SwiftUIRuntime.prepare()
    let host = UIHostingController(rootView: Text("Gesture probe").padding()
      .onTapGesture {}.simultaneousGesture(DragGesture().onEnded { _ in }))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    let capture = SwiftUIRuntime.capture(host.view)
    XCTAssertNil(capture.reason)
    let gestureProperties = capture.nodes.flatMap(\.properties).flatMap(\.properties)
      .filter { $0.id == "eventHandlers" }
    XCTAssertFalse(gestureProperties.isEmpty, "Gesture types: \(capture.nodes.filter { $0.type.contains("Gesture") }.map(\.type))")
  }
  #else
  func testReleaseRuntimeProbe() throws {
    setenv("SWIFTUI_VIEW_DEBUG", "31", 1)
    let host = UIHostingController(rootView: Text("Release SwiftUI probe").padding())
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    let inspection = try XCTUnwrap(host.view as? any ReleaseHostingProbe)
    let raw = inspection.releaseProbe()
    let encoded = _ViewDebug.serializedData(raw)
    let report = "release graph roots=\(raw.count), serialized bytes=\(encoded?.count ?? 0)"
    let attachment = XCTAttachment(string: report + "\n" + (encoded.map { String(decoding: $0, as: UTF8.self) } ?? "nil"))
    attachment.name = "release-swiftui-runtime-probe"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertNotNil(encoded, report)
    let capture = SwiftUIRuntime.capture(host.view)
    XCTAssertEqual(capture.nodes.isEmpty, raw.isEmpty)
    if raw.isEmpty { XCTAssertNotNil(capture.reason) }
  }

  func testMissingHostingEntryFallsBackSafely() {
    XCTAssertTrue(SwiftUIRuntime.canAttemptInspection)
    XCTAssertTrue(SwiftUIRuntime.capture(UIView()).nodes.isEmpty)
  }
  #endif
}

#if !DEBUG
@MainActor private protocol ReleaseHostingProbe {
  func releaseProbe() -> [_ViewDebug.Data]
}
extension _UIHostingView: ReleaseHostingProbe {
  fileprivate func releaseProbe() -> [_ViewDebug.Data] { _viewDebugData() }
}
#endif
