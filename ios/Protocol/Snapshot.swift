import Foundation

/// Shared wire types. No dependency on a UI toolkit, device connection, or collector.
public struct Snapshot: Codable, Sendable, Equatable {
  public let protocolVersion: ProtocolVersion
  public let snapshotId: String
  public let sessionId: String
  public let capturedAt: String
  public let source: String
  public let target: Target
  public let capabilities: [Capability]
  public let capture: CaptureStatus
  public let windows: [SnapshotWindow]
  public let nodes: [SnapshotNode]
  public let relations: [NodeRelation]
  public let images: [ImageResource]

  public init(
    protocolVersion: ProtocolVersion,
    snapshotId: String,
    sessionId: String,
    capturedAt: String,
    source: String,
    target: Target,
    capabilities: [Capability],
    capture: CaptureStatus,
    windows: [SnapshotWindow],
    nodes: [SnapshotNode],
    relations: [NodeRelation],
    images: [ImageResource]
  ) {
    self.protocolVersion = protocolVersion
    self.snapshotId = snapshotId
    self.sessionId = sessionId
    self.capturedAt = capturedAt
    self.source = source
    self.target = target
    self.capabilities = capabilities
    self.capture = capture
    self.windows = windows
    self.nodes = nodes
    self.relations = relations
    self.images = images
  }
}

public struct ProtocolVersion: Codable, Sendable, Equatable {
  public let major: Int
  public let minor: Int
  public static let current = ProtocolVersion(major: 0, minor: 1)

  public init(
    major: Int,
    minor: Int
  ) {
    self.major = major
    self.minor = minor
  }
}

public struct Target: Codable, Sendable, Equatable {
  public let platform: String
  public let deviceId: String
  public let deviceName: String
  public let appId: String
  public let appName: String
  public let appVersion: String
  public let osVersion: String
  public let buildType: String
  public let frameworks: [FrameworkVersion]

  public init(
    platform: String,
    deviceId: String,
    deviceName: String,
    appId: String,
    appName: String,
    appVersion: String,
    osVersion: String,
    buildType: String,
    frameworks: [FrameworkVersion]
  ) {
    self.platform = platform
    self.deviceId = deviceId
    self.deviceName = deviceName
    self.appId = appId
    self.appName = appName
    self.appVersion = appVersion
    self.osVersion = osVersion
    self.buildType = buildType
    self.frameworks = frameworks
  }
}

public struct FrameworkVersion: Codable, Sendable, Equatable {
  public let name: String
  public let version: String?

  public init(
    name: String,
    version: String?
  ) {
    self.name = name
    self.version = version
  }
}

public struct Capability: Codable, Sendable, Equatable {
  public let name: String
  public let status: String
  public let reason: String?

  public init(
    name: String,
    status: String,
    reason: String?
  ) {
    self.name = name
    self.status = status
    self.reason = reason
  }
}

public struct CaptureStatus: Codable, Sendable, Equatable {
  public let startedAt: String
  public let completedAt: String
  public let completeness: String
  public let consistency: String
  public let warnings: [CaptureWarning]

  public init(
    startedAt: String,
    completedAt: String,
    completeness: String,
    consistency: String,
    warnings: [CaptureWarning]
  ) {
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.completeness = completeness
    self.consistency = consistency
    self.warnings = warnings
  }
}

public struct CaptureWarning: Codable, Sendable, Equatable {
  public let code: String
  public let message: String
  public let nodeId: String?

  public init(
    code: String,
    message: String,
    nodeId: String?
  ) {
    self.code = code
    self.message = message
    self.nodeId = nodeId
  }
}

public struct SnapshotWindow: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let size: LayoutSize
  /// Logical units: points on iOS, dp on Android. Geometry is window-relative.
  public let unit: String
  public let pixelsPerUnit: Double
  public let rootNodeIds: [String]
  public let screenshotId: String?

  public init(
    id: String,
    title: String,
    size: LayoutSize,
    unit: String,
    pixelsPerUnit: Double,
    rootNodeIds: [String],
    screenshotId: String?
  ) {
    self.id = id
    self.title = title
    self.size = size
    self.unit = unit
    self.pixelsPerUnit = pixelsPerUnit
    self.rootNodeIds = rootNodeIds
    self.screenshotId = screenshotId
  }
}

