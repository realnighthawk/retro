package org.nighthawklabs.retro.data

import androidx.compose.runtime.*
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.nighthawklabs.retro.net.*
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID

@Serializable data class WardrobeLocalPhoto(val id: String, val checksum: String, val size: Int, val prepareKey: String,
    val media: WardrobeMedia? = null, val retryBody: JsonObject? = null, val problem: String? = null)
@Serializable data class WardrobePhotoBatch(val id: String, val garmentID: String, val title: String, val baseline: List<String>,
    val retained: List<String>, val photos: List<WardrobeLocalPhoto>, val attachment: JsonObject? = null,
    val attachmentKey: String? = null, val blocked: Boolean = false, val problem: String? = null) {
    val target: List<String> get() = retained + photos.map { it.id }
}

class WardrobePhotos(private val folder: File, private val cache: File, private val engine: Engine, private val writes: WardrobeWrites) {
    var batches by mutableStateOf<List<WardrobePhotoBatch>>(emptyList())
        private set
    var drafts by mutableStateOf<List<WardrobePhotoDraft>>(emptyList())
        private set
    var problem by mutableStateOf<String?>(null)
        private set
    var running by mutableStateOf(false)
        private set
    var foreground by mutableStateOf(true)
    private val canRun: Boolean get() = engine.isCurrentOwner && foreground
    init {
        try {
            val file = File(folder, "jobs.json")
            if (file.exists()) {
                check(file.length() <= 4L * 1024 * 1024) { "Photo manifest exceeds its limit." }
                val text = file.readText()
                val manifest = if (text.trimStart().startsWith("[")) WardrobePhotoManifest(1, ApiJson.decodeFromString(text), emptyList()) else ApiJson.decodeFromString<WardrobePhotoManifest>(text)
                val loaded = manifest.batches
                check(manifest.version == 1 && manifest.drafts.size <= 20 && manifest.drafts.map { it.id }.distinct().size == manifest.drafts.size && manifest.drafts.map { it.garment.id }.distinct().size == manifest.drafts.size && manifest.drafts.all(::validDraft) && draftSize(manifest.drafts) <= 256L * 1024 * 1024) { "Invalid photo drafts." }
                check(loaded.size <= 20 && loaded.map { it.id }.distinct().size == loaded.size && loaded.none { batch -> manifest.drafts.any { it.garment.id == batch.garmentID } } && loaded.all { batch ->
                    runCatching { UUID.fromString(batch.id) }.isSuccess && runCatching { UUID.fromString(batch.garmentID) }.isSuccess &&
                        batch.photos.all { WardrobeMediaPath.path(it.id) != null } && (batch.attachment == null) == (batch.attachmentKey == null) &&
                        (batch.attachment?.let { input -> input["id"]?.jsonPrimitive?.content == batch.garmentID && input["idempotency_key"]?.jsonPrimitive?.content == batch.attachmentKey &&
                            input["patch"]?.jsonObject?.let { it.size == 1 && it["media_ids"] == JsonArray(batch.target.map(::JsonPrimitive)) } == true } ?: true)
                }) { "Invalid photo jobs." }
                batches = loaded
                drafts = manifest.drafts
            }
            pruneUnqueuedSources()
        } catch (e: Exception) { problem = "Pending photos could not be opened. Keep this app's data and reopen Retro. ${e.localizedMessage}" }
    }
    fun contains(garmentID: String) = batches.any { it.garmentID == garmentID }

    suspend fun currentGarment(id: String): Api<WardrobeGarmentResult> = engine.call("garments_get", WardrobeID(id))

