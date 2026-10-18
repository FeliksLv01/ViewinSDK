#if canImport(UIKit)
  import UIKit
  import ObjectiveC.runtime
  import ViewinProtocol

  @MainActor enum UIKitProperties {
    static func memberReferences(in views: [UIView]) -> [ObjectIdentifier: [JSONValue]] {
      var result: [ObjectIdentifier: [JSONValue]] = [:]
      let known = Set(views.map(ObjectIdentifier.init)
        + views.flatMap { $0.gestureRecognizers ?? [] }.map(ObjectIdentifier.init))
      var owners: [NSObject] = views
      var seen = Set<ObjectIdentifier>()
      for view in views {
        var responder: UIResponder? = view.next
        while let value = responder {
          if value is UIViewController, seen.insert(ObjectIdentifier(value)).inserted {
            owners.append(value)
          }
          responder = value.next
        }
      }
      for owner in owners {
        var cls: AnyClass? = type(of: owner)
        while let current = cls, current != NSObject.self {
          var count: UInt32 = 0
          if let ivars = class_copyIvarList(current, &count) {
            defer { free(ivars) }
            for index in 0..<Int(count) {
              let ivar = ivars[index]
              guard let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64,
                let value = object_getIvar(owner, ivar) as? NSObject,
                known.contains(ObjectIdentifier(value)), let name = ivar_getName(ivar)
              else { continue }
              result[ObjectIdentifier(value), default: []].append(
                .object([
                  "name": .string(String(cString: name)),
                  "ownerType": .string(NSStringFromClass(current)), "kind": .string("ivar"),
                ]))
            }
          }
          cls = class_getSuperclass(current)
        }
        // Swift stored properties can have an empty Objective-C type encoding.
        // Read their reflected values rather than treating unknown ivar bytes as objects.
        var mirror: Mirror? = Mirror(reflecting: owner)
        while let current = mirror {
          let ownerType = (current.subjectType as? AnyClass).map(NSStringFromClass)
            ?? String(reflecting: current.subjectType)
          for child in current.children {
            guard let name = child.label else { continue }
            var value = child.value
            let optional = Mirror(reflecting: value)
            if optional.displayStyle == .optional {
              guard let wrapped = optional.children.first else { continue }
              value = wrapped.value
            }
            guard let object = value as? NSObject, known.contains(ObjectIdentifier(object)) else { continue }
            let key = ObjectIdentifier(object)
            let exists = result[key, default: []].contains { reference in
              guard case .object(let fields) = reference else { return false }
              return fields["name"] == .string(name) && fields["ownerType"] == .string(ownerType)
            }
            if !exists {
              result[key, default: []].append(.object([
                "name": .string(name), "ownerType": .string(ownerType), "kind": .string("swiftStoredProperty"),
              ]))
            }
          }
          mirror = current.superclassMirror
        }
      }
      return result
    }
    static func groups(
      for view: UIView, references: [JSONValue],
      eventReferences: [ObjectIdentifier: [JSONValue]]
    ) -> [PropertyGroup] {
      func integer(_ value: Int) -> JSONValue { .integer(Int64(value)) }
      func p(
        _ id: String, _ title: String, _ value: JSONValue, _ kind: String = "scalar",
        section: String? = nil, sectionTitle: String? = nil, enumType: String? = nil
      ) -> NodeProperty {
        .init(
          id: id, title: title, value: value, availability: "available", reason: nil,
          presentation: .init(
            kind: kind, sectionId: section, sectionTitle: sectionTitle, enumType: enumType))
      }
      func rect(_ r: CGRect) -> JSONValue {
        .object([
          "x": .number(r.minX), "y": .number(r.minY), "width": .number(r.width),
          "height": .number(r.height),
        ])
      }
      func color(_ value: UIColor?) -> JSONValue {
        guard let value else { return .null }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard
          value.resolvedColor(with: view.traitCollection).getRed(
            &red, green: &green, blue: &blue, alpha: &alpha)
        else { return .null }
        return .object([
          "red": .number(red), "green": .number(green), "blue": .number(blue),
          "alpha": .number(alpha),
        ])
      }
      var classes: [JSONValue] = []
      var cls: AnyClass? = type(of: view)
      while let current = cls {
        classes.append(.string(NSStringFromClass(current)))
        cls = class_getSuperclass(current)
      }
      var result = [
        PropertyGroup(
          id: "class", title: "Class",
          properties: [p("classChain", "类继承", .array([.array(classes)]), "classChain")])
      ]
      var relation = [p("memberReferences", "成员引用", .array(references))]
      if let controller = view.next as? UIViewController, controller.viewIfLoaded === view {
        relation.append(
          p("controller", "UIViewController", .string(NSStringFromClass(type(of: controller)))))
      }
      if let cell = view as? UITableViewCell {
        var parent = cell.superview
        while let ancestor = parent {
          if let table = ancestor as? UITableView, let position = table.indexPath(for: cell) {
            relation.append(
              p(
                "listPosition", "列表位置",
                .object(["section": integer(position.section), "item": integer(position.row)])))
            break
          }
          parent = ancestor.superview
        }
      }
      if let cell = view as? UICollectionViewCell {
        var parent = cell.superview
        while let ancestor = parent {
          if let collection = ancestor as? UICollectionView,
            let position = collection.indexPath(for: cell)
          {
            relation.append(
              p(
                "listPosition", "列表位置",
                .object(["section": integer(position.section), "item": integer(position.item)])))
            break
          }
          parent = ancestor.superview
        }
      }
      relation.append(p("eventHandlers", "事件与手势",
        .array(UIKitEventHandlers.values(for: view, references: eventReferences))))
      result.append(
        .init(
          id: "hierarchy", title: "Hierarchy",
          properties: [
            p(
              "hierarchyHints", "层级提示",
              .object(["controllerRoot": .bool(view.next is UIViewController)]))
          ]))
      result.append(.init(id: "relation", title: "Relation", properties: relation))
      let safe = view.safeAreaInsets
      result.append(
        .init(
          id: "layout", title: "Layout",
          properties: [
            p("frame", "Frame", rect(view.frame), "rect"),
            p("bounds", "Bounds", rect(view.bounds), "rect"),
            p("constraints", "Constraints", .array(UIKitConstraints.values(affecting: view))),
            p(
              "safeAreaInsets", "SafeArea",
              .object([
                "top": .number(safe.top), "left": .number(safe.left),
                "bottom": .number(safe.bottom), "right": .number(safe.right),
              ]), "insets"),
          ]))
      result.append(
        .init(
          id: "view", title: "CALayer / UIView",
          properties: [
            p("hidden", "Hidden", .bool(view.isHidden), "boolean"),
            p("alpha", "Opacity / Alpha", .number(view.alpha)),
            p(
              "userInteractionEnabled", "UserInteractionEnabled",
              .bool(view.isUserInteractionEnabled), "boolean"),
            p("clipsToBounds", "ClipsToBounds", .bool(view.clipsToBounds), "boolean"),
            p("backgroundColor", "BackgroundColor", color(view.backgroundColor), "color"),
            p(
              "borderColor", "BorderColor",
              color(view.layer.borderColor.map(UIColor.init(cgColor:))), "color", section: "border",
              sectionTitle: "Border"),
            p(
              "borderWidth", "BorderWidth", .number(view.layer.borderWidth), section: "border",
              sectionTitle: "Border"),
            p("cornerRadius", "CornerRadius", .number(view.layer.cornerRadius)),
            p(
              "shadowColor", "ShadowColor",
              color(view.layer.shadowColor.map(UIColor.init(cgColor:))),
              "color", section: "shadow", sectionTitle: "Shadow"),
            p(
              "shadowOpacity", "ShadowOpacity", .number(Double(view.layer.shadowOpacity)),
              section: "shadow",
              sectionTitle: "Shadow"),
            p(
              "shadowRadius", "ShadowRadius", .number(view.layer.shadowRadius), section: "shadow",
              sectionTitle: "Shadow"),
            p(
              "shadowOffsetX", "ShadowOffsetW", .number(view.layer.shadowOffset.width),
              section: "shadow",
              sectionTitle: "Shadow"),
            p(
              "shadowOffsetY", "ShadowOffsetH", .number(view.layer.shadowOffset.height),
              section: "shadow",
              sectionTitle: "Shadow"),
          ]))
      if let label = view as? UILabel {
        result.append(
          .init(
            id: "label", title: "UILabel",
            properties: [
              p("text", "Text", .string(label.text ?? "")),
              p(
                "fontName", "FontName", .string(label.font.fontName), section: "font",
                sectionTitle: "Font"),
              p(
                "fontSize", "FontSize", .number(label.font.pointSize), section: "font",
                sectionTitle: "Font"),
              p("numberOfLines", "NumberOfLines", integer(label.numberOfLines)),
              p("textColor", "TextColor", color(label.textColor), "color"),
              p(
                "lineBreakMode", "LineBreakMode", integer(label.lineBreakMode.rawValue), "enum",
                enumType: "NSLineBreakMode"),
              p(
                "textAlignment", "TextAlignment", integer(label.textAlignment.rawValue), "enum",
                enumType: "NSTextAlignment"),
            ]))
      }
      if let control = view as? UIControl {
        result.append(
          .init(
            id: "control", title: "UIControl",
            properties: [
              p("enabled", "Enabled", .bool(control.isEnabled), "boolean"),
              p("selected", "Selected", .bool(control.isSelected), "boolean"),
            ]))
      }
      return result
    }
  }
#endif
