package app.viewin.sdk

import android.app.Application
import android.content.pm.ApplicationInfo
import android.graphics.*
import android.os.SystemClock
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.widget.*
import app.viewin.protocol.*
import app.viewin.protocol.Target
import kotlinx.serialization.json.*
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import kotlin.math.*

internal class ViewCollector(private val app: Application, private val state: Viewin.Session,
                             private val buildType: Viewin.BuildType) {
    private val sessionId = UUID.randomUUID().toString()
    private fun id(view: View) = "view-${System.identityHashCode(view).toUInt().toString(16)}"
    fun target(): Target {
        val info = app.packageManager.getPackageInfo(app.packageName, 0)
        // Unlike SwiftUI's SDK compilation flags, Android exposes host debuggability.
        val declared = if (buildType != Viewin.BuildType.UNKNOWN) buildType.wireValue
            else if (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) "debug" else "unknown"
        return Target("android", Build.MODEL + ":" + Build.DEVICE, Build.MODEL, app.packageName,
            app.applicationInfo.loadLabel(app.packageManager).toString(), info.versionName ?: "", "Android ${Build.VERSION.RELEASE}",
            declared, listOf(FrameworkVersion("Android View", Build.VERSION.SDK_INT.toString())))
    }
    private fun png(bitmap: Bitmap): ByteArray = ByteArrayOutputStream().use {
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray()
    }
    private fun bitmap(view: View, longest: Int, soloBackground: Boolean = false): Bitmap? {
        if (!view.isShown || view.alpha <= 0 || view.width <= 0 || view.height <= 0) return null
        val scale = min(1f, longest.toFloat() / max(view.width, view.height))
        if (!view.getGlobalVisibleRect(Rect())) return null
        val bitmap = Bitmap.createBitmap(max(1, ceil(view.width * scale).toInt()), max(1, ceil(view.height * scale).toInt()), Bitmap.Config.ARGB_8888)
        bitmap.density = view.resources.displayMetrics.densityDpi
        try {
            val canvas = Canvas(bitmap); canvas.scale(scale, scale)
            if (soloBackground) {
                // Never hide children or mutate Drawable bounds. Expanded containers show background only.
                view.background?.draw(canvas)
            } else view.draw(canvas)
        } catch (_: RuntimeException) { bitmap.recycle(); return null }
        return bitmap
    }
    fun preview(): Map<String, ByteArray> {
        val window = state.windows().lastOrNull() ?: error("Bring the inspected App to the foreground")
        val preview = bitmap(window.decorView, 440) ?: return emptyMap()
        return try { mapOf("app-preview" to png(preview)) } finally { preview.recycle() }
    }
    data class Capture(val snapshot: Snapshot, val images: Map<String, ByteArray>)
    fun capture(): Capture {
        val started = Instant.now().toString()
        val deadline = SystemClock.elapsedRealtime() + 8_000
        val windows = state.windows()
        check(windows.isNotEmpty()) { "Bring the inspected App to the foreground" }
        val nodes = mutableListOf<SnapshotNode>()
        val resources = mutableListOf<ImageResource>()
        val images = linkedMapOf<String, ByteArray>()
        val windowModels = mutableListOf<SnapshotWindow>()
        var truncated = false
        val composeCaptures = mutableListOf<ComposeCapture>()
        val composeWarnings = mutableListOf<CaptureWarning>()
        var imageBytes = 0
        fun store(bitmap: Bitmap?): String? {
            if (bitmap == null) return null
            try {
                val data = png(bitmap)
                val key = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
                if (images[key] == null) {
                    if (images.size >= 512 || imageBytes + data.size > 128_000_000) { truncated = true; return null }
                    images[key] = data; imageBytes += data.size
                    resources += ImageResource(key, "images/$key.png", "image/png", bitmap.width, bitmap.height)
                }
                return key
            } finally { bitmap.recycle() }
        }
        for ((windowIndex, window) in windows.withIndex()) {
            val root = window.decorView
            val windowId = "window-${id(root)}"
            val density = root.resources.displayMetrics.density.toDouble()
            val origin = IntArray(2); root.getLocationOnScreen(origin)
            fun point(x: Float, y: Float) = LayoutPoint((x - origin[0]) / density, (y - origin[1]) / density)
            fun visit(view: View, parent: String?, depth: Int): String? {
                if (nodes.size >= 5000 || depth > 126 || SystemClock.elapsedRealtime() > deadline) { truncated = true; return null }
                val nodeId = id(view)
                val matrix = Matrix(); view.transformMatrixToGlobal(matrix)
                val points = floatArrayOf(0f, 0f, view.width.toFloat(), 0f, view.width.toFloat(), view.height.toFloat(), 0f, view.height.toFloat())
                matrix.mapPoints(points)
                val corners = (0..3).map { point(points[it * 2], points[it * 2 + 1]) }
                val x = corners.minOf { it.x }; val y = corners.minOf { it.y }
                val frame = LayoutRect(x, y, corners.maxOf { it.x } - x, corners.maxOf { it.y } - y)
                val clipping = Rect()
                val clip = if (view.getGlobalVisibleRect(clipping)) listOf(point(clipping.left.toFloat(), clipping.top.toFloat()),
                    point(clipping.right.toFloat(), clipping.top.toFloat()), point(clipping.right.toFloat(), clipping.bottom.toFloat()),
                    point(clipping.left.toFloat(), clipping.bottom.toFloat())) else null
                val identifiers = mutableMapOf("runtimeIdentity" to System.identityHashCode(view).toUInt().toString(16))
                if (view.id != View.NO_ID) runCatching { view.resources.getResourceName(view.id) }.getOrNull()?.let { identifiers["resourceId"] = it }
                val tag = view.tag
                if (tag is String) identifiers["tag"] = tag.take(500)
                val group = store(bitmap(view, 1400))
                val hasChildren = view is ViewGroup && view.childCount > 0
                var solo = if (!hasChildren) group else if (view.background != null) store(bitmap(view, 1400, true)) else null
                val position = nodes.size
                // Reserve before recursion so the node/depth budgets cannot produce dangling children.
                val properties = ViewProperties.groups(view, density).toMutableList()
                properties += PropertyGroup("rendering", "Rendering", listOf(
                    ViewProperties.field("imageRepresentation", "Image Source", JsonPrimitive(if (hasChildren) "View.draw 子树；展开时容器仅显示 Background" else "View.draw 叶子视图")),
                    NodeProperty("xmlSource", "XML Source", JsonNull, "unavailable", "运行时未提供 XML 文件/行号；resourceId 可用于源码搜索。")
                ))
                if (view.id == android.R.id.content) properties += PropertyGroup("hierarchy", "Hierarchy", listOf(
                    ViewProperties.field("hierarchyHints", "Hierarchy", buildJsonObject { put("controllerRoot", true) })
                ))
                val kind = if (RecyclerViewProperties.isRecyclerView(view)) "scroll" else when (view) { is Button -> "button"; is TextView -> "text"; is ImageView -> "image"; is ScrollView, is HorizontalScrollView, is AbsListView -> "scroll"; is LinearLayout -> "stack"; else -> if (view === root) "window" else "view" }
                val node = SnapshotNode(nodeId, windowId, parent, emptyList(), "androidView", kind, view.javaClass.name,
                    view.javaClass.simpleName, identifiers, NodeGeometry(LayoutRect(0.0, 0.0, view.width / density, view.height / density), frame, corners, clip),
                    NodeVisibility(view.visibility != View.VISIBLE, view.alpha.toDouble()), properties, imageId = solo, groupImageId = group)
                nodes += node
                val compose = ComposeInspection.adapter?.takeIf { it.isHost(view) }?.let { adapter ->
                    try {
                        adapter.capture(view, windowId, nodeId, origin, 5000 - nodes.size, 126 - depth - 1, deadline) { store(it) }
                    } catch (e: Exception) {
                        android.util.Log.w("Viewin", "Compose capture failed", e)
                        ComposeCapture(emptyList(), emptyList(), "none", true, "Compose capture failed: ${e.javaClass.simpleName}")
                    }
                }
                if (compose != null) {
                    composeCaptures += compose
                    nodes += compose.nodes
                    compose.reason?.let { composeWarnings += CaptureWarning("compose-partial", it, nodeId) }
                    if (compose.nodes.isNotEmpty()) solo = null
                }
                val children = if (view is ViewGroup) (0 until view.childCount).mapNotNull { visit(view.getChildAt(it), nodeId, depth + 1) } else emptyList()
                nodes[position] = node.copy(childIds = children + (compose?.roots ?: emptyList()), imageId = solo)
                return nodeId
            }
            val rootId = visit(root, null, 0) ?: continue
            windowModels += SnapshotWindow(windowId, window.attributes.title?.toString()?.ifEmpty { "Window ${windowIndex + 1}" } ?: "Window ${windowIndex + 1}",
                LayoutSize(root.width / density, root.height / density), "dp", density, listOf(rootId), nodes.first { it.id == rootId }.groupImageId)
        }
        val snapshot = Snapshot(ProtocolVersion(0, 1), UUID.randomUUID().toString(), sessionId, Instant.now().toString(), "runtime", target(),
            listOf(Capability("androidView.hierarchy", "supported"), Capability("androidView.properties", "supported"),
                Capability("view.images", "partial", "Software View.draw; SurfaceView, TextureView and hardware effects may be absent. Expanded containers show background only."),
                Capability("androidView.recyclerView", if (nodes.any { n -> n.properties.any { it.id == "recyclerView" } }) "supported" else "unsupported",
                    "公开 API 读取 Adapter、LayoutManager 和已挂载 item 的 ViewHolder；不创建离屏 item。不可读取的字段单独标记 unavailable。"),
                Capability("androidView.xmlSource", "unsupported", "Resource IDs available; source file/line requires build instrumentation."),
                Capability("androidView.events", "partial", "Public listener presence and clickability; no callback execution or private listener fields."),
                Capability("compose.logicalTree", if (composeCaptures.any { it.backend == "composition" && it.nodes.isNotEmpty() }) "partial" else "unsupported",
                    "Optional composition tooling, layout and modifiers. Host crops only; independent render textures are unavailable."),
                Capability("compose.semantics", if (composeCaptures.any { it.nodes.isNotEmpty() }) "supported" else "unsupported", "Unmerged semantics; actions are read only and never invoked.")),
            CaptureStatus(started, Instant.now().toString(), if (truncated || composeCaptures.any { it.partial }) "partial" else "complete", "bestEffort",
                listOf(CaptureWarning("software-rendering", "View.draw may omit hardware surfaces and effects.")) + composeWarnings +
                    if (truncated) listOf(CaptureWarning("capture-budget", "Node, image or depth budget reached.")) else emptyList()),
            windowModels, nodes, composeCaptures.flatMap { c -> c.roots.map { rootId -> NodeRelation(rootId, c.nodes.first { it.id == rootId }.parentId!!, "hostedBy") } }, resources)
        return Capture(snapshot, images)
    }
}
