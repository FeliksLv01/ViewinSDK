import Foundation

/// Viewin wire v1. Each frame is a UInt32 big-endian length followed by raw bytes.
/// JSON metadata is followed by one binary PNG frame per declared image (no base64 images).
public enum InspectionWire {
  public static let service = "app.viewin.inspection"
  public static let version = 1
  public static let simulatorPorts: ClosedRange<UInt16> = 48721...48726
}
public struct InspectionRequest: Codable, Sendable {
  public let service: String
  public let version: Int
  public let id: UUID
  public let method: String
  public init(method: String, id: UUID = UUID()) {
    service = InspectionWire.service
    version = InspectionWire.version
    self.method = method
    self.id = id
  }
}
public struct InspectionResponse: Codable, Sendable {
  public var service = InspectionWire.service
  public var version = InspectionWire.version
  public let id: UUID
  public var target: Target?
  public var snapshot: Snapshot?
  public var imageIds: [String]
  public var error: String?
  public init(
    id: UUID, target: Target? = nil, snapshot: Snapshot? = nil, imageIds: [String] = [],
    error: String? = nil
  ) {
    self.id = id
    self.target = target
    self.snapshot = snapshot
    self.imageIds = imageIds
    self.error = error
  }
}
