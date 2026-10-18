#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime
import ViewinProtocol

/// Read-only capture. No recognizer hooks, action execution, or state changes.
@MainActor enum UIKitEventHandlers {
  static func values(for view: UIView, references: [ObjectIdentifier: [JSONValue]]) -> [JSONValue] {
    var result: [JSONValue] = []
    if let control = view as? UIControl {
      var actions: [UInt: [JSONValue]] = [:]
      control.enumerateEventHandlers { actionHandler, targetAction, events, _ in
        let pair: JSONValue
        if let actionHandler {
          pair = .object(["target": .string(describe(actionHandler)),
                          "action": .string("UIAction(\(actionHandler.identifier.rawValue))"),
                          "kind": .string("closure")])
        } else {
          pair = .object(["target": targetAction?.0.map { .string(describe($0 as AnyObject)) } ?? .null,
                          "action": targetAction.map { .string(NSStringFromSelector($0.1)) } ?? .null])
        }
        for bit in 0..<32 {
          let mask = UInt(1) << bit
          if events.rawValue & mask != 0 { actions[mask, default: []].append(pair) }
        }
      }
      for mask in actions.keys.sorted() {
        result.append(.object([
          "handlerType": .string("control"), "typeName": .string("UIControl"),
          "eventName": .string(eventName(mask)), "event": .integer(Int64(mask)),
          "targetActions": .array(actions[mask] ?? []),
          "targetActionsAvailability": .string("available"),
        ]))
      }
    }
    for gesture in view.gestureRecognizers ?? [] {
      let targets = gestureActions(gesture)
      var fields: [String: JSONValue] = [
        "handlerType": .string("gesture"), "typeName": .string(NSStringFromClass(type(of: gesture))),
        "enabled": .bool(gesture.isEnabled), "origin": .string("gestureRecognizer"),
        "delegate": gesture.delegate.map { .string(describe($0)) } ?? .null,
        "targetActions": .array(targets ?? []),
        "targetActionsAvailability": .string(targets == nil ? "unavailable" : "available"),
        "memberReferences": .array(references[ObjectIdentifier(gesture)] ?? []),
      ]
      if targets == nil { fields["targetActionsReason"] = .string("当前系统未提供可读取的手势 target/action 存储结构") }
      let bases: [AnyClass] = [UILongPressGestureRecognizer.self, UIScreenEdgePanGestureRecognizer.self,
        UIPanGestureRecognizer.self, UISwipeGestureRecognizer.self, UIRotationGestureRecognizer.self,
        UIPinchGestureRecognizer.self, UITapGestureRecognizer.self]
      if !bases.contains(where: { gesture.isMember(of: $0) }) {
        fields["inheritedRecognizerName"] = .string(
          bases.first(where: { gesture.isKind(of: $0) }).map(NSStringFromClass) ?? "UIGestureRecognizer")
      }
      result.append(.object(fields))
    }
    return result
  }

  private static func describe(_ object: AnyObject) -> String {
    let address = UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    return "\(NSStringFromClass(type(of: object))) (0x\(String(address, radix: 16)))"
  }

  /// UIGestureRecognizer has no public target enumeration. Inspect only known,
  /// type-checked Objective-C ivars; unsupported layouts remain unavailable.
  private static func gestureActions(_ gesture: UIGestureRecognizer) -> [JSONValue]? {
    guard let targetsIvar = class_getInstanceVariable(type(of: gesture), "_targets"),
          let targetsEncoding = ivar_getTypeEncoding(targetsIvar), targetsEncoding.pointee == 64 else { return nil }
    guard let stored = object_getIvar(gesture, targetsIvar) else { return [] }
    guard let boxes = stored as? [NSObject] else { return nil }
    var pairs: [JSONValue] = []
    for box in boxes {
      guard let actionIvar = class_getInstanceVariable(type(of: box), "_action"),
            let encoding = ivar_getTypeEncoding(actionIvar), encoding.pointee == 58 else { return nil }
      let offset = ivar_getOffset(actionIvar)
      guard offset >= 0, offset + MemoryLayout<UnsafeRawPointer?>.size <= class_getInstanceSize(type(of: box))
      else { return nil }
      let storage = UnsafeRawPointer(Unmanaged.passUnretained(box).toOpaque()).advanced(by: offset)
      let pointer = storage.load(as: UnsafeRawPointer?.self)
      let action = pointer.map { NSStringFromSelector(unsafeBitCast($0, to: Selector.self)) }
      // A missing target field is different from an existing field containing nil.
      guard let targetIvar = class_getInstanceVariable(type(of: box), "_target"),
            let targetEncoding = ivar_getTypeEncoding(targetIvar), targetEncoding.pointee == 64 else { return nil }
      let target = object_getIvar(box, targetIvar) as AnyObject?
      pairs.append(.object(["target": target.map { .string(describe($0)) } ?? .null,
                            "action": action.map(JSONValue.string) ?? .null]))
    }
    return pairs
  }

  static func eventName(_ mask: UInt) -> String {
    let names: [UInt: String] = [
      1: "TouchDown", 2: "TouchDownRepeat", 4: "TouchDragInside", 8: "TouchDragOutside",
      16: "TouchDragEnter", 32: "TouchDragExit", 64: "TouchUpInside", 128: "TouchUpOutside",
      256: "TouchCancel", 4096: "ValueChanged", 8192: "PrimaryActionTriggered", 16384: "MenuActionTriggered",
      65536: "EditingDidBegin", 131072: "EditingChanged", 262144: "EditingDidEnd", 524288: "EditingDidEndOnExit",
    ]
    return names[mask].map { "UIControlEvent\($0)" } ?? "UIControlEvent(0x\(String(mask, radix: 16)))"
  }
}
#endif
