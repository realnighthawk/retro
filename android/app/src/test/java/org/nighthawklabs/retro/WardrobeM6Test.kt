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

class WardrobeM6Test {
    private fun fixture(name: String) = javaClass.classLoader!!.getResource("$name.json")!!.readText()
    private fun rejects(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: Exception) { } }
    @Test fun launcherEntriesRejectUnknownOversizedAndUnexpectedParameters() {
        assertNotNull(WardrobeEntryRequest.parse(WardrobeEntryRequest.ADD, null))
        assertEquals("Blue & white", WardrobeEntryRequest.parse(WardrobeEntryRequest.SEARCH, "Blue & white")?.query)
        assertNotNull(WardrobeEntryRequest.parse(WardrobeEntryRequest.TODAY, null))
        assertNull(WardrobeEntryRequest.parse("DELETE", null)); assertNull(WardrobeEntryRequest.parse(WardrobeEntryRequest.ADD, "garment-id"))
        assertNull(WardrobeEntryRequest.parse(WardrobeEntryRequest.SEARCH, "é".repeat(51))); assertNull(WardrobeEntryRequest.parse(WardrobeEntryRequest.SEARCH, "line\nbreak"))
    }
    @Test fun reviewUsesWholePeriodCountsAndRejectsWrongDatesAndInventedTotals() {
        val value = ApiJson.decodeFromString<WardrobeAnalysis>(fixture("analysis"))
        val query = WardrobeAnalysisQuery("2026-10-01", "2026-10-07")
        assertEquals("2 confirmed outfit events across 1 day. 0 of 1 garment had no confirmed wear in this period.", value.periodSummary(query))
        rejects { value.periodSummary(query.copy(from = "2026-10-02")) }
        rejects { query.copy(from = "2026-02-30").validatePeriod() }; rejects { query.copy(from = query.to, to = query.from).validatePeriod() }
        rejects { value.copy(garments = 2).periodSummary(query) }; rejects { value.copy(outfitEvents = -1).periodSummary(query) }
    }
    @Test fun importRelaunchKeepsEachSourceAndIdentityAndBlocksDamagedOrOldOwnerReads() = runTest {
        val root = Files.createTempDirectory("retro-import").toFile()
        try {
            var owner = true
            val file = File(root, "drafts.json"); val drafts = WardrobeSavedDrafts(file) { owner }
            val first = "first normalized photo".toByteArray(); val second = "second normalized photo".toByteArray()
            drafts.addImport(first); drafts.addImport(second)
            val saved = drafts.imports
            assertNull(drafts.garment(null)); assertNotEquals(saved[0].entityID, saved[1].entityID)
            val restored = WardrobeSavedDrafts(file) { owner }
            assertEquals(saved.map { it.entityID }, restored.imports.map { it.entityID }); assertEquals(saved.map { it.importPhoto }, restored.imports.map { it.importPhoto })
            assertArrayEquals(first, restored.importBytes(saved[0].id)); restored.remove(saved[0].id)
            assertArrayEquals(second, restored.importBytes(saved[1].id))
            val source = File(root, "drafts/import-photos/${saved[1].importPhoto!!.id}.jpg"); val manifest = file.readBytes()
            source.writeBytes(ByteArray(second.size))
            try { restored.importBytes(saved[1].id); fail("Changed bytes must stay blocked") } catch (_: IllegalStateException) { }
            assertArrayEquals(manifest, file.readBytes()); owner = false
            rejects { restored.remove(saved[1].id) }; rejects { restored.addImport(first) }
            try { restored.importBytes(saved[1].id); fail("Old account cannot reopen import bytes") } catch (_: IllegalStateException) { }
        } finally { root.deleteRecursively() }
    }
    @Test fun acceptedPhotoRetriesKeepOneMediaIdentityAndLaterEditsBlockFinish() = runTest {
        val root = Files.createTempDirectory("retro-import").toFile()
        try {
            var owner = "A"
            val drafts = WardrobeSavedDrafts(File(root, "drafts.json")) { owner == "A" }; drafts.addImport("normalized photo".toByteArray())
            var entry = drafts.imports[0]
            var remote = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0].copy(id = entry.entityID, mediaIDs = emptyList())
            entry = entry.copy(garment = remote, garmentDraft = WardrobeGarmentDraft(remote)); drafts.put(entry)
            val engine = Engine(RetroApi("https://photo.test/api/v1", Transport { _, url, _, _, _ ->
                check(url.endsWith("garments_get")); 200 to ApiJson.encodeToString(WardrobeGarmentResult(remote))
            }), "A", { owner }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { owner == "A" }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "photos"), File(root, "cache"), engine, writes)
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", engine.cacheScope), writes, photos, drafts) { owner == "A" }
            store.attachImport(entry.id)
            entry = drafts.imports[0]
            val media = entry.importMediaID; val key = photos.batches[0].photos[0].prepareKey
            store.attachImport(entry.id)
            assertEquals(1, photos.batches.size); assertEquals(media, photos.batches[0].photos[0].id); assertEquals(key, photos.batches[0].photos[0].prepareKey)
            try { store.finishImport(entry.id); fail("Unacknowledged photo must stay visible") } catch (_: IllegalStateException) { }
            val restored = WardrobeSavedDrafts(File(root, "drafts.json")) { owner == "A" }
            assertEquals(media, restored.imports[0].importMediaID)
            val review = entry.copy(garment = remote, garmentDraft = WardrobeGarmentDraft(remote).copy(notes = "Later edits"))
            drafts.put(review); assertTrue(review.hasImportEdits())
            try { store.attachImport(entry.id); fail("Later edits need review") } catch (_: IllegalStateException) { }
            owner = "B"
            try { store.attachImport(entry.id); fail("Old account cannot attach") } catch (_: IllegalStateException) { }
            assertEquals(1, photos.batches.size); assertTrue(writes.items.isEmpty())
        } finally { root.deleteRecursively() }
    }
    @Test fun corruptImportManifestIsPreservedAndDoesNotPruneItsPhotos() {
        val root = Files.createTempDirectory("retro-import").toFile()
        try {
            val file = File(root, "drafts.json"); val drafts = WardrobeSavedDrafts(file) { true }; drafts.addImport("photo".toByteArray())
            val source = File(root, "drafts/import-photos/${drafts.imports[0].importPhoto!!.id}.jpg"); source.setLastModified(System.currentTimeMillis() - 172_800_000)
            file.writeText("broken manifest")
            val restored = WardrobeSavedDrafts(file) { true }
            assertNotNull(restored.problem); rejects { restored.addImport("other".toByteArray()) }
            assertEquals("broken manifest", file.readText()); assertTrue(source.exists())
        } finally { root.deleteRecursively() }
    }
    @Test fun submitReturnsFrozenCreateBeforeAnEagerDeliveryCallbackRemovesIt() {
        val root = Files.createTempDirectory("retro-import").toFile()
        try {
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", engine.cacheScope), writes = writes) { true }
            store.onEnqueued = { writes.remove(writes.items[0]) }
            val id = UUID.randomUUID().toString()
            val draft = WardrobeGarmentDraft(name = "Reviewed shirt")
            val accepted = store.submit("garments_create", id, draft.name, JsonObject(draft.fields() + ("id" to JsonPrimitive(id))))
            assertTrue(writes.items.isEmpty()); assertEquals(id, accepted.entity); assertEquals(draft.name, accepted.createFields()["name"]!!.jsonPrimitive.content)
        } finally { root.deleteRecursively() }
    }
    @Test fun choosingExistingRequiresFreshUnchangedItemAndNeverAbandonsAnAcceptedCreate() = runTest {
        val root = Files.createTempDirectory("retro-import").toFile()
        try {
            var owner = "A"; var originalExists = false; var unavailable = false
            val drafts = WardrobeSavedDrafts(File(root, "drafts.json")) { owner == "A" }; drafts.addImport("photo".toByteArray())
            val entry = drafts.imports[0]
            val candidate = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory")).items[0]
            var remote = candidate
            val engine = Engine(RetroApi("https://photo.test/api/v1", Transport { _, url, _, body, _ ->
                check(url.endsWith("garments_get"))
                val id = ApiJson.parseToJsonElement(checkNotNull(body)).jsonObject["id"]!!.jsonPrimitive.content
                if (unavailable) 503 to "{}"
                else if (id == entry.entityID && !originalExists) 404 to """{"error":{"code":"not_found","message":"Missing"}}"""
                else 200 to ApiJson.encodeToString(WardrobeGarmentResult(if (id == entry.entityID) remote.copy(id = entry.entityID) else remote))
            }), "A", { owner }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { owner == "A" }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "photos"), File(root, "cache"), engine, writes)
            val store = WardrobeStore(engine, WardrobeReadCache(root, "A", engine.cacheScope), writes, photos, drafts) { owner == "A" }
            originalExists = true
            try { store.useExistingImport(entry.id, candidate); fail("An accepted create cannot be abandoned") } catch (_: IllegalStateException) { }
            originalExists = false; remote = candidate.copy(version = candidate.version + 1)
            try { store.useExistingImport(entry.id, candidate); fail("A changed candidate needs review") } catch (_: IllegalStateException) { }
            remote = candidate; unavailable = true
            try { store.useExistingImport(entry.id, candidate); fail("Service errors are not not-found") } catch (_: IllegalStateException) { }
            unavailable = false
            assertEquals(entry.entityID, drafts.imports[0].entityID)
            store.useExistingImport(entry.id, candidate)
            assertEquals(candidate.id, drafts.imports[0].entityID); assertEquals(entry.importPhoto, drafts.imports[0].importPhoto)
            assertTrue(writes.items.isEmpty()); assertTrue(photos.batches.isEmpty())
            owner = "B"
            try { store.attachImport(entry.id); fail("Old account cannot attach") } catch (_: IllegalStateException) { }
            assertTrue(photos.batches.isEmpty())
        } finally { root.deleteRecursively() }
    }
}
