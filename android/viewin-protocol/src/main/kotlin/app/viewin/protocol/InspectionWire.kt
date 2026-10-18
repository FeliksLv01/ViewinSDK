package app.viewin.protocol

import kotlinx.serialization.Serializable
import java.io.DataInputStream
import java.io.DataOutputStream

object InspectionWire {
    const val SERVICE = "app.viewin.inspection"
    const val VERSION = 1
    const val DEFAULT_PORT = 48721
    // Matches desktop per-frame transport budget; not an archive-size restriction.
    const val MAX_FRAME = 256_000_000
    fun read(input: DataInputStream, maxBytes: Int = MAX_FRAME): ByteArray {
        val size = input.readInt()
        require(size in 1..maxBytes) { "Invalid frame length" }
        return ByteArray(size).also(input::readFully)
    }
    fun write(output: DataOutputStream, bytes: ByteArray) {
        require(bytes.isNotEmpty() && bytes.size <= MAX_FRAME) { "Invalid frame length" }
        output.writeInt(bytes.size)
        output.write(bytes)
        output.flush()
    }
}

@Serializable data class InspectionRequest(
    val service: String, val version: Int, val id: String, val method: String
)
@Serializable data class InspectionResponse(
    val service: String = InspectionWire.SERVICE,
    val version: Int = InspectionWire.VERSION,
    val id: String,
    val target: Target? = null,
    val snapshot: Snapshot? = null,
    val imageIds: List<String> = emptyList(),
    val error: String? = null
)