    fun review(id: String, current: WardrobeGarment, retained: List<String>) {
        check(engine.isCurrentOwner && problem == null && !running) { "Wait for photo delivery to stop first." }
        val batch = batches.first { it.id == id }
        require(batch.garmentID == current.id && current.archivedAt == null && batch.photos.all { it.media?.state == "ready" } && retained.size + batch.photos.size <= 10 && retained.distinct().size == retained.size && retained.all { id -> id in current.mediaIDs && batch.photos.none { it.id == id } }) { "Review an active garment and up to 10 ready photos first." }
        val pending = writes.items.find { it.entity == batch.garmentID }
        if (pending != null) { check(pending.id == batch.attachmentKey && pending.rejected) { "Reconcile this garment's pending save before replacing an attachment." }; writes.remove(pending) }
        else check(batch.attachmentKey == null || batch.blocked) { "Retry to reconcile this attachment before replacing it." }
        commit(batches.map { if (it.id == id) it.copy(baseline = current.mediaIDs, retained = retained, attachment = null, attachmentKey = null, blocked = false, problem = null) else it })
    }

    fun stage(garment: WardrobeGarment, retained: List<String>, images: List<ByteArray>) {
        check(engine.isCurrentOwner && problem == null && garment.archivedAt == null && !contains(garment.id) && drafts.none { it.garment.id == garment.id } && !writes.contains(garment.id)) { problem ?: "Resolve this garment's pending saves/photos first." }
        require(images.isNotEmpty() && retained.size + images.size <= 10 && retained.distinct().size == retained.size && retained.all { it in garment.mediaIDs } && batches.size < 20) { "Choose up to 10 photos per garment and resolve older photo jobs first." }
        val photos = images.map { bytes ->
            require(bytes.isNotEmpty() && bytes.size <= 12 * 1024 * 1024) { "Each photo must be at most 12 MiB." }
            val id = UUID.randomUUID().toString()
            atomic(source(id), bytes)
            WardrobeLocalPhoto(id, hash(bytes), bytes.size, UUID.randomUUID().toString())
        }
        // Source files precede durable intent. Interrupted staging can orphan bytes, never queue a missing photo.
        commit(batches + WardrobePhotoBatch(UUID.randomUUID().toString(), garment.id, garment.name, garment.mediaIDs, retained, photos))
    }
    fun saveDraft(id: String, garment: WardrobeGarment, retained: List<String>, photos: List<WardrobePreparedPhoto>) {
        check(engine.isCurrentOwner && problem == null && !contains(garment.id)) { problem ?: "Resolve the accepted photo batch first." }
        require(WardrobeMediaPath.path(id) != null && garment.archivedAt == null && retained.size + photos.size <= 10 && retained.distinct().size == retained.size && retained.all { it in garment.mediaIDs } && photos.map { it.id }.distinct().size == photos.size) { "Review up to 10 different photos first." }
        check(drafts.none { it.garment.id == garment.id && it.id != id }) { "Resume this garment's existing photo draft first." }
        val newSize = photos.sumOf { it.original.size.toLong() + if (it.original.contentEquals(it.chosen)) 0L else it.chosen.size.toLong() }
        require(drafts.count { it.id != id } < 20 && draftSize(drafts.filterNot { it.id == id }) + newSize <= 256L * 1024 * 1024 && photos.all { it.original.isNotEmpty() && it.chosen.isNotEmpty() && it.original.size <= 12 * 1024 * 1024 && it.chosen.size <= 12 * 1024 * 1024 }) { "Photo draft storage is full or a photo is too large. Resolve older drafts first." }
        val before = sourceIDs
        val previous = drafts.find { it.id == id }
        check(previous == null || (previous.garment.id == garment.id && previous.garment.mediaIDs == garment.mediaIDs)) { "The photo draft baseline changed. Resume the stored draft first." }
        fun store(bytes: ByteArray, old: WardrobePhotoBytes?): WardrobePhotoBytes {
            require(bytes.isNotEmpty() && bytes.size <= 12 * 1024 * 1024) { "Each normalized photo must be at most 12 MiB." }
            val checksum = hash(bytes)
            if (old != null && old.checksum == checksum && old.size == bytes.size) return old
            val file = WardrobePhotoBytes(UUID.randomUUID().toString(), checksum, bytes.size)
            atomic(source(file.id), bytes); return file
        }
        val saved = photos.map { photo ->
            val old = previous?.photos?.find { it.id == photo.id }
            val original = store(photo.original, old?.original)
            val chosen = store(photo.chosen, if (photo.chosen.contentEquals(photo.original)) original else old?.chosen)
            WardrobePhotoEdit(photo.id, original, chosen)
        }
        val value = WardrobePhotoDraft(id, garment, retained, saved, System.currentTimeMillis())
        val next = drafts.filterNot { it.id == id } + value
        require(validDraft(value) && next.size <= 20 && draftSize(next) <= 256L * 1024 * 1024) { "Photo drafts are full (20 drafts / 256 MiB). Resolve older drafts first." }
        commitState(batches, next); release(before)
    }
    suspend fun loadDraft(id: String): List<WardrobePreparedPhoto> {
        check(engine.isCurrentOwner && problem == null) { problem ?: "Photo draft is unavailable." }
        val value = checkNotNull(drafts.find { it.id == id }) { "Photo draft is unavailable." }
        val loaded = withContext(Dispatchers.IO) {
            value.photos.map { photo ->
                currentCoroutineContext().ensureActive()
                val original = readBytes(photo.original)
                val chosen = if (photo.original.id == photo.chosen.id) original else readBytes(photo.chosen)
                WardrobePreparedPhoto(photo.id, original, chosen)
            }
        }
        currentCoroutineContext().ensureActive()
        check(engine.isCurrentOwner && drafts.find { it.id == id } == value) { "Photo draft changed. Reopen it to continue." }
        return loaded
    }
    private fun readBytes(file: WardrobePhotoBytes): ByteArray {
        require(WardrobeMediaPath.path(file.id) != null && file.size in 1..12 * 1024 * 1024 && source(file.id).length() == file.size.toLong()) { "A draft photo is missing or damaged. Keep app data and restore the file, or discard this draft." }
        val bytes = source(file.id).readBytes()
        check(bytes.size == file.size && hash(bytes) == file.checksum) { "A draft photo has changed. It will not be uploaded." }
        return bytes
    }
    fun acceptDraft(id: String) {
        check(engine.isCurrentOwner && problem == null && !running) { problem ?: "Wait for this garment's pending work before saving photos." }
        val value = checkNotNull(drafts.find { it.id == id }) { "Photo draft is unavailable." }
        check(!contains(value.garment.id) && !writes.contains(value.garment.id) && batches.size < 20 && validDraft(value)) { "Wait for this garment's pending work before saving photos." }
        value.photos.forEach { readBytes(it.chosen) }
        val batch = WardrobePhotoBatch(value.id, value.garment.id, value.garment.name, value.garment.mediaIDs, value.retained,
            value.photos.map { WardrobeLocalPhoto(it.chosen.id, it.chosen.checksum, it.chosen.size, UUID.randomUUID().toString()) })
        val before = sourceIDs
        commitState(batches + batch, drafts.filterNot { it.id == id }); release(before)
    }
    fun discardDraft(id: String) {
        check(engine.isCurrentOwner && problem == null) { problem ?: "Sign in before discarding a photo draft." }
        if (drafts.none { it.id == id }) return
        val before = sourceIDs
        commitState(batches, drafts.filterNot { it.id == id }); release(before)
    }
    suspend fun step() {
        if (!canRun || problem != null || running) return
        running = true
        try {
            for (batchID in batches.map { it.id }) {
                currentCoroutineContext().ensureActive()
                if (!canRun) return
                var batch = batches.find { it.id == batchID } ?: continue
                val key = batch.attachmentKey
                if (key != null) {
                    if (key in writes.acknowledgedIDs) { finish(batch); continue }
                    val pending = writes.items.find { it.id == key }
                    if (pending?.rejected == true) { update(batch.copy(blocked = true, problem = pending.problem)); continue }
                    val attachment = batch.attachment
                    if (!batch.blocked && !writes.contains(batch.garmentID) && attachment != null) {
                        try { writes.enqueuePrepared(key, "garments_update", batch.garmentID, "Photos · ${batch.title}", attachment) }
                        catch (e: Exception) { update(batch.copy(problem = e.localizedMessage)) }
                    }
                    continue
                }
                for (index in batch.photos.indices) {
                    currentCoroutineContext().ensureActive()
                    if (!canRun) return
                    var photo = batch.photos[index].copy(problem = null)
                    var pause = false
                    try {
                        val bytes = withContext(Dispatchers.IO) { check(photo.size in 1..12 * 1024 * 1024 && source(photo.id).length() == photo.size.toLong()) { "Stored photo size has changed. It will not be uploaded." }; source(photo.id).readBytes() }
                        check(bytes.size == photo.size && hash(bytes) == photo.checksum) { "Stored photo has changed. It will not be uploaded." }
                        if (photo.media == null) {
                            val input = buildJsonObject { put("id", photo.id); put("idempotency_key", photo.prepareKey); put("checksum", photo.checksum); put("size_bytes", photo.size); put("mime_type", "image/jpeg") }
                            val result = engine.call<JsonObject, WardrobeMediaResult>("media_prepare", input)
                            currentCoroutineContext().ensureActive(); if (!canRun) return
                            pause = result.pausesPhotoDelivery
                            check(result is Api.Ok) { result.problem ?: "Could not reserve photo." }
                            validate(result.value.media, photo)
                            photo = photo.copy(media = result.value.media)
                            batch = batch.copy(photos = batch.photos.toMutableList().also { it[index] = photo })
                            if (!update(batch)) return
                        }
                        val result = engine.call<WardrobeID, WardrobeMediaResult>("media_get", WardrobeID(photo.id))
                        currentCoroutineContext().ensureActive(); if (!canRun) return
                        pause = result.pausesPhotoDelivery
                        check(result is Api.Ok) { result.problem ?: "Could not check photo." }
                        val media = result.value.media
                        validate(media, photo); photo = photo.copy(media = media)
                        val retry = photo.retryBody
                        if (retry != null) {
                            val result = engine.call<JsonObject, WardrobeMediaResult>("media_retry", retry)
                            currentCoroutineContext().ensureActive(); if (!canRun) return
                            pause = result.pausesPhotoDelivery
                            if (result is Api.Failed && result.code in setOf("conflict", "invalid_input", "not_found")) photo = photo.copy(retryBody = null)
                            check(result is Api.Ok) { result.problem ?: "Processing retry was rejected. Refresh before requesting another retry." }
                            validate(result.value.media, photo)
                            photo = photo.copy(retryBody = null, media = result.value.media)
                        } else if (media.state == "awaiting_upload") {
                            val result = engine.uploadPhoto(photo.id, bytes)
                            currentCoroutineContext().ensureActive(); if (!canRun) return
                            pause = result.pausesPhotoDelivery
                            check(result is Api.Ok) { result.problem ?: "Could not upload photo." }
                            validate(result.value.media, photo); photo = photo.copy(media = result.value.media)
                        } else if (media.state == "failed") photo = photo.copy(problem = media.error ?: "Processing failed. Retry processing or stop attaching this batch.")
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) { photo = photo.copy(problem = e.localizedMessage ?: "Photo delivery failed.") }
                    batch = batch.copy(photos = batch.photos.toMutableList().also { it[index] = photo })
                    if (!update(batch) || pause) return
                }
                if (batch.photos.any { it.media?.state != "ready" || it.retryBody != null } || writes.contains(batch.garmentID) || batch.blocked) continue
                val result = engine.call<WardrobeID, WardrobeGarmentResult>("garments_get", WardrobeID(batch.garmentID))
                currentCoroutineContext().ensureActive(); if (!canRun) return
                if (result is Api.Ok && result.value.garment.archivedAt == null && result.value.garment.mediaIDs == batch.baseline) {
                    if (writes.contains(batch.garmentID)) continue
                    val key = UUID.randomUUID().toString()
                    val body = JsonObject(WardrobeDraftValidation.edit(batch.garmentID, result.value.garment.version) + mapOf(
                        "idempotency_key" to JsonPrimitive(key), "patch" to buildJsonObject { put("media_ids", JsonArray(batch.target.map(::JsonPrimitive))) }))
                    batch = batch.copy(attachment = body, attachmentKey = key, problem = null)
                    if (!update(batch)) return
                    try { writes.enqueuePrepared(key, "garments_update", batch.garmentID, "Photos · ${batch.title}", body) }
                    catch (e: Exception) { update(batch.copy(problem = e.localizedMessage)) }
                } else update(batch.copy(blocked = result is Api.Ok, problem = result.problem ?: "The garment's photos or archive state changed. Review it before attaching these photos."))
            }
        } finally { running = false }
    }
    fun reconcile() {
        if (!engine.isCurrentOwner || problem != null || running) return
        batches.filter { it.attachmentKey in writes.acknowledgedIDs }.forEach(::finish)
    }
    fun retryProcessing(batchID: String, photoID: String) {
        check(engine.isCurrentOwner && !running && problem == null) { "Refresh this photo before retrying processing." }
        val batch = batches.first { it.id == batchID }
        val photo = batch.photos.first { it.id == photoID }
        val media = checkNotNull(photo.media) { "Refresh this photo before retrying processing." }
        check(media.state == "failed") { "Refresh this photo before retrying processing." }
        if (photo.retryBody == null) {
            val body = JsonObject(WardrobeDraftValidation.edit(photo.id, media.version) + ("idempotency_key" to JsonPrimitive(UUID.randomUUID().toString())))
            commit(batches.map { if (it.id == batchID) it.copy(photos = it.photos.map { p -> if (p.id == photoID) p.copy(retryBody = body) else p }) else it })
        }
    }
    fun discard(id: String) {
        check(engine.isCurrentOwner && !running) { "Wait for photo delivery to stop first." }
        val batch = batches.first { it.id == id }
        batch.attachmentKey?.let { key ->
            val pending = writes.items.find { it.id == key }
            if (pending != null) { check(pending.rejected) { "Reconcile the attachment in Pending saves before discarding it." }; writes.remove(pending) }
            else check(batch.blocked) { "Retry to reconcile this attachment before discarding it." }
        }
        val before = sourceIDs
        commit(batches.filterNot { it.id == id }); release(before)
    }
    suspend fun image(id: String, variant: String, reload: Boolean = false): Api<ByteArray> {
        if (!engine.isCurrentOwner || WardrobeMediaPath.path(id, variant) == null) return Api.Unauthorized
        val file = File(cache, "$id-$variant.jpg")
        val cached = withContext(Dispatchers.IO) { runCatching { if (!reload && file.length() in 1..12L * 1024 * 1024) file.readBytes() else null }.getOrNull() }
        currentCoroutineContext().ensureActive()
        if (!engine.isCurrentOwner) return Api.Unauthorized
        if (cached != null && cached.isNotEmpty() && cached.size <= 12 * 1024 * 1024) return Api.Ok(cached)
        val result = engine.photo(id, variant)
        currentCoroutineContext().ensureActive()
        if (!engine.isCurrentOwner) return Api.Unauthorized
        if (result is Api.Ok) withContext(Dispatchers.IO) {
            if (engine.isCurrentOwner) runCatching { atomic(file, result.value); trimCache() }
        }
        return if (engine.isCurrentOwner) result else Api.Unauthorized
    }
    private fun validate(media: WardrobeMedia, photo: WardrobeLocalPhoto) {
        check(media.id == photo.id && media.checksum == photo.checksum && media.sizeBytes == photo.size.toLong() && media.mimeType == "image/jpeg" && media.state in listOf("awaiting_upload", "processing", "ready", "failed")) { "Photo reservation does not match saved bytes." }
    }
    private fun source(id: String) = File(folder, "$id.jpg")
    private fun pruneUnqueuedSources() {
        val retained = sourceIDs
        // A valid manifest owns queued bytes; allow a day before removing interrupted staging leftovers.
        folder.listFiles().orEmpty().filter { it.extension == "jpg" && WardrobeMediaPath.path(it.nameWithoutExtension) != null && it.nameWithoutExtension.lowercase() !in retained && it.lastModified() < System.currentTimeMillis() - 86_400_000 }.forEach { it.delete() }
    }
    private fun commit(next: List<WardrobePhotoBatch>) = commitState(next, drafts)
    private fun commitState(next: List<WardrobePhotoBatch>, nextDrafts: List<WardrobePhotoDraft>) {
        val bytes = ApiJson.encodeToString(WardrobePhotoManifest(1, next, nextDrafts)).toByteArray()
        require(bytes.size <= 4 * 1024 * 1024) { "Photo manifest is full. Resolve older work first." }
        atomic(File(folder, "jobs.json"), bytes); batches = next; drafts = nextDrafts
    }
    private val sourceIDs: Set<String> get() = (batches.flatMap { it.photos.map { p -> p.id.lowercase() } } + drafts.flatMap { it.sources.map { p -> p.id.lowercase() } }).toSet()
    private fun release(before: Set<String>) { (before - sourceIDs).forEach { source(it).delete() } }
    private fun draftSize(values: List<WardrobePhotoDraft>) = values.flatMap { it.sources }.distinctBy { it.id }.sumOf { it.size.toLong() }
    private fun validDraft(value: WardrobePhotoDraft) = WardrobeMediaPath.path(value.id) != null && WardrobeMediaPath.path(value.garment.id) != null && value.garment.archivedAt == null &&
        value.retained.size + value.photos.size <= 10 && value.retained.distinct().size == value.retained.size && value.retained.all { it in value.garment.mediaIDs } &&
        value.photos.map { it.id }.distinct().size == value.photos.size && value.photos.map { it.chosen.id }.distinct().size == value.photos.size && value.photos.none { it.chosen.id in value.retained } && value.photos.all { WardrobeMediaPath.path(it.id) != null } &&
        value.sources.all { WardrobeMediaPath.path(it.id) != null && it.size in 1..12 * 1024 * 1024 && it.checksum.length == 64 && it.checksum.all { ch -> ch in "0123456789abcdef" } }
    private fun update(batch: WardrobePhotoBatch): Boolean = try { commit(batches.map { if (it.id == batch.id) batch else it }); true }
        catch (e: Exception) { problem = "Pending photos could not be stored. Reopen Retro to retry. ${e.localizedMessage}"; false }
    private fun finish(batch: WardrobePhotoBatch) {
        try { val before = sourceIDs; commit(batches.filterNot { it.id == batch.id }); release(before) }
        catch (e: Exception) { problem = "The attachment is acknowledged, but local cleanup failed. Reopen Retro to reconcile. ${e.localizedMessage}" }
    }
    private fun trimCache() {
        val files = cache.listFiles().orEmpty()
        var total = files.sumOf { it.length() }
        files.sortedBy { it.lastModified() }.forEach { if (total > 64 * 1024 * 1024) { total -= it.length(); it.delete() } }
    }
    companion object {
        private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        fun live(durable: File, cached: File, engine: Engine, writes: WardrobeWrites): WardrobePhotos {
            val owner = hash(engine.owner.toByteArray()); val scope = hash(engine.cacheScope.toByteArray())
            return WardrobePhotos(File(durable, "retro/$owner/photos-$scope"), File(cached, "retro/$owner/photos-$scope"), engine, writes)
        }
        private fun atomic(file: File, bytes: ByteArray) {
            Files.createDirectories(file.parentFile!!.toPath())
            val temp = File.createTempFile("photo-", ".tmp", file.parentFile)
            try { FileOutputStream(temp).use { it.write(bytes); it.fd.sync() }; Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING) }
            finally { temp.delete() }
        }
    }
}

private val Api<*>.pausesPhotoDelivery: Boolean
    get() = this == Api.Unauthorized || this == Api.NotProvisioned || this is Api.Retry || this is Api.ServerError
