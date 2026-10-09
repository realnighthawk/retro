package org.nighthawklabs.retro

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import java.io.File
import java.nio.file.Files
import java.time.ZoneId
import java.util.UUID

class WardrobeAssistanceTest {
    private val extraID = "11111111-1111-4111-8111-222222222222"
    private fun fixture(name: String) = javaClass.classLoader!!.getResource("$name.json")!!.readText()
    private fun rejects(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: Exception) { } }
    @Test fun reuseMakesNewPlanWithExplicitReplacementAndNewRequestIdentity() {
        val historical = ApiJson.decodeFromString<WardrobePage<WardrobeOutfit>>(fixture("history")).items[0]
        val original = historical.copy(occasion = "Dinner", notes = "Notes about that wear", source = "suggestion")
        val piece = original.items[0]
        val review = WardrobeReuseReview(original, listOf(WardrobeReusePiece(piece.garmentID, "Archived dress", piece.role, "Archived")))
        val day = "2026-10-20"
        rejects { review.plan(day, emptyMap(), emptySet()) }
        rejects { review.plan(day, emptyMap(), setOf(piece.garmentID)) }
        rejects { review.plan(day, mapOf(extraID to WardrobeSelection(extraID, "New", "base")), emptySet()) }
        val plan = review.plan(day, mapOf(piece.garmentID to WardrobeSelection(extraID, "Ready dress", "base")), emptySet())
        assertEquals(piece.role, plan.items[0].role); assertEquals(extraID, plan.items[0].id)
        assertEquals("planned", plan.state); assertEquals("manual", plan.source); assertEquals("", plan.notes)
        assertEquals(day, plan.day); assertEquals(ZoneId.systemDefault().id, plan.timeZone); assertEquals("Dinner", plan.occasion)
        assertEquals("worn", original.state); assertEquals(historical.items[0].snapshot, original.items[0].snapshot)
        val root = Files.createTempDirectory("retro-reuse").toFile()
        try {
            val queue = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val entity = UUID.randomUUID().toString()
            val fields = JsonObject(plan.fields() + mapOf("id" to JsonPrimitive(entity), "state" to JsonPrimitive(plan.state), "source" to JsonPrimitive(plan.source)))
            queue.enqueue("outfits_create", entity, "Reused plan", fields)
            assertNotEquals(original.id, queue.items[0].entity)
            val body = queue.items[0].createFields()
            assertEquals("planned", body["state"]!!.jsonPrimitive.content); assertEquals("manual", body["source"]!!.jsonPrimitive.content)
            assertEquals(entity, body["id"]!!.jsonPrimitive.content); assertNull(body["confirmed_at"])
        } finally { root.deleteRecursively() }
        val repeated = WardrobeReuseReview(original, review.pieces + WardrobeReusePiece(extraID, "Other", "feet"))
        rejects { repeated.plan(day, mapOf(piece.garmentID to WardrobeSelection(extraID, "Same", "base")), emptySet()) }
    }
    @Test fun comparisonUsesActualPiecesAndRejectsForgedOrMissingDrafts() {
        val query = WardrobeSuggestQuery("2026-10-07")
        val first = ApiJson.decodeFromString<WardrobeSuggestions>(fixture("suggestions")).items[0]
        val second = first.copy(items = first.items + WardrobeSuggestedItem(extraID, "feet", 2), fingerprint = "another-real-option", reasons = listOf("Footwear included"), missingRoles = emptyList())
        fun draft(option: WardrobeSuggestion) = WardrobeOutfitDraft(day = query.day, source = "suggestion", items = option.items.map { WardrobeSelection(it.garmentID, "Actual piece", it.role) })
        val drafts = mapOf(first.fingerprint to draft(first), second.fingerprint to draft(second))
        val comparison = WardrobeComparison(query, listOf(first, second), drafts)
        assertEquals(first.items.map { it.garmentID }.toSet(), comparison.sharedIDs)
        assertEquals(second.reasons, comparison.candidates[1].option.reasons)
        assertEquals(listOf(extraID), comparison.candidates[1].draft.items.filter { it.id !in comparison.sharedIDs }.map { it.id })
        rejects { WardrobeComparison(query, listOf(first, first), drafts) }
        rejects { WardrobeComparison(query, listOf(first, second), mapOf(first.fingerprint to draft(first))) }
        val forged = draft(second).copy(items = draft(second).items.mapIndexed { index, it -> if (index == 0) it.copy(role = "base") else it })
        rejects { WardrobeComparison(query, listOf(first, second), mapOf(first.fingerprint to draft(first), second.fingerprint to forged)) }
        val invented = draft(second).copy(items = draft(second).items.mapIndexed { index, it -> if (index == 0) it.copy(id = UUID.randomUUID().toString()) else it })
        rejects { WardrobeComparison(query, listOf(first, second), mapOf(first.fingerprint to draft(first), second.fingerprint to invented)) }
    }
    @Test fun reuseRefreshesLiveGarmentsAndRejectsPendingStaleServiceAndAccountChanges() = runTest {
        val root = Files.createTempDirectory("retro-reuse").toFile()
        try {
            val original = ApiJson.decodeFromString<WardrobePage<WardrobeOutfit>>(fixture("history")).items[0]
            val garment = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0]
            var currentOwner = "A"; var switchOwner = false; var status = 200
            var garmentText = ApiJson.encodeToString(WardrobeGarmentResult(garment))
            val transport = Transport { _, url, _, _, _ ->
                if (switchOwner) currentOwner = "B"
                if (url.endsWith("outfits_get")) 200 to ApiJson.encodeToString(WardrobeOutfitResult(original)) else status to garmentText
            }
            val engine = Engine(RetroApi("https://reuse.test/api/v1", transport), "A", { currentOwner }) { "token" }
            val queue = WardrobeWrites(File(root, "writes.json"), { currentOwner == "A" }, { _, _ -> Api.Ok(true) })
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", "reuse"), writes = queue) { currentOwner == "A" }
            val fresh = store.reuseOutfit(original.id)
            assertEquals(garment.name, fresh.pieces[0].name); assertNull(fresh.pieces[0].problem)
            assertEquals(original, fresh.outfit); assertNotEquals(original.items[0].snapshot?.name, fresh.pieces[0].name)
            val plan = fresh.plan("2026-10-20", emptyMap(), emptySet())
            garmentText = ApiJson.encodeToString(WardrobeGarmentResult(garment.copy(availability = "washing")))
            assertEquals("Washing", store.reuseOutfit(original.id).pieces[0].problem)
            try { store.refreshReusePlan(plan); fail("Unavailable piece cannot seed a plan") } catch (_: IllegalStateException) { }
            garmentText = ApiJson.encodeToString(WardrobeGarmentResult(garment.copy(archivedAt = "2026-10-08T00:00:00Z")))
            assertEquals("Archived", store.reuseOutfit(original.id).pieces[0].problem)
            garmentText = ApiJson.encodeToString(WardrobeGarmentResult(garment))
            queue.enqueue("garments_update", garment.id, "Pending", buildJsonObject { put("id", garment.id); put("expected_version", garment.version); put("patch", buildJsonObject { put("notes", "Edited") }) })
            assertEquals("Pending save", store.reuseOutfit(original.id).pieces[0].problem)
            try { store.refreshReusePlan(plan); fail("Pending piece cannot seed a plan") } catch (_: IllegalStateException) { }
            queue.remove(queue.items[0])
            status = 404; garmentText = """{"error":{"code":"not_found","message":"Missing garment"}}"""
            val missing = store.reuseOutfit(original.id)
            assertEquals(original.items[0].snapshot?.name, missing.pieces[0].name); assertNotNull(missing.pieces[0].problem)
            status = 503
            try { store.reuseOutfit(original.id); fail("Service failure cannot be treated as a missing piece") } catch (_: IllegalStateException) { }
            switchOwner = true
            try { store.reuseOutfit(original.id); fail("Old account must not receive a reusable plan") } catch (_: IllegalStateException) { }
            assertTrue(queue.items.isEmpty())
        } finally { root.deleteRecursively() }
    }
}
