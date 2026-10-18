package app.viewin.sdk

import android.view.View
import app.viewin.protocol.*
import kotlinx.serialization.json.*
import java.lang.reflect.Method

/** Optional public-API bridge. Holds classes/methods only, never ViewHolder or Activity instances. */
internal object RecyclerViewProperties {
    private const val PREFIX = "androidx.recyclerview.widget."
    // Use the SDK/application loader, not Android's framework loader.
    private fun appType(name: String): Class<*>? = runCatching {
        Class.forName(PREFIX + name, false, RecyclerViewProperties::class.java.classLoader)
    }.getOrNull()
    private val recycler = appType("RecyclerView")
    private val adapter = appType("RecyclerView\$Adapter")
    private val holder = appType("RecyclerView\$ViewHolder")
    private val linear = appType("LinearLayoutManager")
    private val grid = appType("GridLayoutManager")
    private val staggered = appType("StaggeredGridLayoutManager")
    private data class Signature(val owner: Class<*>, val name: String, val arguments: List<Class<*>>)
    private val methods = mutableMapOf<Signature, Method?>()
    private data class Read(val available: Boolean, val value: Any?)
    private fun read(owner: Class<*>?, receiver: Any?, name: String, vararg arguments: Any): Read {
        if (owner == null || receiver == null) return Read(false, null)
        val types = arguments.map { if (it is View) View::class.java else it.javaClass }
        val signature = Signature(owner, name, types)
        val method = methods.getOrPut(signature) { runCatching { owner.getMethod(name, *types.toTypedArray()) }.getOrNull() }
            ?: return Read(false, null)
        return try { Read(true, method.invoke(receiver, *arguments)) } catch (_: Exception) { Read(false, null) }
    }
    private fun value(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is String -> JsonPrimitive(value)
        else -> JsonPrimitive(value.javaClass.name)
    }
    private fun property(id: String, title: String, read: Read): NodeProperty =
        if (read.available) ViewProperties.field(id, title, value(read.value))
        else NodeProperty(id, title, JsonNull, "unavailable", "当前版本或状态下无法读取。")
    private fun position(id: String, title: String, read: Read): NodeProperty {
        val position = read.value as? Int
        return if (read.available && position != null && position >= 0) ViewProperties.field(id, title, JsonPrimitive(position))
        else NodeProperty(id, title, JsonNull, "unavailable", "当前没有有效位置；可能尚未绑定、已移除或正在更新。")
    }
    fun isRecyclerView(view: View): Boolean = recycler?.isInstance(view) == true

    fun groups(view: View): List<PropertyGroup> {
        val groups = mutableListOf<PropertyGroup>()
        if (isRecyclerView(view)) {
            val owner = read(recycler, view, "getAdapter")
            val manager = read(recycler, view, "getLayoutManager")
            val fields = mutableListOf(
                property("adapterType", "Adapter", owner),
                property("layoutManagerType", "LayoutManager", manager),
                property("itemCount", "Item Count", read(adapter, owner.value, "getItemCount")),
                property("hasStableIds", "Stable IDs", read(adapter, owner.value, "hasStableIds")),
                ViewProperties.field("attachedChildCount", "Attached Items", JsonPrimitive((view as android.view.ViewGroup).childCount)),
                property("isComputingLayout", "Computing Layout", read(recycler, view, "isComputingLayout")),
                property("hasPendingAdapterUpdates", "Pending Adapter Updates", read(recycler, view, "hasPendingAdapterUpdates")),
                property("isLayoutSuppressed", "Layout Suppressed", read(recycler, view, "isLayoutSuppressed"))
            )
            val scroll = read(recycler, view, "getScrollState")
            fields += property("scrollState", "Scroll State", if (scroll.available) Read(true, when (scroll.value) {
                0 -> "Idle (0)"; 1 -> "Dragging (1)"; 2 -> "Settling (2)"; else -> scroll.value
            }) else scroll)
            val layout = manager.value
            val layoutType = when {
                grid?.isInstance(layout) == true -> grid
                linear?.isInstance(layout) == true -> linear
                staggered?.isInstance(layout) == true -> staggered
                else -> null
            }
            if (layoutType != null) {
                val orientation = read(layoutType, layout, "getOrientation")
                fields += property("orientation", "Orientation", if (orientation.available) Read(true, when (orientation.value) {
                    0 -> "Horizontal (0)"; 1 -> "Vertical (1)"; else -> orientation.value
                }) else orientation)
                fields += property("reverseLayout", "Reverse Layout", read(layoutType, layout, "getReverseLayout"))
                if (linear?.isInstance(layout) == true) {
                    fields += property("stackFromEnd", "Stack From End", read(linear, layout, "getStackFromEnd"))
                    fields += position("firstVisiblePosition", "First Visible Position", read(linear, layout, "findFirstVisibleItemPosition"))
                    fields += position("lastVisiblePosition", "Last Visible Position", read(linear, layout, "findLastVisibleItemPosition"))
                }
                if (grid?.isInstance(layout) == true || staggered?.isInstance(layout) == true) {
                    fields += property("spanCount", "Span Count", read(layoutType, layout, "getSpanCount"))
                }
            }
            groups += PropertyGroup("recyclerView", "RecyclerView", fields)
        }
        // Only the actual item root owns list metadata; descendants do not get duplicate row indices.
        val parent = view.parent as? View ?: return groups
        if (!isRecyclerView(parent)) return groups
        val found = read(recycler, parent, "findContainingViewHolder", view)
        val itemHolder = found.value
        if (!found.available || itemHolder == null) {
            groups += PropertyGroup("viewHolder", "ViewHolder", listOf(property("holderType", "ViewHolder", Read(false, null))))
            return groups
        }
        val absolute = read(holder, itemHolder, "getAbsoluteAdapterPosition")
        val absolutePosition = absolute.value as? Int
        val fields = mutableListOf(
            ViewProperties.field("holderType", "ViewHolder", JsonPrimitive(itemHolder.javaClass.name)),
            property("bindingAdapterType", "Binding Adapter", read(holder, itemHolder, "getBindingAdapter")),
            position("absoluteAdapterPosition", "Absolute Position", absolute),
            position("bindingAdapterPosition", "Binding Position", read(holder, itemHolder, "getBindingAdapterPosition")),
            position("layoutPosition", "Layout Position", read(holder, itemHolder, "getLayoutPosition")),
            property("itemViewType", "Item View Type", read(holder, itemHolder, "getItemViewType")),
            property("isRecyclable", "Recyclable", read(holder, itemHolder, "isRecyclable"))
        )
        fields += if (absolute.available && absolutePosition != null && absolutePosition >= 0) {
            ViewProperties.field("listPosition", "Position", buildJsonObject { put("position", absolutePosition) })
        } else NodeProperty("listPosition", "Position", JsonNull, "unavailable", "当前没有有效的 Adapter 位置。")
        val rootAdapter = read(recycler, parent, "getAdapter")
        val stable = read(adapter, rootAdapter.value, "hasStableIds").value == true
        val itemId = read(holder, itemHolder, "getItemId")
        fields += if (stable && itemId.available && itemId.value is Long && itemId.value != -1L) {
            property("itemId", "Item ID", itemId)
        } else NodeProperty("itemId", "Item ID", JsonNull, "unavailable", if (stable) "ViewHolder 没有有效 Stable ID。" else "Adapter 未启用 Stable IDs。")
        groups += PropertyGroup("viewHolder", "ViewHolder", fields)
        return groups
    }
}
