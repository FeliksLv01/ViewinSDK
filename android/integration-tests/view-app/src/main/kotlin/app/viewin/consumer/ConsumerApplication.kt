package app.viewin.consumer
import android.app.Application
import app.viewin.sdk.Viewin
class ConsumerApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Viewin.start(this, buildType = Viewin.BuildType.INTERNAL_RELEASE)
    }
}
