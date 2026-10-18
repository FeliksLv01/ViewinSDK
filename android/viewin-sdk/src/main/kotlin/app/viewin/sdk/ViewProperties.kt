package app.viewin.sdk

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.*
import app.viewin.protocol.*
import kotlinx.serialization.json.*

internal object ViewProperties {
    fun field(id: String, title: String, value: JsonElement, kind: String = "scalar") =
        NodeProperty(id, title, value, "available", presentation = PropertyPresentation(kind))
    fun color(value: Int) = buildJsonObject {
        put("red", Color.red(value) / 255.0); put("green", Color.green(value) / 255.0)
        put("blue", Color.blue(value) / 255.0); put("alpha", Color.alpha(value) / 255.0)
    }
    fun groups(view: View, density: Double): List<PropertyGroup> {
        fun n(value: Number) = JsonPrimitive(value.toDouble() / density)
        fun p(id: String, title: String, value: Boolean) = field(id, title, JsonPrimitive(value))
        val base = mutableListOf(
            p("hidden", "Hidden", view.visibility != View.VISIBLE),
            field("visibility", "Visibility", JsonPrimitive(when(view.visibility) { View.GONE -> "GONE"; View.INVISIBLE -> "INVISIBLE"; else -> "VISIBLE" })),
            field("alpha", "Alpha", JsonPrimitive(view.alpha)), p("enabled", "Enabled", view.isEnabled),
            p("clickable", "Clickable", view.isClickable), p("longClickable", "Long Clickable", view.isLongClickable),
            p("focusable", "Focusable", view.isFocusable), p("selected", "Selected", view.isSelected),
            field("elevation", "Elevation", n(view.elevation)),
            field("translationZ", "Translation Z", n(view.translationZ)),
            field("rotation", "Rotation", JsonPrimitive(view.rotation)),
            field("scaleX", "Scale X", JsonPrimitive(view.scaleX)), field("scaleY", "Scale Y", JsonPrimitive(view.scaleY)),
            field("contentDescription", "Content Description", JsonPrimitive(view.contentDescription?.toString()?.take(2000) ?: "")),
            field("padding", "Padding", buildJsonObject {
                put("left", n(view.paddingLeft)); put("top", n(view.paddingTop)); put("right", n(view.paddingRight)); put("bottom", n(view.paddingBottom))
            }, "insets"),
            field("scroll", "Scroll", buildJsonObject { put("x", n(view.scrollX)); put("y", n(view.scrollY)) }, "point")
        )
        (view.background as? ColorDrawable)?.let { base += field("backgroundColor", "Background Color", color(it.color), "color") }
        if (view is ViewGroup) {
            base += p("clipChildren", "Clip Children", view.clipChildren)
            base += p("clipToPadding", "Clip To Padding", view.clipToPadding)
        }
        val groups = mutableListOf(PropertyGroup("view", "View", base))
        val lp = view.layoutParams
        if (lp != null) {
            val params = mutableListOf(field("width", "Width", JsonPrimitive(when(lp.width) { -1 -> "match_parent"; -2 -> "wrap_content"; else -> "${lp.width / density} dp" })),
                field("height", "Height", JsonPrimitive(when(lp.height) { -1 -> "match_parent"; -2 -> "wrap_content"; else -> "${lp.height / density} dp" })))
            if (lp is ViewGroup.MarginLayoutParams) params += field("margin", "Margin", buildJsonObject {
                put("left", n(lp.leftMargin)); put("top", n(lp.topMargin)); put("right", n(lp.rightMargin)); put("bottom", n(lp.bottomMargin))
            }, "insets")
            if (lp is LinearLayout.LayoutParams) params += field("weight", "Weight", JsonPrimitive(lp.weight))
            groups += PropertyGroup("layoutParams", lp.javaClass.simpleName, params)
        }
        if (view is TextView) {
            val password = view.transformationMethod is android.text.method.PasswordTransformationMethod
                || (view.inputType and 0xfff) in listOf(0x81, 0x91, 0xe1, 0x12)
            groups += PropertyGroup("text", view.javaClass.simpleName, listOf(
                field("text", "Text", JsonPrimitive(if (password) "••••" else view.text.toString().take(4000))),
                field("hint", "Hint", JsonPrimitive(view.hint?.toString()?.take(2000) ?: "")),
                field("textSize", "Text Size (sp)", JsonPrimitive(view.textSize / view.resources.displayMetrics.scaledDensity)),
                field("textColor", "Text Color", color(view.currentTextColor), "color"),
                field("maxLines", "Max Lines", JsonPrimitive(view.maxLines)),
                field("gravity", "Gravity", JsonPrimitive(view.gravity)),
                field("inputType", "Input Type", JsonPrimitive(view.inputType)),
                field("fontStyle", "Font Style", JsonPrimitive(view.typeface?.style ?: 0))
            ))
        }
        val parent = view.parent
        val position = when (parent) {
            is AdapterView<*> -> parent.getPositionForView(view)
            else -> -1
        }
        if (position >= 0) groups += PropertyGroup("list", "List Position", listOf(field("listPosition", "Position", buildJsonObject { put("position", position) })))
        groups += RecyclerViewProperties.groups(view)
        if (view is CompoundButton) groups += PropertyGroup("control", "CompoundButton", listOf(p("checked", "Checked", view.isChecked)))
        val handlers = buildJsonArray {
            if (view.hasOnClickListeners()) add(buildJsonObject {
                put("typeName", "View.OnClickListener"); put("eventName", "Click"); put("origin", "androidView")
                put("enabled", view.isEnabled); put("handlerDescription", "Listener 已注册；未读取私有字段或执行回调")
            })
            if (view.isLongClickable) add(buildJsonObject {
                put("typeName", "View.OnLongClickListener"); put("eventName", "Long Click"); put("origin", "androidView")
                put("enabled", view.isEnabled); put("handlerDescription", "LongClickable=true；不保证已注册 Listener")
            })
        }
        if (handlers.isNotEmpty()) groups += PropertyGroup("events", "Events", listOf(field("eventHandlers", "Events", handlers)))
        return groups
    }
}
