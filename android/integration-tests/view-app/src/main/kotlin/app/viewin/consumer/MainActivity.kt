package app.viewin.consumer
import android.app.Activity
import android.widget.TextView
class MainActivity : Activity() {
    override fun onCreate(state: android.os.Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Viewin Maven View consumer" })
    }
}
