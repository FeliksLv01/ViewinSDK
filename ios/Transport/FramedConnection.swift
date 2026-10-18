import Foundation
@preconcurrency import Network

public struct TransportError: Error, LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

@MainActor public final class FramedConnection {
  private let connection: NWConnection
  private var pendingConnect: CheckedContinuation<Void, Error>?
  public init(host: NWEndpoint.Host = "127.0.0.1", port: UInt16) {
    connection = NWConnection(host: host, port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
  }
  public init(accepting connection: NWConnection) { self.connection = connection }
  public func start(timeout: TimeInterval = 2) async throws {
    let timer = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.close()
    }
    defer { timer.cancel() }
    let connection = self.connection
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { continuation in
        pendingConnect = continuation
        connection.stateUpdateHandler = { [weak self] state in
          Task { @MainActor in
            guard let self else { return }
            switch state {
            case .ready: self.finishConnect(nil)
            case .failed(let error): self.finishConnect(error)
            case .cancelled: self.finishConnect(TransportError("连接已断开或超时。"))
            default: break
            }
          }
        }
        connection.start(queue: .main)
      }
    } onCancel: {
      connection.cancel()
    }
  }
  private func finishConnect(_ error: Error?) {
    guard let pending = pendingConnect else { return }
    pendingConnect = nil
    if let error { pending.resume(throwing: error) } else { pending.resume() }
  }
  public func close() {
    connection.cancel()
    finishConnect(TransportError("连接已关闭。"))
  }
  public func send(_ data: Data) async throws {
    guard data.count <= Int(UInt32.max) else { throw TransportError("消息超过协议帧长度。") }
    var length = UInt32(data.count).bigEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }
    frame.append(data)
    let connection = self.connection
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
          content: frame,
          completion: .contentProcessed { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          })
      }
    } onCancel: {
      connection.cancel()
    }
  }
  public func receive() async throws -> Data {
    let connection = self.connection
    return try await withTaskCancellationHandler {
      let header = try await read(4)
      let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      // Per-frame safety budget, independent of the removed 20 MB archive restriction.
      guard count > 0, count <= 256_000_000 else { throw TransportError("消息长度无效。") }
      return try await read(Int(count))
    } onCancel: {
      connection.cancel()
    }
  }
  private func read(_ count: Int) async throws -> Data {
    var data = Data()
    while data.count < count {
      try Task.checkCancellation()
      let remaining = min(count - data.count, 1_048_576)
      let bytes: Data = try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
          bytes, _, _, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let bytes, !bytes.isEmpty {
            continuation.resume(returning: bytes)
          } else {
            continuation.resume(throwing: TransportError("对端已断开连接。"))
          }
        }
      }
      data.append(bytes)
    }
    return data
  }
}
