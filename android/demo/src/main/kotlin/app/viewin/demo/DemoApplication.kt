package app.viewin.demo

import android.app.Application
import app.viewin.sdk.Viewin

class DemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Viewin.start(this, buildType = if (BuildConfig.DEBUG) Viewin.BuildType.DEBUG else Viewin.BuildType.INTERNAL_RELEASE)
    }
}