public struct SnapshotNode: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let windowId: String
  public let parentId: String?
  public let childIds: [String]
  /// Open strings preserve new framework and node kinds in older readers.
  public let framework: String
  public let kind: String
  public let typeName: String
  public let name: String
  public let identifiers: [String: String]
  /// nil for logical components without independently measured geometry.
  public let geometry: NodeGeometry?
  public let visibility: NodeVisibility
  public let properties: [PropertyGroup]
  public let sourceLocation: SourceLocation?
  /// Solo rendering of this node, excluding children; references Snapshot.images.
  public let imageId: String?
  /// Rendering of the node including descendants, used while collapsed.
  public let groupImageId: String?

  public init(
    id: String,
    windowId: String,
    parentId: String?,
    childIds: [String],
    framework: String,
    kind: String,
    typeName: String,
    name: String,
    identifiers: [String: String],
    geometry: NodeGeometry?,
    visibility: NodeVisibility,
    properties: [PropertyGroup],
    sourceLocation: SourceLocation?,
    imageId: String? = nil,
    groupImageId: String? = nil
  ) {
    self.id = id
    self.windowId = windowId
    self.parentId = parentId
    self.childIds = childIds
    self.framework = framework
    self.kind = kind
    self.typeName = typeName
    self.name = name
    self.identifiers = identifiers
    self.geometry = geometry
    self.visibility = visibility
    self.properties = properties
    self.sourceLocation = sourceLocation
    self.imageId = imageId
    self.groupImageId = groupImageId
  }
}

public struct NodeGeometry: Codable, Sendable, Equatable {
  public let localBounds: LayoutRect
  public let frameInWindow: LayoutRect
  /// Transformed corners in clockwise order; not an axis-aligned approximation.
  public let cornersInWindow: [LayoutPoint]
  public let clipInWindow: [LayoutPoint]?

  public init(
    localBounds: LayoutRect,
    frameInWindow: LayoutRect,
    cornersInWindow: [LayoutPoint],
    clipInWindow: [LayoutPoint]?
  ) {
    self.localBounds = localBounds
    self.frameInWindow = frameInWindow
    self.cornersInWindow = cornersInWindow
    self.clipInWindow = clipInWindow
  }
}

public struct NodeVisibility: Codable, Sendable, Equatable {
  public let hidden: Bool
  public let alpha: Double

  public init(
    hidden: Bool,
    alpha: Double
  ) {
    self.hidden = hidden
    self.alpha = alpha
  }
}

public struct LayoutPoint: Codable, Sendable, Equatable {
  public let x: Double
  public let y: Double

  public init(
    x: Double,
    y: Double
  ) {
    self.x = x
    self.y = y
  }
}

public struct LayoutSize: Codable, Sendable, Equatable {
  public let width: Double
  public let height: Double

  public init(
    width: Double,
    height: Double
  ) {
    self.width = width
    self.height = height
  }
}

public struct LayoutRect: Codable, Sendable, Equatable {
  public let x: Double
  public let y: Double
  public let width: Double
  public let height: Double

  public init(
    x: Double,
    y: Double,
    width: Double,
    height: Double
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct PropertyGroup: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let properties: [NodeProperty]

  public init(
    id: String,
    title: String,
    properties: [NodeProperty]
  ) {
    self.id = id
    self.title = title
    self.properties = properties
  }
}

public struct NodeProperty: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let value: JSONValue
  public let availability: String
  public let reason: String?
  public let presentation: PropertyPresentation?

  public init(
    id: String,
    title: String,
    value: JSONValue,
    availability: String,
    reason: String?,
    presentation: PropertyPresentation? = nil
  ) {
    self.id = id
    self.title = title
    self.value = value
    self.availability = availability
    self.reason = reason
    self.presentation = presentation
  }
}

/// Read-only rendering hints. The value remains structured data for CLI/agents.
public struct PropertyPresentation: Codable, Sendable, Equatable {
  public let kind: String
  public let sectionId: String?
  public let sectionTitle: String?
  public let enumType: String?

  public init(
    kind: String, sectionId: String? = nil, sectionTitle: String? = nil, enumType: String? = nil
  ) {
    self.kind = kind
    self.sectionId = sectionId
    self.sectionTitle = sectionTitle
    self.enumType = enumType
  }
}

public struct SourceLocation: Codable, Sendable, Equatable {
  public let file: String
  public let line: Int?
  public let column: Int?

  public init(
    file: String,
    line: Int?,
    column: Int?
  ) {
    self.file = file
    self.line = line
    self.column = column
  }
}

/// Cross-tree relationships do not change hierarchy parentage.
public struct NodeRelation: Codable, Sendable, Equatable {
  public let fromNodeId: String
  public let toNodeId: String
  public let kind: String

  public init(
    fromNodeId: String,
    toNodeId: String,
    kind: String
  ) {
    self.fromNodeId = fromNodeId
    self.toNodeId = toNodeId
    self.kind = kind
  }
}

public struct ImageResource: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  /// Relative path within the snapshot bundle; never a local absolute path.
  public let path: String
  public let mimeType: String
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(
    id: String,
    path: String,
    mimeType: String,
    pixelWidth: Int,
    pixelHeight: Int
  ) {
    self.id = id
    self.path = path
    self.mimeType = mimeType
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}
