package app.viewin.sdk

import android.os.Handler
import android.os.Looper
import android.util.Log
import app.viewin.protocol.*
import kotlinx.serialization.encodeToString
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean

internal class InspectionServer(port: Int, private val collector: ViewCollector) {
    private val listener = ServerSocket(port, 4, InetAddress.getByName("127.0.0.1"))
    private val clients = ConcurrentHashMap.newKeySet<Socket>()
    private val slots = Semaphore(4)
    private val workers = Executors.newFixedThreadPool(4) { Thread(it, "Viewin-client").apply { isDaemon = true } }
    private val running = AtomicBoolean(true)
    private val main = Handler(Looper.getMainLooper())
    fun start() {
        Thread({
            while (running.get()) {
                try {
                    val socket = listener.accept()
                    if (!slots.tryAcquire()) { socket.close(); continue }
                    clients += socket
                    try { workers.execute { handle(socket) } }
                    catch (_: RejectedExecutionException) { clients -= socket; socket.close(); slots.release() }
                } catch (error: Exception) {
                    if (running.get()) Log.w("Viewin", "Inspection listener stopped", error)
                    break
                }
            }
        }, "Viewin-listener").apply { isDaemon = true; start() }
    }
    fun stop() {
        running.set(false)
        listener.close()
        clients.forEach { runCatching { it.close() } }
        workers.shutdownNow()
    }
    private fun <T> onMain(block: () -> T): T {
        val task = FutureTask(Callable { check(running.get()); block() })
        main.post(task)
        return try { task.get(20, TimeUnit.SECONDS) }
        finally { main.removeCallbacks(task); task.cancel(false) }
    }
    private fun handle(socket: Socket) {
        try {
            socket.use {
                socket.soTimeout = 30_000
                val input = DataInputStream(socket.getInputStream())
                val output = DataOutputStream(socket.getOutputStream())
                val request = ViewinJson.decodeFromString<InspectionRequest>(InspectionWire.read(input, 64 * 1024).decodeToString())
                require(request.service == InspectionWire.SERVICE && request.version == InspectionWire.VERSION)
                val (response, images) = try { when (request.method) {
                    "hello" -> onMain {
                        val images = collector.preview()
                        InspectionResponse(id = request.id, target = collector.target(), imageIds = images.keys.toList()) to images
                    }
                    "capture" -> onMain {
                        val capture = collector.capture()
                        InspectionResponse(id = request.id, snapshot = capture.snapshot, imageIds = capture.snapshot.images.map { it.id }) to capture.images
                    }
                    else -> InspectionResponse(id = request.id, error = "Unknown inspection method") to emptyMap()
                } } catch (error: Exception) {
                    InspectionResponse(id = request.id, error = error.cause?.message ?: error.message ?: "Capture unavailable") to emptyMap()
                }
                InspectionWire.write(output, ViewinJson.encodeToString(response).encodeToByteArray())
                for (id in response.imageIds) InspectionWire.write(output, images.getValue(id))
            }
        } catch (error: Exception) {
            // Disconnection is expected during discovery; never retry in the background.
            if (running.get() && error !is java.io.IOException) Log.d("Viewin", "Inspection request ended: ${error.javaClass.simpleName}")
        } finally { clients -= socket; slots.release(); runCatching { socket.close() } }
    }
}
