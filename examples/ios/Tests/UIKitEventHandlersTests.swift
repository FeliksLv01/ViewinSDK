import XCTest
import UIKit
import ViewinProtocol
@testable import ViewinSDK

@MainActor final class UIKitEventHandlersTests: XCTestCase {
  private final class Target: NSObject, UIGestureRecognizerDelegate {
    var calls = 0
    @objc func first(_ sender: Any) { calls += 1 }
    @objc func second(_ sender: Any) { calls += 1 }
  }
  private final class CustomTap: UITapGestureRecognizer {}

  func testGestureCapturesDelegateReferencesAndMultipleActionsWithoutMutating() throws {
    let target = Target()
    let gesture = CustomTap(target: target, action: #selector(Target.first(_:)))
    gesture.addTarget(target, action: #selector(Target.second(_:)))
    gesture.delegate = target
    gesture.isEnabled = false
    let view = UIView()
    view.addGestureRecognizer(gesture)
    let references: [JSONValue] = [.object(["name": .string("_tap"), "ownerType": .string("Owner")])]
    let fields = try XCTUnwrap(objects(UIKitEventHandlers.values(for: view,
      references: [ObjectIdentifier(gesture): references])).first)
    XCTAssertEqual(fields["enabled"], .bool(false))
    XCTAssertEqual(fields["inheritedRecognizerName"], .string("UITapGestureRecognizer"))
    XCTAssertEqual(fields["memberReferences"], .array(references))
    XCTAssertTrue(fields["delegate"]?.displayText.contains("Target") == true)
    XCTAssertEqual(fields["targetActionsAvailability"], .string("available"))
    guard case .array(let actions) = fields["targetActions"] else { return XCTFail("No actions") }
    XCTAssertEqual(objects(actions).compactMap { $0["action"]?.displayText }, ["first:", "second:"])
    XCTAssertTrue(objects(actions).allSatisfy { $0["target"]?.displayText.contains("Target") == true })
    XCTAssertFalse(gesture.isEnabled)
    XCTAssertEqual(target.calls, 0)
  }

  private final class Owner: UIViewController {
    let tap = UITapGestureRecognizer()
    override func viewDidLoad() { super.viewDidLoad(); view.addGestureRecognizer(tap) }
  }

  func testCaptureFindsRecognizerStoredOnController() {
    let owner = Owner()
    owner.loadViewIfNeeded()
    let references = UIKitProperties.memberReferences(in: [owner.view])
    let values = references[ObjectIdentifier(owner.tap)] ?? []
    XCTAssertTrue(objects(values).contains { $0["name"] == .string("tap") })
  }

  func testControlGroupsAllActionsAndNamesPreviouslyMissingEvents() throws {
    let target = Target()
    let control = UIControl()
    control.addTarget(target, action: #selector(Target.first(_:)), for: [.touchUpOutside, .editingDidBegin])
    control.addTarget(target, action: #selector(Target.second(_:)), for: .touchUpOutside)
    let events = objects(UIKitEventHandlers.values(for: control, references: [:]))
    let touch = try XCTUnwrap(events.first { $0["eventName"] == .string("UIControlEventTouchUpOutside") })
    guard case .array(let actions) = touch["targetActions"] else { return XCTFail("No actions") }
    XCTAssertEqual(actions.count, 2)
    XCTAssertTrue(objects(actions).allSatisfy { $0["target"]?.displayText.contains("AnyHashable") == false })
    XCTAssertTrue(events.contains { $0["eventName"] == .string("UIControlEventEditingDidBegin") })
    XCTAssertEqual(target.calls, 0)
  }

  func testClosureActionsAreIdentifiedWithoutExecutingThem() throws {
    let target = Target()
    let control = UIControl()
    control.addAction(UIAction(identifier: .init("test.action")) { _ in target.calls += 1 }, for: .valueChanged)
    let event = try XCTUnwrap(objects(UIKitEventHandlers.values(for: control, references: [:])).first)
    guard case .array(let actions) = event["targetActions"] else { return XCTFail("No actions") }
    XCTAssertEqual(objects(actions).first?["action"], .string("UIAction(test.action)"))
    XCTAssertEqual(target.calls, 0)
  }

  private func objects(_ values: [JSONValue]) -> [[String: JSONValue]] {
    values.compactMap { if case .object(let value) = $0 { return value }; return nil }
  }
}
