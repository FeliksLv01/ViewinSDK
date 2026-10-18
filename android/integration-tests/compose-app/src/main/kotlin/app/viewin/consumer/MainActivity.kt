package app.viewin.consumer
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.text.BasicText
class MainActivity : ComponentActivity() {
    override fun onCreate(state: android.os.Bundle?) {
        super.onCreate(state)
        setContent { BasicText("Viewin Maven Compose consumer") }
    }
}
