package app.viewin.protocol

import java.io.*
import kotlin.test.*
import kotlinx.serialization.encodeToString

class InspectionWireTest {
    @Test fun framesRoundTripWithBigEndianLength() {
        val bytes = ByteArrayOutputStream()
        val payload = "Viewin".encodeToByteArray()
        InspectionWire.write(DataOutputStream(bytes), payload)
        assertContentEquals(byteArrayOf(0, 0, 0, 6), bytes.toByteArray().take(4).toByteArray())
        assertContentEquals(payload, InspectionWire.read(DataInputStream(ByteArrayInputStream(bytes.toByteArray()))))
    }
    @Test fun rejectsInvalidAndTruncatedFrames() {
        for (size in listOf(-1, 0, 65_537)) {
            val bytes = ByteArrayOutputStream().also { DataOutputStream(it).writeInt(size) }
            assertFailsWith<IllegalArgumentException> { InspectionWire.read(DataInputStream(ByteArrayInputStream(bytes.toByteArray())), 65_536) }
        }
        assertFailsWith<EOFException> { InspectionWire.read(DataInputStream(ByteArrayInputStream(byteArrayOf(0, 0, 0, 2, 1)))) }
    }
    @Test fun helloMatchesDesktopContract() {
        val request = ViewinJson.decodeFromString<InspectionRequest>("""{"service":"app.viewin.inspection","version":1,"id":"92ED0F2B-925E-4FA8-BB66-CEB379CAACCE","method":"hello"}""")
        val response = InspectionResponse(id = request.id)
        val decoded = ViewinJson.decodeFromString<InspectionResponse>(ViewinJson.encodeToString(response))
        assertEquals(InspectionWire.SERVICE, decoded.service)
        assertEquals(1, decoded.version)
        assertEquals(request.id, decoded.id)
        assertTrue(decoded.imageIds.isEmpty())
    }
}
