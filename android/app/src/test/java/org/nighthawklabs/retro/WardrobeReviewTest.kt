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
import java.util.UUID

class WardrobeReviewTest {
    private fun fixture(name: String) = javaClass.classLoader!!.getResource("$name.json")!!.readText()
    private fun rejects(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: Exception) { } }
    @Test fun queuedCreateFollowupKeepsOriginalIdentityAcrossRelaunchAndReconciliation() = runTest {
        val root = Files.createTempDirectory("retro-followup").toFile()
        try {
            val writesFile = File(root, "writes.json"); val draftsFile = File(root, "drafts.json")
            val queue = WardrobeWrites(writesFile, { true }, { _, _ -> Api.Ok(true) })
            val garment = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0]
            val fields = JsonObject(WardrobeGarmentDraft(garment).fields() + ("id" to JsonPrimitive(garment.id)))
            queue.enqueue("garments_create", garment.id, garment.name, fields)
            val original = queue.items[0]
            var owner = true
            val drafts = WardrobeSavedDrafts(draftsFile) { owner }
            val entry = drafts.follow(original).let { it.copy(garmentDraft = it.garmentDraft!!.copy(notes = "Later offline edit")) }
            drafts.put(entry)
            assertEquals(original.body, queue.items[0].body); assertEquals(entry.id, drafts.follow(original).id)
            assertNull(drafts.garment(null))
            val restored = WardrobeSavedDrafts(draftsFile) { true }
            val value = restored.items[0]
            assertEquals(garment.id, value.entityID); assertEquals(original.id, value.dependency!!.id)
            assertEquals(original.body, value.dependency.body); assertNull(value.garment)
            val patch = WardrobeDraftValidation.patch(value.garmentDraft!!.fields(), value.originalGarment().fields())
            assertEquals(setOf("notes"), patch.keys)
            owner = false; rejects { drafts.follow(original) }
            queue.remove(original)
            val createdKeys = mutableSetOf<String>()
            val replay = WardrobeWrites(writesFile, { true }, { operation, body ->
                assertEquals(original.operation, operation); assertEquals(original.body, body)
                createdKeys.add(original.id); Api.Ok(true)
            })
            replay.restoreCreate(value.dependency)
            assertTrue(replay.items[0].dispatched); rejects { replay.remove(replay.items[0]) }
            replay.drain(force = true); replay.restoreCreate(original); replay.drain(force = true)
            assertEquals(1, createdKeys.size); assertTrue(replay.items.isEmpty())
            assertEquals("Later offline edit", restored.items[0].garmentDraft!!.notes)
        } finally { root.deleteRecursively() }
    }
    @Test fun queuedOutfitFollowupRetainsStateSourceAndRejectedCreateUsesNewKey() = runTest {
        val root = Files.createTempDirectory("retro-followup").toFile()
        try {
            val queue = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Failed("invalid_input", "Review details") })
            val entity = UUID.randomUUID().toString(); val garmentID = "11111111-1111-4111-8111-111111111111"
            val originalDraft = WardrobeOutfitDraft(day = "2026-10-07", timeZone = "UTC", state = "worn", source = "suggestion", items = listOf(WardrobeSelection(garmentID, "Dress", "one_piece")))
            var fields = JsonObject(originalDraft.fields() + mapOf("id" to JsonPrimitive(entity), "state" to JsonPrimitive(originalDraft.state), "source" to JsonPrimitive(originalDraft.source)))
            queue.enqueue("outfits_create", entity, "Outfit", fields)
            val original = queue.items[0]
            val drafts = WardrobeSavedDrafts(File(root, "drafts.json")) { true }
            val first = drafts.follow(original)
            assertEquals("worn", first.outfitDraft!!.state); assertEquals("suggestion", first.outfitDraft.source)
            val value = first.copy(outfitDraft = first.outfitDraft.copy(notes = "Corrected notes")); drafts.put(value)
            assertNull(drafts.outfit(null, false))
            val patch = WardrobeDraftValidation.patch(value.outfitDraft!!.fields(), value.originalOutfit().fields())
            assertEquals(setOf("notes"), patch.keys)
            rejects { queue.replaceRejected(original.id, "outfits_create", fields) }
            queue.drain(); fields = JsonObject(fields + ("notes" to JsonPrimitive("Corrected notes")))
            queue.replaceRejected(original.id, "outfits_create", fields)
            assertNotEquals(original.id, queue.items[0].id); assertEquals(entity, queue.items[0].entity)
            val replacement = queue.items[0].createFields()
            assertEquals("worn", replacement["state"]!!.jsonPrimitive.content); assertEquals("suggestion", replacement["source"]!!.jsonPrimitive.content)
            assertEquals("Corrected notes", replacement["notes"]!!.jsonPrimitive.content)
            assertEquals(original.body, value.dependency!!.body)
            rejects { drafts.put(value.copy(entityID = UUID.randomUUID().toString())) }
            assertEquals(entity, drafts.items[0].entityID)
        } finally { root.deleteRecursively() }
    }

    @Test fun suggestionAnalysisAuditAndFiltersMatchContract() {
        val suggestions = ApiJson.decodeFromString<WardrobeSuggestions>(fixture("suggestions"))
        assertEquals(9007199254740993L, suggestions.items[0].items[0].version)
        assertEquals(listOf("feet"), suggestions.items[0].missingRoles)
        val analysis = ApiJson.decodeFromString<WardrobeAnalysis>(fixture("analysis"))
        assertEquals(1L, analysis.wearDays); assertEquals(2L, analysis.outfitEvents)
        val audit = ApiJson.decodeFromString<WardrobePage<WardrobeChange>>(fixture("audit"))
        assertEquals(9007199254740993L, audit.items[0].id)
        assertTrue(audit.items[0].details.contains("9007199254740993"))
        val id = suggestions.items[0].items[0].garmentID
        val query = WardrobeHistoryQuery(from = "2026-10-01", to = "2026-10-07", garmentID = id)
        val fields = ApiJson.parseToJsonElement(ApiJson.encodeToString(query)).jsonObject
        assertEquals(id, fields["garment_id"]!!.jsonPrimitive.content)
        assertEquals(query.from, fields["from"]!!.jsonPrimitive.content)
        rejects { WardrobeSuggestQuery("2026-10-07", requiredIDs = listOf(id), excludedIDs = listOf(id)).validate() }
        rejects { WardrobeSuggestQuery("2026-02-30").validate() }
    }
    @Test fun draftRelaunchKeepsBaselineEntityAndEditsAndFencesOwner() {
        val root = Files.createTempDirectory("retro-drafts").toFile()
        try {
            var owner = true
            val file = File(root, "drafts.json")
            val garment = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0]
            val edited = WardrobeGarmentDraft(garment).copy(notes = "Unsaved after pending edit")
            val entry = WardrobeSavedDraft(UUID.randomUUID().toString(), garment.id, garment = garment, garmentDraft = edited)
            val drafts = WardrobeSavedDrafts(file) { owner }
            drafts.put(entry)
            val restored = WardrobeSavedDrafts(file) { true }
            assertEquals(9007199254740993L, restored.items[0].garment!!.version)
            assertEquals(edited, restored.items[0].garmentDraft)
            assertEquals(garment.id, restored.items[0].entityID)
            owner = false; rejects { drafts.remove(entry.id) }; rejects { drafts.put(entry) }
            file.writeText("damaged")
            val damaged = WardrobeSavedDrafts(file) { true }
            assertNotNull(damaged.problem); rejects { damaged.put(entry) }
            assertEquals("damaged", file.readText())
        } finally { root.deleteRecursively() }
    }
    @Test fun reviewedReplacementIsAtomicAndCannotReplaceUncertainSaves() = runTest {
        val root = Files.createTempDirectory("retro-review").toFile()
        try {
            val file = File(root, "writes.json")
            var refuseStorage = false
            val queue = WardrobeWrites(file, { true }, { _, _ -> Api.Failed("conflict", "changed") }, { values ->
                check(!refuseStorage) { "disk full" }; file.writeText(ApiJson.encodeToString(values))
            })
            val entity = "11111111-1111-4111-8111-111111111111"
            queue.enqueue("garments_update", entity, "Edit", buildJsonObject { put("id", entity); put("expected_version", 1); put("patch", buildJsonObject { put("notes", "requested") }) })
            val original = queue.items[0]
            val fields = buildJsonObject { put("id", entity); put("expected_version", 9007199254740993L); put("patch", buildJsonObject { put("notes", "reviewed") }) }
            rejects { queue.replaceRejected(original.id, "garments_update", fields) }
            queue.drain(); refuseStorage = true
            rejects { queue.replaceRejected(original.id, "garments_update", fields) }
            assertEquals(original.body, queue.items[0].body); assertTrue(queue.items[0].rejected)
            refuseStorage = false; queue.replaceRejected(original.id, "garments_update", fields)
            assertNotEquals(original.id, queue.items[0].id); assertFalse(queue.items[0].dispatched); assertFalse(queue.items[0].rejected)
            assertEquals(9007199254740993L, queue.items[0].body["expected_version"]!!.jsonPrimitive.long)
            assertEquals(queue.items[0].body, WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) }).items[0].body)
        } finally { root.deleteRecursively() }
    }
    @Test fun suggestionsRefreshExactPiecesAndRejectChangedVersions() = runTest {
        val root = Files.createTempDirectory("retro-review").toFile()
        try {
            val garment = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0]
            val transport = Transport { _, _, _, _, _ -> 200 to ApiJson.encodeToString(WardrobeGarmentResult(garment)) }
            val engine = Engine(RetroApi("https://review.test/api/v1", transport), "A", { "A" }) { "token" }
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", "review")) { true }
            val suggestion = ApiJson.decodeFromString<WardrobeSuggestions>(fixture("suggestions")).items[0]
            val input = WardrobeSuggestQuery("2026-10-07")
            val draft = store.reviewSuggestion(suggestion, input)
            assertEquals(garment.name, draft.items[0].name); assertEquals("suggestion", draft.source); assertEquals("planned", draft.state)
            try { store.reviewSuggestion(suggestion.copy(items = suggestion.items.map { it.copy(version = 1) }), input); fail("Changed piece must require regeneration") } catch (_: IllegalStateException) { }
        } finally { root.deleteRecursively() }
    }
    @Test fun automaticRetryCooldownSurvivesRelaunchWithoutChangingPayload() = runTest {
        val root = Files.createTempDirectory("retro-retry").toFile()
        try {
            val file = File(root, "writes.json")
            var calls = 0
            val first = WardrobeWrites(file, { true }, { _, _ -> calls++; Api.Retry("offline") })
            first.enqueue("garments_create", "11111111-1111-4111-8111-111111111111", "Draft", JsonObject(emptyMap()))
            val body = first.items[0].body
            first.drain(); assertNotNull(first.items[0].retryAfter)
            val restored = WardrobeWrites(file, { true }, { _, payload -> calls++; assertEquals(body, payload); Api.Ok(true) })
            restored.drain(); assertEquals(1, calls)
            restored.drain(force = true); assertEquals(2, calls); assertTrue(restored.items.isEmpty())
        } finally { root.deleteRecursively() }
    }
}
