package app.viewin.protocol

import java.io.File
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SnapshotContractTest {
    @Test
    fun sharedFixturesRoundTripWithoutLosingStructure() {
        for (platform in listOf("ios", "android")) {
            val file = File(System.getProperty("viewin.fixtures"), "$platform.json")
            val snapshot = ViewinJson.decodeFromString<Snapshot>(file.readText())
            val restored = ViewinJson.decodeFromString<Snapshot>(ViewinJson.encodeToString(snapshot))
            assertEquals(snapshot, restored)
            assertEquals(platform, snapshot.target.platform)
            assertEquals(2, snapshot.nodes.map { it.framework }.toSet().size)
            assertNull(snapshot.nodes.first { it.id == "screen" }.geometry)
            assertEquals("renderedBy", snapshot.relations.single().kind)
        }
    }
}
