#if canImport(UIKit)
import UIKit
import SwiftUI
import ObjectiveC.runtime
import ViewinProtocol

@MainActor enum SwiftUIRuntime {
  struct Capture {
    let nodes: [SwiftUIDebugDecoder.Node]
    let reason: String?
    let truncated: Bool
    var canvasFrame: CGRect? = nil
  }

  static var canAttemptInspection: Bool {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27
  }

  static func prepare() {
    guard canAttemptInspection else { return }
    // SwiftUI reads this before building the first hosting graph.
    setenv("SWIFTUI_VIEW_DEBUG", "31", 0)
  }

  static func isHostingView(_ view: UIView) -> Bool {
    var current: AnyClass? = type(of: view)
    while let type = current {
      if NSStringFromClass(type).contains("_UIHostingView") { return true }
      current = class_getSuperclass(type)
    }
    return false
  }

  static func capture(_ view: UIView, maxDepth: Int = 112) -> Capture {
    guard canAttemptInspection else {
      return .init(nodes: [], reason: "SwiftUI runtime inspection currently supports iOS 27.", truncated: false)
    }
    guard let host = view as? any SwiftUIHostingInspection else {
      return .init(nodes: [], reason: "此宿主未提供可读取的 SwiftUI 调试入口。", truncated: false)
    }
    let raw = host.viewinDebugData()
    guard !raw.isEmpty, let data = _ViewDebug.serializedData(raw) else {
      return .init(nodes: [], reason: "No SwiftUI debug data returned. Release optimization or late startup may prevent recording; start Viewin before creating the first SwiftUI host.", truncated: false)
    }
    do {
      let decoded = try SwiftUIDebugDecoder.decode(data, maxDepth: maxDepth)
      return .init(nodes: decoded.nodes, reason: decoded.truncated ? "SwiftUI 树已达到本轮采集预算。" : nil,
                   truncated: decoded.truncated, canvasFrame: decoded.canvasFrame)
    } catch {
      return .init(nodes: [], reason: "SwiftUI 调试数据格式不受支持或超出本轮预算。", truncated: false)
    }
  }
}

@MainActor protocol SwiftUIHostingInspection {
  func viewinDebugData() -> [_ViewDebug.Data]
}

extension _UIHostingView: SwiftUIHostingInspection {
  func viewinDebugData() -> [_ViewDebug.Data] { _viewDebugData() }
}
#endif
