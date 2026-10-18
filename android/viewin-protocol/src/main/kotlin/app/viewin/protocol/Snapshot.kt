package app.viewin.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// Framework-free wire DTOs. JSON fields follow protocol/schema/snapshot.schema.json.

@Serializable
data class Snapshot(
    val protocolVersion: ProtocolVersion,
    val snapshotId: String,
    val sessionId: String,
    val capturedAt: String,
    val source: String,
    val target: Target,
    val capabilities: List<Capability>,
    val capture: CaptureStatus,
    val windows: List<SnapshotWindow>,
    val nodes: List<SnapshotNode>,
    val relations: List<NodeRelation>,
    val images: List<ImageResource>
)

@Serializable
data class ProtocolVersion(
    val major: Int,
    val minor: Int
)

@Serializable
data class Target(
    val platform: String,
    val deviceId: String,
    val deviceName: String,
    val appId: String,
    val appName: String,
    val appVersion: String,
    val osVersion: String,
    val buildType: String,
    val frameworks: List<FrameworkVersion>
)

@Serializable
data class FrameworkVersion(
    val name: String,
    val version: String? = null
)

@Serializable
data class Capability(
    val name: String,
    val status: String,
    val reason: String? = null
)

@Serializable
data class CaptureStatus(
    val startedAt: String,
    val completedAt: String,
    val completeness: String,
    val consistency: String,
    val warnings: List<CaptureWarning>
)

@Serializable
data class CaptureWarning(
    val code: String,
    val message: String,
    val nodeId: String? = null
)

@Serializable
data class SnapshotWindow(
    val id: String,
    val title: String,
    val size: LayoutSize,
    val unit: String,
    val pixelsPerUnit: Double,
    val rootNodeIds: List<String>,
    val screenshotId: String? = null
)

@Serializable
data class SnapshotNode(
    val id: String,
    val windowId: String,
    val parentId: String? = null,
    val childIds: List<String>,
    val framework: String,
    val kind: String,
    val typeName: String,
    val name: String,
    val identifiers: Map<String, String>,
    val geometry: NodeGeometry? = null,
    val visibility: NodeVisibility,
    val properties: List<PropertyGroup>,
    val sourceLocation: SourceLocation? = null,
    val imageId: String? = null,
    val groupImageId: String? = null
)

@Serializable
data class NodeGeometry(
    val localBounds: LayoutRect,
    val frameInWindow: LayoutRect,
    val cornersInWindow: List<LayoutPoint>,
    val clipInWindow: List<LayoutPoint>? = null
)

@Serializable
data class NodeVisibility(
    val hidden: Boolean,
    val alpha: Double
)

@Serializable
data class LayoutPoint(
    val x: Double,
    val y: Double
)

@Serializable
data class LayoutSize(
    val width: Double,
    val height: Double
)

@Serializable
data class LayoutRect(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double
)

@Serializable
data class PropertyGroup(
    val id: String,
    val title: String,
    val properties: List<NodeProperty>
)

@Serializable
data class NodeProperty(
    val id: String,
    val title: String,
    val value: JsonElement,
    val availability: String,
    val reason: String? = null,
    val presentation: PropertyPresentation? = null
)

@Serializable
data class PropertyPresentation(
    val kind: String,
    val sectionId: String? = null,
    val sectionTitle: String? = null,
    val enumType: String? = null
)

@Serializable
data class SourceLocation(
    val file: String,
    val line: Int? = null,
    val column: Int? = null
)

@Serializable
data class NodeRelation(
    val fromNodeId: String,
    val toNodeId: String,
    val kind: String
)

@Serializable
data class ImageResource(
    val id: String,
    val path: String,
    val mimeType: String,
    val pixelWidth: Int,
    val pixelHeight: Int
)
