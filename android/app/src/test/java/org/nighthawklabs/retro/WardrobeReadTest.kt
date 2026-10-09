package org.nighthawklabs.retro

import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.KSerializer
import org.junit.Assert.*
import org.junit.Test
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*

class WardrobeReadTest {
    private fun fixture(name: String) = requireNotNull(javaClass.getResourceAsStream("/$name.json"))
        .bufferedReader().use { it.readText() }

    @Test fun `wire fields preserve versions arbitrary colours and wear snapshots`() {
        val inventory = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory"))
        assertEquals(9_007_199_254_740_993L, inventory.items.single().version)
        assertEquals(listOf("chartreuse", "navy"), inventory.items.single().colours)
        assertNull(inventory.items.single().material)
        assertEquals(1L, inventory.items.single().wearDays)
        assertEquals(2L, inventory.items.single().wearEvents)
        val day = ApiJson.decodeFromString<WardrobeDay>(fixture("day"))
        assertEquals(2, day.outfits.size)
        assertEquals(setOf("2026-10-07"), day.outfits.map { it.day }.toSet())
        assertEquals("America/Los_Angeles", day.outfits.first().timeZone)
        assertEquals("one_piece", day.outfits.first().items.single().role)
        assertEquals("Blue dress", day.outfits.first().items.single().snapshot?.name)
        assertNotEquals(inventory.items.single().name, day.outfits.first().items.single().snapshot?.name)
    }

    @Test fun `old query response cannot replace or cache newer query`() = runTest {
        val root = Files.createTempDirectory("retro-read-test").toFile()
        try {
            val started = CompletableDeferred<Unit>()
            val release = CompletableDeferred<String>()
            val engine = FakeEngine { _, body ->
                if (body.contains("\"top\"")) { started.complete(Unit); Api.Ok(release.await()) }
                else Api.Ok("""{"items":[],"next_cursor":null}""")
            }
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", "test")) { true }
            val old = launch { store.refreshInventory(WardrobeInventoryQuery(category = "top")) }
            started.await()
            store.refreshInventory(WardrobeInventoryQuery(category = "bottom"))
            release.complete(fixture("inventory"))
            old.join()
            assertTrue(store.inventory.value!!.items.isEmpty())
            engine.respond = { _, _ -> Api.Retry("offline") }
            store.refreshInventory(WardrobeInventoryQuery(category = "top"))
            assertNull(store.inventory.value)
        } finally { root.deleteRecursively() }
    }

    @Test fun `reads survive offline refresh without crossing query account or service`() = runTest {
        val root = Files.createTempDirectory("retro-read-test").toFile()
        try {
            val engine = FakeEngine { _, _ -> Api.Ok(fixture("inventory")) }
            val cache = WardrobeReadCache(root, "A", "production")
            val store = WardrobeStore(engine, cache) { true }
            store.refreshInventory(WardrobeInventoryQuery())
            engine.respond = { _, _ -> Api.Retry("offline") }
            val offline = WardrobeStore(engine, cache) { true }
            offline.refreshInventory(WardrobeInventoryQuery())
            assertEquals(1, offline.inventory.value!!.items.size)
            assertTrue(offline.inventory.cached)
            assertNotNull(offline.inventory.problem)
            offline.refreshInventory(WardrobeInventoryQuery(category = "top"))
            assertNull(offline.inventory.value)
            for (other in listOf(WardrobeReadCache(root, "B", "production"), WardrobeReadCache(root, "A", "local"))) {
                val isolated = WardrobeStore(engine, other) { true }
                isolated.refreshInventory(WardrobeInventoryQuery())
                assertNull(isolated.inventory.value)
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun `account switch while reading does not publish or cache old response`() = runTest {
        val root = Files.createTempDirectory("retro-read-test").toFile()
        try {
            var owner = true
            val engine = FakeEngine { _, _ -> owner = false; Api.Ok(fixture("inventory")) }
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", "test")) { owner }
            store.refreshInventory(WardrobeInventoryQuery())
            assertNull(store.inventory.value)
            owner = true
            engine.respond = { _, _ -> Api.Retry("offline") }
            store.refreshInventory(WardrobeInventoryQuery())
            assertNull(store.inventory.value)
        } finally { root.deleteRecursively() }
    }

    @Test fun `engine discards a successful reply after identity changes`() = runTest {
        var owner = "A"
        val api = RetroApi("https://wardrobe.test/api/v1") { _, _, _, _, _ -> owner = "B"; 200 to fixture("inventory") }
        val engine = Engine(api, "A", { owner }) { "token" }
        val result = engine.call<WardrobeInventoryQuery, WardrobePage<WardrobeGarment>>("garments_list", WardrobeInventoryQuery())
        assertTrue(result is Api.Unauthorized)
    }

    @Test fun `pagination does not duplicate items and preserves cached cursor`() = runTest {
        val root = Files.createTempDirectory("retro-read-test").toFile()
        try {
            val body = fixture("inventory")
            val engine = FakeEngine { _, request -> Api.Ok(if (request.contains("opaque-cursor")) body.replace("\"opaque-cursor\"", "null") else body) }
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", "test")) { true }
            store.refreshInventory(WardrobeInventoryQuery())
            store.moreInventory()
            assertEquals(1, store.inventory.value!!.items.size)
            assertNull(store.inventory.value!!.nextCursor)
        } finally { root.deleteRecursively() }
    }

    private class FakeEngine(var respond: suspend (String, String) -> Api<String>) : EngineApi {
        override suspend fun <I, O> call(op: String, input: I, inSer: KSerializer<I>, outSer: KSerializer<O>): Api<O> =
            respond(op, ApiJson.encodeToString(inSer, input)).map { ApiJson.decodeFromString(outSer, it) }
    }
}
