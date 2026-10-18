package app.viewin.sdk

import android.graphics.Bitmap
import android.view.View
import app.viewin.protocol.SnapshotNode

/** Optional adapter contract; the base SDK has no Compose dependency. */
interface ComposeInspectionAdapter {
    fun prepare(debuggable: Boolean)
    fun isHost(view: View): Boolean
    fun capture(view: View, windowId: String, hostId: String, origin: IntArray,
                maxNodes: Int, maxDepth: Int, deadline: Long, store: (Bitmap) -> String?): ComposeCapture
}
data class ComposeCapture(val nodes: List<SnapshotNode>, val roots: List<String>,
                          val backend: String, val partial: Boolean, val reason: String? = null)

internal object ComposeInspection {
    val adapter: ComposeInspectionAdapter? by lazy {
        try {
            Class.forName("app.viewin.compose.ComposeAdapter").getDeclaredConstructor().newInstance() as ComposeInspectionAdapter
        } catch (_: ReflectiveOperationException) { null } catch (_: LinkageError) { null }
    }
}
