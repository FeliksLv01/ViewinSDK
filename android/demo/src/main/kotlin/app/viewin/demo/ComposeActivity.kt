package app.viewin.demo

import androidx.activity.ComponentActivity
import android.os.Bundle
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class ComposeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(ComposeView(this).apply { setContent { ComposeDemo() } })
    }
}
@Composable private fun ComposeDemo() {
    var clicks by remember { mutableIntStateOf(0) }
    var enabled by remember { mutableStateOf(true) }
    Column(Modifier.fillMaxSize().background(Color(0xFFF2F2F7)).padding(24.dp).statusBarsPadding().testTag("compose.screen")) {
        BasicText("Viewin Compose Demo", style = TextStyle(fontSize = 25.sp, color = Color.Black))
        Spacer(Modifier.height(10.dp))
        BasicText("Clicked $clicks times", Modifier.testTag("compose.counter"), style = TextStyle(fontSize = 18.sp))
        Spacer(Modifier.height(12.dp))
        Box(Modifier.fillMaxWidth().background(Color(0xFF007AFF)).clickable(enabled = enabled, role = Role.Button) { clicks++ }
            .padding(16.dp).testTag("compose.increment")) {
            BasicText("Update counter", style = TextStyle(color = Color.White, fontSize = 16.sp))
        }
        Spacer(Modifier.height(8.dp))
        BasicText(if (enabled) "Disable counter" else "Enable counter",
            Modifier.fillMaxWidth().clickable { enabled = !enabled }.padding(12.dp).testTag("compose.toggle"))
        LazyColumn(Modifier.fillMaxWidth().weight(1f).testTag("compose.list")) {
            items((0 until 100).toList(), key = { it }) { index ->
                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp).background(Color.White)
                    .semantics { contentDescription = "Compose item $index" }.padding(12.dp).testTag("compose.item.$index")) {
                    BasicText("Compose row $index", style = TextStyle(fontSize = 16.sp, color = Color(0xFF007AFF)))
                    BasicText("LazyColumn · stable key $index", style = TextStyle(fontSize = 12.sp, color = Color.DarkGray))
                }
            }
        }
    }
}
