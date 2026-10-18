#if canImport(UIKit)
  import UIKit
  import Network
  import ViewinProtocol
  import ViewinTransport

  /// Explicit opt-in SDK, usable in Debug and internal Release builds. No automatic injection.
  public enum ViewinBuildType: String, Sendable {
    case debug
    case internalRelease
    case unknown
  }

  @MainActor public enum Viewin {
    private static var server: InspectionServer?
    public static func start(port: UInt16 = 48721, buildType: ViewinBuildType = .unknown) throws {
      guard server == nil else { return }
      SwiftUIRuntime.prepare()
      let instance = try InspectionServer(port: port, buildType: buildType)
      server = instance
      instance.start()
    }
    public static func stop() {
      server?.stop()
      server = nil
    }
  }

  @MainActor private final class InspectionServer {
    private let listener: NWListener
    private let collector: UIKitCollector
    private var isCapturing = false
    private var clients: [UUID: (FramedConnection, Task<Void, Never>)] = [:]
    init(port: UInt16, buildType: ViewinBuildType) throws {
      collector = UIKitCollector(buildType: buildType)
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(
        host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
      listener = try NWListener(using: parameters)
    }
    func start() {
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in self?.accept(connection) }
      }
      listener.start(queue: .main)
    }
    func stop() {
      listener.cancel()
      for (connection, task) in clients.values {
        task.cancel()
        connection.close()
      }
      clients.removeAll()
    }
    private func accept(_ incoming: NWConnection) {
      guard clients.count < 4 else {
        incoming.cancel()
        return
      }
      let id = UUID()
      let connection = FramedConnection(accepting: incoming)
      let task = Task { [weak self] in
        guard let self else { return }
        defer {
          connection.close()
          clients[id] = nil
        }
        let timeout = Task {
          try? await Task.sleep(nanoseconds: 30_000_000_000)
          if !Task.isCancelled { connection.close() }
        }
        defer { timeout.cancel() }
        do {
          try await connection.start()
          let request = try JSONDecoder().decode(
            InspectionRequest.self, from: await connection.receive())
          guard request.service == InspectionWire.service, request.version == InspectionWire.version
          else {
            throw TransportError("不兼容的 Viewin 协议。")
          }
          if request.method == "hello" {
            let previews = collector.previewImages()
            try await connection.send(
              JSONEncoder().encode(
                InspectionResponse(
                  id: request.id, target: collector.target, imageIds: previews.map { $0.0 })))
            for (_, bytes) in previews { try await connection.send(bytes) }
          } else if request.method == "capture" {
            guard UIApplication.shared.applicationState == .active else {
              try await connection.send(
                JSONEncoder().encode(InspectionResponse(id: request.id, error: "请将目标 App 切到前台。")))
              return
            }
            guard !isCapturing else {
              try await connection.send(
                JSONEncoder().encode(InspectionResponse(id: request.id, error: "已有采集任务正在进行。")))
              return
            }
            isCapturing = true
            defer { isCapturing = false }
            let capture = collector.capture()
            let ids = capture.snapshot.images.map(\.id)
            try await connection.send(
              JSONEncoder().encode(
                InspectionResponse(id: request.id, snapshot: capture.snapshot, imageIds: ids)))
            for imageID in ids {
              if let bytes = capture.images[imageID] { try await connection.send(bytes) }
            }
          } else {
            try await connection.send(
              JSONEncoder().encode(InspectionResponse(id: request.id, error: "未知采集命令。")))
          }
        } catch { /* A disconnected or invalid session is closed without retry. */  }
      }
      clients[id] = (connection, task)
    }
  }
#endif
