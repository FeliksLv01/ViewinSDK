package app.viewin.demo

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.graphics.Color
import android.view.ViewGroup
import android.widget.*
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.viewin.sdk.Viewin

class MainActivity : Activity() {
    private var clicks = 0
    private lateinit var rows: RecyclerView
    private lateinit var headers: DemoAdapter
    private lateinit var items: DemoAdapter
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<Button>(R.id.action_button).setOnClickListener {
            clicks++
            findViewById<TextView>(R.id.subtitle).text = "Captured after $clicks clicks"
        }
        findViewById<Button>(R.id.dialog_button).setOnClickListener {
            val dialog = AlertDialog.Builder(this).setTitle("Inspect a dialog").setMessage("A registered Android window")
                .setPositiveButton("Done", null).create()
            dialog.setOnDismissListener { dialog.window?.let(Viewin::unregisterWindow) }
            dialog.show()
            dialog.window?.let(Viewin::registerWindow)
        }
        val root = findViewById<TextView>(R.id.title).parent as LinearLayout
        root.addView(Button(this).apply {
            id = R.id.compose_button; text = "Inspect Compose"
            setOnClickListener { startActivity(android.content.Intent(this@MainActivity, ComposeActivity::class.java)) }
        }, root.indexOfChild(findViewById(R.id.rows)))
        rows = findViewById(R.id.rows)
        rows.layoutManager = LinearLayoutManager(this)
        configureAdapters(true)
        findViewById<Switch>(R.id.toggle).setOnCheckedChangeListener { _, enabled -> configureAdapters(enabled) }
        findViewById<Button>(R.id.grid_button).setOnClickListener { button ->
            val grid = rows.layoutManager !is GridLayoutManager
            rows.layoutManager = if (grid) GridLayoutManager(this, 2) else LinearLayoutManager(this)
            (button as Button).text = if (grid) "Linear" else "Grid"
        }
        findViewById<Button>(R.id.remove_button).setOnClickListener { headers.removeFirst() }
    }
    private fun configureAdapters(stable: Boolean) {
        headers = DemoAdapter("Header", 9_100_000_000_000_000L, 3, stable)
        items = DemoAdapter("Item", 9_200_000_000_000_000L, 97, stable)
        rows.adapter = ConcatAdapter(ConcatAdapter.Config.Builder().setStableIdMode(
            if (stable) ConcatAdapter.Config.StableIdMode.SHARED_STABLE_IDS else ConcatAdapter.Config.StableIdMode.NO_STABLE_IDS
        ).build(), headers, items)
    }
}

private data class DemoRow(val id: Long, val originalIndex: Int, val label: String, var selected: Boolean = false)
private open class DemoHolder(val root: LinearLayout, val title: TextView, val detail: TextView) : RecyclerView.ViewHolder(root)
private class HeaderHolder(root: LinearLayout, title: TextView, detail: TextView) : DemoHolder(root, title, detail)
private class ItemHolder(root: LinearLayout, title: TextView, detail: TextView) : DemoHolder(root, title, detail)

private class DemoAdapter(private val prefix: String, base: Long, count: Int, stable: Boolean) : RecyclerView.Adapter<DemoHolder>() {
    private val data = MutableList(count) { DemoRow(base + it, it, "$prefix $it") }
    init { setHasStableIds(stable) }
    override fun getItemCount() = data.size
    override fun getItemId(position: Int) = data[position].id
    override fun getItemViewType(position: Int) = data[position].originalIndex % 2
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DemoHolder {
        val context = parent.context
        fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
        val root = LinearLayout(context).apply {
            id = R.id.row
            orientation = LinearLayout.VERTICAL
            layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72))
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setBackgroundColor(if (viewType == 0) Color.WHITE else Color.rgb(244, 247, 252))
        }
        val title = TextView(context).apply { id = R.id.row_title; textSize = 16f; setTextColor(Color.BLACK) }
        val detail = TextView(context).apply { id = R.id.row_detail; textSize = 11f; setTextColor(Color.DKGRAY) }
        root.addView(title); root.addView(detail)
        return if (prefix == "Header") HeaderHolder(root, title, detail) else ItemHolder(root, title, detail)
    }
    override fun onBindViewHolder(holder: DemoHolder, position: Int) {
        val row = data[position]
        holder.root.tag = "$prefix-${row.originalIndex}"
        holder.title.text = row.label + if (row.selected) " · selected" else ""
        holder.detail.text = "type ${getItemViewType(position)} · id ${row.id}"
        holder.root.setOnClickListener {
            val current = holder.bindingAdapterPosition
            if (current != RecyclerView.NO_POSITION && current < data.size) {
                data[current].selected = !data[current].selected
                notifyItemChanged(current)
            }
        }
    }
    fun removeFirst() {
        if (data.isEmpty()) return
        data.removeAt(0)
        notifyItemRemoved(0)
    }
}
