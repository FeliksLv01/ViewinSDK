#if canImport(UIKit)
  import UIKit
  import ViewinProtocol

  @MainActor enum UIKitConstraints {
    static func values(affecting view: UIView) -> [JSONValue] {
      var constraints = view.constraints
      var parent = view.superview
      while let owner = parent {
        constraints += owner.constraints.filter { constraint in
          (constraint.firstItem as? UIView) === view || (constraint.secondItem as? UIView) === view
        }
        parent = owner.superview
      }
      func reference(_ item: AnyObject?) -> JSONValue {
        guard let item else {
          return .object(["type": .string("objectReference"), "objectId": .string("0")])
        }
        let id = String(UInt(bitPattern: Unmanaged.passUnretained(item).toOpaque()), radix: 16)
        return .object([
          "type": .string("objectReference"), "objectId": .string(id),
          "address": .string("0x" + id), "className": .string(NSStringFromClass(type(of: item))),
        ])
      }
      return constraints.map { constraint in
        .object([
          "type": .string("constraint"),
          "identifier": constraint.identifier.map(JSONValue.string) ?? .null,
          "firstItem": reference(constraint.firstItem),
          "secondItem": reference(constraint.secondItem),
          "firstAttribute": .integer(Int64(constraint.firstAttribute.rawValue)),
          "secondAttribute": .integer(Int64(constraint.secondAttribute.rawValue)),
          "relation": .integer(Int64(constraint.relation.rawValue)),
          "multiplier": .number(constraint.multiplier), "constant": .number(constraint.constant),
          "priority": .number(Double(constraint.priority.rawValue)),
          "active": .bool(constraint.isActive),
          "effective": .bool(constraint.isActive),
        ])
      }
    }
  }
#endif
