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

class WardrobePhotoTest {
    private fun garment() = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(javaClass.classLoader!!.getResource("inventory.json")!!.readText()).items[0]
    private fun rejects(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: Exception) { } }

    @Test fun photoDraftRelaunchRestoresOriginalChoiceAndAtomicallyMovesToQueue() = runTest {
        val root = Files.createTempDirectory("retro-photo-draft").toFile()
        try {
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            val id = UUID.randomUUID().toString()
            val original = "normalized original".toByteArray(); val chosen = "chosen cutout".toByteArray()
            val first = WardrobePreparedPhoto(original = original, chosen = chosen)
            val second = WardrobePreparedPhoto(original = "second".toByteArray(), chosen = "second".toByteArray())
            photos.saveDraft(id, garment(), emptyList(), listOf(second, first))
            val stored = photos.drafts[0]
            assertEquals(stored.photos[0].original.id, stored.photos[0].chosen.id)
            stored.sources.forEach { File(folder, "${it.id}.jpg").setLastModified(System.currentTimeMillis() - 172_800_000) }
            val restored = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            val loaded = restored.loadDraft(id)
            assertEquals(listOf(second.id, first.id), loaded.map { it.id })
            assertArrayEquals(original, loaded[1].original); assertArrayEquals(chosen, loaded[1].chosen)
            restored.saveDraft(id, garment(), emptyList(), loaded)
            assertEquals(stored.photos.map { it.chosen.id }, restored.drafts[0].photos.map { it.chosen.id })
            restored.acceptDraft(id)
            assertTrue(restored.drafts.isEmpty()); assertEquals(stored.photos.map { it.chosen.id }, restored.batches[0].photos.map { it.id })
            assertFalse(File(folder, "${stored.photos[1].original.id}.jpg").exists())
            rejects { restored.acceptDraft(id) }
            val relaunched = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            assertTrue(relaunched.drafts.isEmpty()); assertEquals(1, relaunched.batches.size)
            assertEquals(restored.batches[0].photos.map { it.prepareKey }, relaunched.batches[0].photos.map { it.prepareKey })
        } finally { root.deleteRecursively() }
    }
    @Test fun failedPhotoDraftHandoffPreservesDraftAndBothSourceFiles() {
        val root = Files.createTempDirectory("retro-photo-draft").toFile()
        try {
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources"); val file = File(folder, "jobs.json"); val backup = File(root, "manifest-backup.json")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            val id = UUID.randomUUID().toString()
            photos.saveDraft(id, garment(), emptyList(), listOf(WardrobePreparedPhoto(original = "original".toByteArray(), chosen = "cutout".toByteArray())))
            val sources = photos.drafts[0].sources
            Files.move(file.toPath(), backup.toPath()); file.mkdir(); File(file, "child").writeText("write obstruction")
            rejects { photos.acceptDraft(id) }
            assertEquals(1, photos.drafts.size); assertTrue(photos.batches.isEmpty())
            sources.forEach { assertTrue(File(folder, "${it.id}.jpg").exists()) }
            file.deleteRecursively(); Files.move(backup.toPath(), file.toPath())
            val restored = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            assertEquals(1, restored.drafts.size); assertTrue(restored.batches.isEmpty())
        } finally { root.deleteRecursively() }
    }

    @Test fun damagedPhotoDraftCannotBeAcceptedAndOwnerCannotResumeIt() = runTest {
        val root = Files.createTempDirectory("retro-photo-draft").toFile()
        try {
            var owner = "A"
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { owner }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { owner == "A" }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            val id = UUID.randomUUID().toString()
            photos.saveDraft(id, garment(), emptyList(), listOf(WardrobePreparedPhoto(original = "good".toByteArray(), chosen = "good".toByteArray())))
            val manifest = File(folder, "jobs.json").readBytes()
            val source = File(folder, "${photos.drafts[0].photos[0].chosen.id}.jpg")
            source.writeText("evil")
            rejects { photos.acceptDraft(id) }
            try { photos.loadDraft(id); fail("Changed bytes must not load") } catch (_: IllegalStateException) { }
            assertEquals(1, photos.drafts.size); assertTrue(photos.batches.isEmpty()); assertTrue(writes.items.isEmpty())
            assertArrayEquals(manifest, File(folder, "jobs.json").readBytes())
            source.writeText("good"); owner = "B"
            try { photos.loadDraft(id); fail("An old owner must not resume a draft") } catch (_: IllegalStateException) { }
            rejects { photos.discardDraft(id) }; rejects { photos.acceptDraft(id) }
        } finally { root.deleteRecursively() }
    }
    @Test fun referenceOnlyDraftChecksLiveBaselineAndQueuesOnlyReviewedReferences() = runTest {
        val root = Files.createTempDirectory("retro-photo-draft").toFile()
        try {
            val original = garment(); val live = original.copy(mediaIDs = emptyList(), version = original.version + 1)
            var calls = 0
            val engine = Engine(RetroApi("https://photo.test/api/v1", Transport { _, url, _, _, _ ->
                calls++; assertTrue(url.endsWith("garments_get")); 200 to ApiJson.encodeToString(WardrobeGarmentResult(live))
            }), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, writes)
            val id = UUID.randomUUID().toString()
            photos.saveDraft(id, original, emptyList(), emptyList()); photos.acceptDraft(id)
            photos.step()
            assertTrue(photos.batches[0].blocked); assertTrue(writes.items.isEmpty())
            photos.review(id, live, emptyList()); photos.step()
            assertEquals(2, calls); assertEquals(1, writes.items.size)
            assertEquals(live.version, writes.items[0].body["expected_version"]!!.jsonPrimitive.long)
            assertEquals(setOf("media_ids"), writes.items[0].body["patch"]!!.jsonObject.keys)
            assertEquals(JsonArray(emptyList()), writes.items[0].body["patch"]!!.jsonObject["media_ids"])
        } finally { root.deleteRecursively() }
    }
    @Test fun legacyPhotoJobsMigrateAndUnknownManifestVersionPreservesSources() {
        val root = Files.createTempDirectory("retro-photo-draft").toFile()
        try {
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources"); val file = File(folder, "jobs.json")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            photos.stage(garment(), emptyList(), listOf("bytes".toByteArray()))
            file.writeText(ApiJson.encodeToString(photos.batches))
            val legacy = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            assertNull(legacy.problem); assertEquals(1, legacy.batches.size)
            legacy.discard(legacy.batches[0].id)
            assertEquals(1, ApiJson.decodeFromString<WardrobePhotoManifest>(file.readText()).version)
            val orphan = File(folder, "33333333-3333-4333-8333-333333333333.jpg").apply { writeText("preserve"); setLastModified(System.currentTimeMillis() - 172_800_000) }
            val unknown = ApiJson.encodeToString(WardrobePhotoManifest(2, emptyList(), emptyList()))
            file.writeText(unknown)
            assertNotNull(WardrobePhotos(folder, File(root, "cache"), engine, writes).problem)
            assertTrue(orphan.exists()); assertEquals(unknown, file.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun wireMediaUsesLongVersionsAndOnlyKnownOriginPaths() {
        val media = ApiJson.decodeFromString<WardrobeMediaResult>(javaClass.classLoader!!.getResource("media.json")!!.readText()).media
        assertEquals(9007199254740993L, media.version)
        assertEquals("/media/${media.id}/content?variant=thumbnail", WardrobeMediaPath.path(media.id, "thumbnail"))
        assertNull(WardrobeMediaPath.path("https://evil.test/photo"))
        assertNull(WardrobeMediaPath.path("../private"))
        assertNull(WardrobeMediaPath.path(media.id, "source&next=https://evil.test"))
        assertEquals(1, PhotoPreparation.sample(320, 640, 2048))
        assertEquals(4, PhotoPreparation.sample(6000, 4000, 2048))
    }

    @Test fun lostAttachmentRelaunchReplaysVersionAndDeletesBytesOnlyAfterAck() = runTest {
        val root = Files.createTempDirectory("retro-photo").toFile()
        try {
            val garment = garment()
            val bytes = "immutable JPEG bytes in a fake transport".toByteArray()
            var local: WardrobeLocalPhoto? = null
            var state = "awaiting_upload"
            var firstBody: String? = null
            var replayBody: String? = null
            var attachments = 0
            var uploadCalls = 0
            fun media(): WardrobeMediaResult {
                val p = checkNotNull(local)
                return WardrobeMediaResult(WardrobeMedia(p.id, 2, p.checksum, bytes.size.toLong(), "image/jpeg", state,
                    uploadPath = "https://evil.test/never-used"))
            }
            val transport = Transport { _, url, token, body, _ ->
                assertEquals("A-token", token)
                when {
                    url.endsWith("garments_update") -> {
                        attachments++
                        if (attachments == 1) { firstBody = body; 503 to "" }
                        else { replayBody = body; 200 to ApiJson.encodeToString(WardrobeGarmentResult(garment)) }
                    }
                    url.endsWith("garments_get") -> 200 to ApiJson.encodeToString(WardrobeGarmentResult(garment))
                    else -> 200 to ApiJson.encodeToString(media())
                }
            }
            val binary = BinaryTransport { method, url, token, body ->
                assertEquals("PUT", method); assertEquals("A-token", token)
                assertEquals("https://photo.test/retro/api/v1/media/${local!!.id}/content", url)
                assertArrayEquals(bytes, body)
                uploadCalls++; state = "processing"
                200 to ApiJson.encodeToString(media()).toByteArray()
            }
            val engine = Engine(RetroApi("https://photo.test/retro/api/v1", transport, binary), "A", { "A" }) { "A-token" }
            fun writes() = WardrobeWrites(File(root, "writes.json"), { true }, { op, body -> engine.call<JsonObject, WardrobeGarmentResult>(op, body).map { true } })
            val firstWrites = writes()
            val photos = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, firstWrites)
            photos.stage(garment, garment.mediaIDs, listOf(bytes))
            local = photos.batches[0].photos[0]
            val source = File(root, "sources/${local!!.id}.jpg")
            photos.step()
            assertEquals(1, uploadCalls)
            assertTrue(source.exists()); assertNull(photos.batches[0].attachment)
            state = "ready"
            photos.step()
            val original = photos.batches[0].attachment!!
            assertEquals(garment.version, original["expected_version"]!!.jsonPrimitive.long)
            assertFalse(firstWrites.drain())
            assertEquals(original, ApiJson.parseToJsonElement(firstBody!!))
            rejects { photos.discard(photos.batches[0].id) }
            assertTrue(source.exists())
            val restoredWrites = writes()
            val restored = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, restoredWrites)
            restored.step()
            assertTrue(restoredWrites.drain(force = true))
            restored.reconcile()
            assertEquals(firstBody, replayBody)
            assertTrue(restored.batches.isEmpty()); assertFalse(source.exists())
            assertEquals(1, uploadCalls)
        } finally { root.deleteRecursively() }
    }

    @Test fun changedReferencesNeedReviewAndReuseReadyMedia() = runTest {
        val root = Files.createTempDirectory("retro-photo").toFile()
        try {
            val garment = garment()
            val current = garment.copy(mediaIDs = emptyList(), version = garment.version + 1)
            val bytes = "saved image".toByteArray()
            var local: WardrobeLocalPhoto? = null
            val transport = Transport { _, url, _, _, _ ->
                if (url.endsWith("garments_get")) 200 to ApiJson.encodeToString(WardrobeGarmentResult(current))
                else {
                    val p = checkNotNull(local)
                    200 to ApiJson.encodeToString(WardrobeMediaResult(WardrobeMedia(p.id, 3, p.checksum, bytes.size.toLong(), "image/jpeg", "ready", uploadPath = "unused")))
                }
            }
            val engine = Engine(RetroApi("https://photo.test/api/v1", transport), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, writes)
            photos.stage(garment, garment.mediaIDs, listOf(bytes))
            local = photos.batches[0].photos[0]
            photos.step()
            assertTrue(photos.batches[0].blocked); assertTrue(writes.items.isEmpty())
            photos.review(photos.batches[0].id, current, emptyList())
            photos.step()
            assertEquals(1, writes.items.size)
            assertEquals(local!!.id, photos.batches[0].photos[0].id)
            assertEquals(current.version, writes.items[0].body["expected_version"]!!.jsonPrimitive.long)
        } finally { root.deleteRecursively() }
    }

    @Test fun damagedSourcesAndUnreadableJobsArePreservedRatherThanSent() = runTest {
        val root = Files.createTempDirectory("retro-photo").toFile()
        try {
            var calls = 0
            val engine = Engine(RetroApi("https://photo.test/api/v1", Transport { _, _, _, _, _ -> calls++; 500 to "" }), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            photos.stage(garment(), emptyList(), listOf("original".toByteArray()))
            val local = photos.batches[0].photos[0]
            File(folder, "${local.id}.jpg").writeText("damaged")
            photos.step()
            assertEquals(0, calls)
            assertNotNull(photos.batches[0].photos[0].problem)
            val file = File(folder, "jobs.json").apply { writeText("broken") }
            val restored = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            assertNotNull(restored.problem)
            rejects { restored.stage(garment(), emptyList(), listOf("new".toByteArray())) }
            assertEquals("broken", file.readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun oldStagingOrphansArePrunedOnlyWithReadableIntentAndQueuedBytesStay() {
        val root = Files.createTempDirectory("retro-orphans").toFile()
        try {
            val engine = Engine(RetroApi("https://photo.test/api/v1"), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val folder = File(root, "sources")
            val photos = WardrobePhotos(folder, File(root, "cache"), engine, writes)
            photos.stage(garment(), emptyList(), listOf("bytes".toByteArray()))
            val queued = File(folder, "${photos.batches[0].photos[0].id}.jpg")
            val orphan = File(folder, "33333333-3333-4333-8333-333333333333.jpg").apply { writeText("orphan") }
            listOf(queued, orphan).forEach { it.setLastModified(System.currentTimeMillis() - 172_800_000) }
            WardrobePhotos(folder, File(root, "cache"), engine, writes)
            assertTrue(queued.exists()); assertFalse(orphan.exists())
            orphan.writeText("orphan"); orphan.setLastModified(System.currentTimeMillis() - 172_800_000)
            File(folder, "jobs.json").writeText("damaged")
            assertNotNull(WardrobePhotos(folder, File(root, "cache"), engine, writes).problem)
            assertTrue(orphan.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun explicitPhotoRetryReplacesCachedBytes() = runTest {
        val root = Files.createTempDirectory("retro-photo").toFile()
        try {
            val id = "33333333-3333-4333-8333-333333333333"
            val file = File(root, "cache/$id-thumbnail.jpg")
            file.parentFile!!.mkdirs(); file.writeText("unreadable cached bytes")
            var requests = 0
            val fresh = "fresh photo bytes from fake transport".toByteArray()
            val engine = Engine(RetroApi("https://photo.test/api/v1", binary = BinaryTransport { _, _, _, _ -> requests++; 200 to fresh }), "A", { "A" }) { "token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { true }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, writes)
            assertArrayEquals(file.readBytes(), (photos.image(id, "thumbnail") as Api.Ok<ByteArray>).value)
            assertEquals(0, requests)
            assertArrayEquals(fresh, (photos.image(id, "thumbnail", reload = true) as Api.Ok<ByteArray>).value)
            assertEquals(1, requests)
            assertArrayEquals(fresh, file.readBytes())
        } finally { root.deleteRecursively() }
    }

    @Test fun lateBinaryResponsesCannotPopulateAnotherAccountCache() = runTest {
        val root = Files.createTempDirectory("retro-photo").toFile()
        try {
            var owner = "A"
            val id = "33333333-3333-4333-8333-333333333333"
            val engine = Engine(RetroApi("https://photo.test/api/v1", binary = BinaryTransport { _, _, _, _ -> owner = "B"; 200 to "image".toByteArray() }), "A", { owner }) { "A-token" }
            val writes = WardrobeWrites(File(root, "writes.json"), { owner == "A" }, { _, _ -> Api.Ok(true) })
            val photos = WardrobePhotos(File(root, "sources"), File(root, "cache"), engine, writes)
            assertEquals(Api.Unauthorized, photos.image(id, "thumbnail"))
            assertFalse(File(root, "cache/$id-thumbnail.jpg").exists())
        } finally { root.deleteRecursively() }
    }
}
