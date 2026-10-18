package app.viewin.sdk

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Looper
import android.view.Window
import java.lang.ref.WeakReference

/** Explicit opt-in, in Application.onCreate before activities are created. */
object Viewin {
    enum class BuildType(val wireValue: String) { DEBUG("debug"), INTERNAL_RELEASE("internalRelease"), UNKNOWN("unknown") }
    private var session: Session? = null

    @JvmStatic @JvmOverloads
    fun start(application: Application, port: Int = 48721, buildType: BuildType = BuildType.UNKNOWN) {
        check(Looper.myLooper() == Looper.getMainLooper()) { "Viewin.start must run on the main thread" }
        require(port in 1024..65535)
        if (session != null) return
        ComposeInspection.adapter?.prepare(application.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0)
        val state = Session(application)
        val collector = ViewCollector(application, state, buildType)
        state.server = InspectionServer(port, collector)
        application.registerActivityLifecycleCallbacks(state)
        session = state
        state.server.start()
    }

    @JvmStatic fun stop() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "Viewin.stop must run on the main thread" }
        val state = session ?: return
        state.application.unregisterActivityLifecycleCallbacks(state)
        state.server.stop()
        state.activities.clear()
        state.extraWindows.clear()
        session = null
    }

    /** Optional Dialog/Popup windows, without hidden WindowManager APIs. Call after showing. */
    @JvmStatic fun registerWindow(window: Window) {
        check(Looper.myLooper() == Looper.getMainLooper())
        session?.extraWindows?.let { windows ->
            windows.removeAll { it.get() == null || it.get() === window }
            windows += WeakReference(window)
        }
    }
    @JvmStatic fun unregisterWindow(window: Window) {
        check(Looper.myLooper() == Looper.getMainLooper())
        session?.extraWindows?.removeAll { it.get() == null || it.get() === window }
    }

    internal class Session(val application: Application) : Application.ActivityLifecycleCallbacks {
        lateinit var server: InspectionServer
        val activities = mutableListOf<WeakReference<Activity>>()
        val extraWindows = mutableListOf<WeakReference<Window>>()
        fun windows(): List<Window> {
            activities.removeAll { it.get() == null }
            extraWindows.removeAll { it.get() == null }
            if (activities.isEmpty()) return emptyList()
            return (activities.mapNotNull { it.get()?.window } + extraWindows.mapNotNull { it.get() })
                .distinct().filter { it.decorView.isAttachedToWindow && it.decorView.isShown }
        }
        override fun onActivityResumed(activity: Activity) {
            activities.removeAll { it.get() == null || it.get() === activity }
            activities += WeakReference(activity)
        }
        override fun onActivityPaused(activity: Activity) { activities.removeAll { it.get() == null || it.get() === activity } }
        override fun onActivityDestroyed(activity: Activity) { onActivityPaused(activity) }
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    }
}
