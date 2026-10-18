@file:OptIn(androidx.compose.ui.tooling.data.UiToolingDataApi::class, androidx.compose.runtime.tooling.ComposeToolingApi::class)
package app.viewin.compose

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import android.view.View
import androidx.compose.runtime.tooling.CompositionData
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.LayoutInfo
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.node.RootForTest
import androidx.compose.ui.platform.InspectableValue
import androidx.compose.ui.platform.isDebugInspectorInfoEnabled
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.tooling.data.ContextCache
import androidx.compose.ui.tooling.data.mapTree
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import app.viewin.protocol.*
import app.viewin.sdk.*
import kotlinx.serialization.json.*
import java.util.Collections
import java.util.IdentityHashMap
import kotlin.math.*

/** Snapshot-only reader. Never executes semantic actions, changes state, or installs input modifiers. */
class ComposeAdapter : ComposeInspectionAdapter {
    override fun prepare(debuggable: Boolean) {
        // Must happen before the first composition. Existing compositions are not hot-reloaded.
        if (debuggable) isDebugInspectorInfoEnabled = true
    }
    override fun isHost(view: View) = view is RootForTest
    private class Record(val layout: LayoutInfo, var label: String = "Layout") {
        val calls = mutableListOf<String>()
        var parameters: List<NodeProperty> = emptyList()
    }
    private class Budget : RuntimeException()
    private fun field(id: String, title: String, value: JsonElement) = NodeProperty(id, title, value, "available")
    private fun scalar(value: Any?, depth: Int = 0): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value.take(2000))
        is Boolean -> JsonPrimitive(value)
        is Unit -> JsonPrimitive(true)
        is Role -> JsonPrimitive(value.toString())
        is TextStyle -> buildJsonObject {
            put("color", scalar(value.color)); put("fontSize", scalar(value.fontSize)); put("fontWeight", value.fontWeight?.weight?.let { JsonPrimitive(it) } ?: JsonNull)
            put("letterSpacing", scalar(value.letterSpacing)); put("lineHeight", scalar(value.lineHeight))
        }
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is Float -> if (value.isFinite()) JsonPrimitive(value) else JsonNull
        is Double -> if (value.isFinite()) JsonPrimitive(value) else JsonNull
        is AnnotatedString -> JsonPrimitive(value.text.take(2000))
        is Color -> if (value == Color.Unspecified) JsonNull else buildJsonObject {
            put("red", value.red); put("green", value.green); put("blue", value.blue); put("alpha", value.alpha)
        }
        is Dp -> scalar(value.value)
        is TextUnit -> scalar(value.value)
        is Enum<*> -> JsonPrimitive(value.name)
        is AccessibilityAction<*> -> buildJsonObject { put("label", value.label); put("hasAction", value.action != null) }
        is Collection<*> -> if (depth < 2) JsonArray(value.take(20).map { scalar(it, depth + 1) }) else JsonPrimitive("Collection (${value.size})")
        else -> JsonPrimitive(value.javaClass.name) // Never evaluate callbacks or arbitrary toString implementations.
    }
    override fun capture(view: View, windowId: String, hostId: String, origin: IntArray,
                         maxNodes: Int, maxDepth: Int, deadline: Long, store: (Bitmap) -> String?): ComposeCapture {
        val root = view as? RootForTest ?: return ComposeCapture(emptyList(), emptyList(), "none", true)
        if (maxNodes <= 0 || maxDepth < 0 || SystemClock.elapsedRealtime() > deadline)
            return ComposeCapture(emptyList(), emptyList(), "none", true, "Compose capture budget reached")
        var partial = false
        var backend = "composition"
        val issues = mutableListOf<String>()
        val records = IdentityHashMap<LayoutInfo, Record>()
        val order = mutableListOf<Record>()
        val density = view.resources.displayMetrics.density.toDouble()
        fun checkBudget() { if (SystemClock.elapsedRealtime() > deadline || records.size >= maxNodes) throw Budget() }
        fun record(layout: LayoutInfo): Record = records[layout] ?: run {
            checkBudget(); Record(layout).also { records[layout] = it; order += it }
        }
        val semantics = root.semanticsOwner.getAllSemanticsNodes(mergingEnabled = false)
            .associateBy { it.id }
        try {
            @Suppress("UNCHECKED_CAST")
            val tables = view.getTag(androidx.compose.ui.R.id.inspection_slot_table_set) as? Set<CompositionData> ?: emptySet()
            val cache = ContextCache()
            for (table in tables) {
                table.mapTree<List<Record>>({ group, context, children ->
                    checkBudget()
                    val layout = group.node as? LayoutInfo
                    val result = if (layout != null) listOf(record(layout)) else children.flatten()
                    val name = context.name
                    val frameworkItem = name == "Item" && (
                        context.location?.sourceFile?.startsWith("Lazy") == true || context.parameters.any {
                            val type = it.value?.javaClass?.name.orEmpty()
                            type.startsWith("androidx.compose.foundation.lazy.") && type.contains("ItemProvider")
                        })
                    if (layout == null && result.size == 1 && name != null && name !in ignoredCalls && !frameworkItem && !name.startsWith("remember")) {
                        val node = result.single()
                        node.label = name
                        if (node.calls.size < 32) node.calls.add(0, name)
                        // Lazy tooling API: decode parameters only for displayed component calls.
                        node.parameters = context.parameters.take(20).map { field(it.name, it.name, scalar(it.value)) }
                    }
                    result
                }, cache)
            }
        } catch (_: Budget) { partial = true; issues += "Compose traversal budget reached" }
          catch (e: Exception) { partial = true; issues += "Composition tooling unavailable"; Log.w("Viewin", "Compose composition inspection failed; falling back to semantics", e) }
        if (order.isEmpty()) {
            backend = "semantics"
            partial = true
            issues += "Semantics only: compiler/tooling composition data unavailable; decorative layouts and modifiers may be absent"
            try { semantics.values.forEach { record(it.layoutInfo) } } catch (_: Budget) { issues += "Compose node budget reached" }
        }
        fun nodeId(layout: LayoutInfo) = "$hostId:compose:${System.identityHashCode(layout).toUInt().toString(16)}"
        val parents = IdentityHashMap<LayoutInfo, LayoutInfo?>()
        order.forEach { r ->
            var p = r.layout.parentInfo
            var depth = 0
            while (p != null && !records.containsKey(p) && depth++ < 128) p = p.parentInfo
            parents[r.layout] = p?.takeIf { records.containsKey(it) }
        }
        // Filter retained/unplaced lazy nodes; connect their descendants to the closest exported parent.
        val visible = order.filter { it.layout.isAttached && it.layout.isPlaced && !it.layout.isDeactivated }.take(maxNodes)
        val included = Collections.newSetFromMap(IdentityHashMap<LayoutInfo, Boolean>()).apply { addAll(visible.map { it.layout }) }
        visible.forEach { r ->
            var p = parents[r.layout]; var depth = 0
            while (p != null && (!included.contains(p)) && depth++ < 128) p = parents[p]
            parents[r.layout] = p
        }
        val accepted = visible.filter { r ->
            var p = parents[r.layout]; var depth = 0
            while (p != null && depth <= maxDepth) { depth++; p = parents[p] }
            (depth <= maxDepth).also { if (!it) partial = true }
        }
        val children = accepted.groupBy { parents[it.layout] }.mapValues { (parent, values) ->
            // Lazy subcompositions come from an unordered slot-table set. Order attached items
            // visually; this is not a claim about RenderNode draw order.
            if (parent != null && records[parent]?.calls?.any { it.contains("Lazy") } == true)
                values.sortedWith(compareBy({ it.layout.coordinates.positionInRoot().y }, { it.layout.coordinates.positionInRoot().x }))
            else values
        }
        // A single host bitmap for collapsed-subtree crops. Expanded containers never reuse it.
        var bitmap: Bitmap? = null
        if (accepted.isNotEmpty() && view.width > 0 && view.height > 0) {
            val scale = min(1f, 1400f / max(view.width, view.height))
            try {
                bitmap = Bitmap.createBitmap(max(1, ceil(view.width * scale).toInt()), max(1, ceil(view.height * scale).toInt()), Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bitmap!!); canvas.scale(scale, scale); view.draw(canvas)
            } catch (_: RuntimeException) { bitmap?.recycle(); bitmap = null }
        }
        val hostLocation = IntArray(2); view.getLocationInWindow(hostLocation)
        val exportOrder = mutableListOf<Record>()
        fun visit(record: Record) {
            exportOrder += record
            children[record.layout].orEmpty().forEach(::visit)
        }
        children[null].orEmpty().forEach(::visit)
        val exported = mutableSetOf<String>()
        val nodes = try { exportOrder.mapNotNull { r ->
            if (SystemClock.elapsedRealtime() > deadline || (parents[r.layout] != null && nodeId(parents[r.layout]!!) !in exported)) {
                partial = true
                return@mapNotNull null
            }
            val layout = r.layout
            val infos = layout.getModifierInfo()
            val coordinates = infos.firstOrNull()?.coordinates?.takeIf { it.isAttached } ?: layout.coordinates
            val size = coordinates.size
            val offsets = listOf(Offset.Zero, Offset(size.width.toFloat(), 0f), Offset(size.width.toFloat(), size.height.toFloat()), Offset(0f, size.height.toFloat()))
                .map { coordinates.localToWindow(it) }
            val corners = offsets.map { LayoutPoint(it.x / density, it.y / density) }
            val frame = LayoutRect(corners.minOf { it.x }, corners.minOf { it.y }, corners.maxOf { it.x } - corners.minOf { it.x }, corners.maxOf { it.y } - corners.minOf { it.y })
            val sem = semantics[layout.semanticsId]
            val entries = sem?.config?.map { it.key.name to it.value } ?: emptyList()
            val semanticFields = entries.map { (key, value) -> field(key, key, scalar(value)) }
            val actions = entries.filter { it.second is AccessibilityAction<*> && it.first in inputActions }.map { (key, action) -> buildJsonObject {
                put("type", "Compose.$key"); put("eventName", key); put("origin", "composeSemantics")
                put("enabled", entries.none { it.first == "Disabled" }); put("handlerDescription", (action as AccessibilityAction<*>).label ?: "Semantic action registered")
            } }
            val modifiers = infos.take(64).map { info ->
                val inspectable = info.modifier as? InspectableValue
                buildJsonObject {
                    put("type", info.modifier.javaClass.name)
                    put("name", inspectable?.nameFallback ?: info.modifier.javaClass.simpleName)
                    inspectable?.let { value -> put("value", scalar(value.valueOverride)); put("properties", buildJsonObject {
                        value.inspectableElements.take(20).forEach { put(it.name, scalar(it.value)) }
                    }) }
                }
            }
            var name = r.label
            if (backend == "semantics") name = when {
                entries.any { it.first == "EditableText" } -> "TextField"
                entries.any { it.first == "Text" } -> "Text"
                entries.any { it.first == "OnClick" } -> "Clickable"
                else -> "Semantics"
            }
            val kind = when {
                name.contains("Text") -> "text"; name.contains("Button") || name == "Clickable" || entries.any { it.first == "Role" && it.second == Role.Button } -> "button"
                name.contains("Image") || name.contains("Icon") -> "image"
                name.contains("Lazy") || entries.any { it.first.endsWith("ScrollAxisRange") } -> "scroll"
                name in listOf("Column", "Row", "Box") -> "stack"; else -> "component"
            }
            val groups = mutableListOf(PropertyGroup("compose", "Compose", listOf(
                field("backend", "Backend", JsonPrimitive(backend)), field("callChain", "Call Chain", JsonArray(r.calls.map { JsonPrimitive(it) })),
                field("isPlaced", "Placed", JsonPrimitive(layout.isPlaced)), field("layoutDirection", "Layout Direction", JsonPrimitive(layout.layoutDirection.name)))))
            if (r.parameters.isNotEmpty()) groups += PropertyGroup("parameters", "Parameters", r.parameters)
            if (semanticFields.isNotEmpty()) groups += PropertyGroup("semantics", "Semantics", semanticFields)
            if (modifiers.isNotEmpty()) groups += PropertyGroup("modifiers", "Modifiers", listOf(field("modifiers", "Modifiers", JsonArray(modifiers))))
            if (actions.isNotEmpty()) groups += PropertyGroup("events", "Events", listOf(field("eventHandlers", "Events", JsonArray(actions))))
            val ids = mutableMapOf("hostingViewId" to hostId, "runtimeIdentity" to System.identityHashCode(layout).toUInt().toString(16), "semanticsId" to layout.semanticsId.toString())
            (entries.firstOrNull { it.first == "TestTag" }?.second as? String)?.let { ids["testTag"] = it }
            val kids = children[layout].orEmpty().map { nodeId(it.layout) }
            var crop: String? = null
            // Crops cannot represent isolated rotated/scaled drawing. Keep those nodes as outlines.
            if (bitmap != null && offsets[0].y == offsets[1].y && offsets[1].x == offsets[2].x && offsets[0].x == offsets[3].x) {
                val left = offsets.minOf { it.x } - hostLocation[0]; val top = offsets.minOf { it.y } - hostLocation[1]
                val right = offsets.maxOf { it.x } - hostLocation[0]; val bottom = offsets.maxOf { it.y } - hostLocation[1]
                if (left >= 0 && top >= 0 && right <= view.width && bottom <= view.height && right > left && bottom > top) {
                    val b = bitmap!!; val sx = b.width.toFloat()/view.width; val sy = b.height.toFloat()/view.height
                    val x = floor(left*sx).toInt().coerceIn(0,b.width-1); val y = floor(top*sy).toInt().coerceIn(0,b.height-1)
                    val w = (ceil(right*sx).toInt()-x).coerceIn(1,b.width-x); val h = (ceil(bottom*sy).toInt()-y).coerceIn(1,b.height-y)
                    val copy = Bitmap.createBitmap(b,x,y,w,h).let { if (it === b) b.copy(Bitmap.Config.ARGB_8888,false) else it }
                    crop = store(copy)
                }
            }
            groups += PropertyGroup("rendering", "Rendering", listOf(field("imageRepresentation", "Image Source", JsonPrimitive("Composed host crop for collapsed subtree; expanded container is outline only"))))
            exported += nodeId(layout)
            SnapshotNode(nodeId(layout), windowId, parents[layout]?.let(::nodeId) ?: hostId, kids, "compose", kind, name, name, ids,
                NodeGeometry(LayoutRect(0.0,0.0,size.width/density,size.height/density),frame,corners), NodeVisibility(false,view.alpha.toDouble()),groups,
                imageId = null, groupImageId = crop)
        } } finally { bitmap?.recycle() }
        val validNodes = nodes.map { it.copy(childIds = it.childIds.filter(exported::contains)) }
        if (partial && issues.isEmpty()) issues += "Compose export budget reached"
        return ComposeCapture(validNodes, validNodes.filter { it.parentId == hostId }.map { it.id }, backend, partial, issues.distinct().joinToString("; ").ifEmpty { null })
    }
    private companion object {
        val inputActions = setOf("OnClick", "OnLongClick", "ScrollBy", "ScrollByOffset", "ScrollToIndex", "SetProgress", "SetText", "SetSelection", "InsertTextAtCursor", "Expand", "Collapse", "Dismiss", "PageUp", "PageDown", "PageLeft", "PageRight")
        val ignoredCalls = setOf("Layout", "ReusableComposeNode", "ComposeNode", "CompositionLocalProvider", "ProvideCommonCompositionLocals", "ProvideAndroidCompositionLocals", "ProvideContent", "Content", "content", "ReusableContent", "ReusableContentHost", "SkippableItem", "LazyLayoutPinnableItem", "SaveableStateProvider", "SaveableStateHolder", "LazyLayout")
    }
}
