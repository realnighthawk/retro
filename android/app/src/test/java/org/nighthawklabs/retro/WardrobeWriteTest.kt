package org.nighthawklabs.retro

import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import java.io.File
import java.nio.file.Files
import java.time.LocalDate

class WardrobeWriteTest {
    private val entity = "11111111-1111-4111-8111-111111111111"
    private fun fields() = buildJsonObject { put("id", entity); put("name", "Shirt"); put("category", "top") }
    private fun rejects(action: () -> Unit) { try { action(); fail("Expected rejection") } catch (_: Exception) { } }

    @Test fun lostResponseRelaunchReusesFrozenPayloadAndRejectsStaleDiscard() = runTest {
        val root = Files.createTempDirectory("retro-write").toFile()
        try {
            val file = File(root, "pending.json")
            var firstBody: JsonObject? = null
            val first = WardrobeWrites(file, { true }, { _, body -> firstBody = body; Api.Retry("lost response") })
            first.enqueue("garments_create", entity, "Shirt", fields())
            val staleUnsent = first.items[0]
            assertFalse(first.drain())
            rejects { first.remove(staleUnsent) }
            var replayBody: JsonObject? = null
            val restored = WardrobeWrites(file, { true }, { _, body -> replayBody = body; Api.Ok(true) })
            assertTrue(restored.items[0].dispatched)
            assertTrue(restored.drain(force = true))
            assertEquals(firstBody, replayBody)
            assertTrue(restored.items.isEmpty())
            assertTrue(WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) }).items.isEmpty())
        } finally { root.deleteRecursively() }
    }

    @Test fun persistenceFailureDoesNotAcceptOrSend() = runTest {
        var sends = 0
        val queue = WardrobeWrites(File("unused"), { true }, { _, _ -> sends++; Api.Ok(true) }, { throw IllegalStateException("disk full") })
        rejects { queue.enqueue("garments_create", entity, "Shirt", fields()) }
        assertTrue(queue.items.isEmpty())
        assertFalse(queue.drain())
        assertEquals(0, sends)
    }

    @Test fun acknowledgementStorageFailureKeepsOriginalRequest() = runTest {
        val root = Files.createTempDirectory("retro-write").toFile()
        try {
            val file = File(root, "pending.json")
            var saves = 0
            val queue = WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) }, { items ->
                saves++
                if (saves == 3) throw IllegalStateException("disk full")
                file.writeText(ApiJson.encodeToString(kotlinx.serialization.serializer<List<WardrobePending>>(), items))
            })
            val fields = JsonObject(WardrobeDraftValidation.edit(entity, 9007199254740993L) + ("patch" to buildJsonObject { put("name", "Shirt") }))
            queue.enqueue("garments_update", entity, "Shirt", fields)
            val body = queue.items[0].body
            assertFalse(queue.drain())
            assertNotNull(queue.problem)
            val restored = WardrobeWrites(file, { true }, { _, replay -> assertEquals(body, replay); Api.Ok(true) })
            assertEquals(body, restored.items[0].body)
            assertEquals(9007199254740993L, restored.items[0].body["expected_version"]!!.jsonPrimitive.long)
            assertTrue(restored.drain(force = true))
        } finally { root.deleteRecursively() }
    }

    @Test fun conflictNeedsReviewAndUnrelatedRecordsContinue() = runTest {
        val root = Files.createTempDirectory("retro-write").toFile()
        try {
            val queue = WardrobeWrites(File(root, "pending.json"), { true }, { op, _ ->
                if (op == "garments_update") Api.Failed("conflict", "Version changed") else Api.Ok(true)
            })
            queue.enqueue("garments_update", entity, "Shirt", JsonObject(WardrobeDraftValidation.edit(entity, 1) + ("patch" to buildJsonObject { put("name", "New shirt") })))
            rejects { queue.enqueue("garments_archive", entity, "Shirt", fields()) }
            queue.enqueue("outfits_create", "22222222-2222-4222-8222-222222222222", "Other", buildJsonObject {})
            assertTrue(queue.drain())
            assertEquals(1, queue.items.size)
            assertTrue(queue.items[0].rejected)
            assertTrue(queue.items[0].requestedSummary.contains("New shirt"))
            queue.remove(queue.items[0]); assertTrue(queue.items.isEmpty())
        } finally { root.deleteRecursively() }
    }

    @Test fun accountSwitchAndCancellationRetainDispatchedRequests() = runTest {
        val root = Files.createTempDirectory("retro-write").toFile()
        try {
            val file = File(root, "pending.json")
            var owner = true
            var sends = 0
            val queue = WardrobeWrites(file, { owner }, { _, _ -> sends++; owner = false; Api.Ok(true) })
            queue.enqueue("garments_create", entity, "Shirt", fields())
            assertFalse(queue.drain()); assertTrue(queue.items[0].dispatched)
            assertFalse(queue.drain()); assertEquals(1, sends)
            val cancelled = WardrobeWrites(file, { true }, { _, _ -> throw CancellationException() })
            val task = launch { cancelled.drain() }
            task.join()
            assertTrue(cancelled.items[0].dispatched)
            assertFalse(cancelled.sending)
        } finally { root.deleteRecursively() }
    }

    @Test fun unreadableQueueBlocksReplacement() {
        val root = Files.createTempDirectory("retro-write").toFile()
        try {
            val file = File(root, "pending.json").apply { writeText("broken") }
            val queue = WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) })
            assertNotNull(queue.problem)
            rejects { queue.enqueue("garments_create", entity, "Shirt", fields()) }
            assertEquals("broken", file.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun draftValidationAndCorrectionKeepUnchangedSnapshots() {
        rejects { WardrobeGarmentDraft(name = "é".repeat(51)).fields() }
        rejects { WardrobeGarmentDraft(name = "Shirt", colours = "blue, blue").fields() }
        val fixture = javaClass.classLoader!!.getResource("day.json")!!.readText()
        val outfit = ApiJson.decodeFromString<WardrobeDay>(fixture).outfits[0]
        val draft = WardrobeOutfitDraft(outfit)
        val patch = WardrobeDraftValidation.patch(draft.copy(label = "Corrected label").fields(), draft.fields())
        assertEquals(setOf("label"), patch.keys)
        val future = draft.copy(day = LocalDate.now().plusDays(3).toString())
        rejects { future.fields() }
        future.copy(state = "planned").fields()
        rejects { draft.copy(items = draft.items + draft.items).fields() }
    }
}
