package org.nighthawklabs.retro.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
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

@Serializable data class WardrobePending(
    val id: String, val entity: String, val operation: String, val title: String,
    val body: JsonObject, val createdAt: Long,
    val dispatched: Boolean = false, val rejected: Boolean = false, val problem: String? = null,
    val context: String? = null,
    val retryAfter: Long? = null,
) {
    fun createFields(): JsonObject {
        check(operation in listOf("garments_create", "outfits_create") && WardrobeMediaPath.path(entity) != null && runCatching { UUID.fromString(id).toString() == id.lowercase() }.getOrDefault(false) && body["id"]?.jsonPrimitive?.content == entity && body["idempotency_key"]?.jsonPrimitive?.content == id) { "The original create request could not be restored." }
        return body
    }
    val requestedSummary: String get() {
        val fields = (body["patch"] as? JsonObject) ?: body
        return fields.filterKeys { it !in setOf("id", "idempotency_key", "expected_version", "source") }.entries.joinToString("\n") {
            if (it.key == "items") context ?: "Pieces: ${(it.value as? JsonArray)?.size ?: 0}"
            else "${WardrobeVocabulary.title(it.key)}: ${if (it.value is JsonPrimitive) it.value.jsonPrimitive.content else it.value}"
        }
    }
}

/** Small atomic records in noBackupFilesDir. Read-cache failures must never swallow write-queue failures. */
class WardrobeWrites(
    private val file: File,
    private val stillOwner: () -> Boolean,
    private val send: suspend (String, JsonObject) -> Api<Boolean>,
    private val save: (List<WardrobePending>) -> Unit = { items -> atomicSave(file, items) },
) {
    var items by mutableStateOf<List<WardrobePending>>(emptyList())
        private set
    var problem by mutableStateOf<String?>(null)
        private set
    var sending by mutableStateOf(false)
        private set
    var acknowledgements by mutableStateOf(0)
        private set
    val acknowledgedIDs = mutableSetOf<String>()

    init {
        try { if (file.exists()) items = ApiJson.decodeFromString(file.readText()) }
        catch (e: Exception) { problem = "Pending saves could not be opened. Keep this app's data and reopen Retro. ${e.localizedMessage}" }
    }
    fun contains(entity: String) = items.any { it.entity == entity }

    // Frozen requests stay immutable; dependent edits remain local drafts until reviewed against a fresh record.
    fun enqueue(operation: String, entity: String, title: String, fields: JsonObject, context: String? = null) {
        check(stillOwner() && problem == null) { problem ?: "Sign in again before saving." }
        check(!contains(entity)) { "This record already has a pending save. Resolve it in Pending saves first." }
        check(items.size < 100) { "Resolve pending saves before adding more." }
        val id = UUID.randomUUID().toString()
        val body = JsonObject(fields + ("idempotency_key" to JsonPrimitive(id)))
        enqueuePrepared(id, operation, entity, title, body, context)
    }

    fun enqueuePrepared(id: String, operation: String, entity: String, title: String, body: JsonObject, context: String? = null) {
        check(stillOwner() && problem == null) { problem ?: "Sign in again before saving." }
        items.find { it.id == id }?.let {
            check(it.body == body && it.operation == operation && it.entity == entity) { "The pending request identity has changed." }
            return
        }
        check(!contains(entity) && items.size < 100) { "Resolve this record's pending saves first." }
        commit(items + WardrobePending(id, entity, operation, title, body, System.currentTimeMillis(), context = context))
    }
    fun restoreCreate(original: WardrobePending) {
        original.createFields()
        check(stillOwner() && problem == null && !sending) { problem ?: "Wait for pending saves before retrying the original create." }
        items.find { it.id == original.id }?.let {
            check(it.body == original.body && it.operation == original.operation && it.entity == original.entity) { "The original request identity has changed." }
            return
        }
        check(!contains(original.entity) && items.size < 100) { "Resolve this record's pending save first." }
        commit(items + original.copy(dispatched = true, rejected = false, retryAfter = null, problem = null))
    }
    fun remove(item: WardrobePending) {
        val stored = items.find { it.id == item.id } ?: return
        check(stillOwner() && !sending && (!stored.dispatched || stored.rejected)) {
            "Retry this save to find out whether Retro received it before removing it."
        }
        commit(items.filterNot { it.id == item.id })
    }
    fun replaceRejected(id: String, operation: String, fields: JsonObject) {
        val stored = checkNotNull(items.find { it.id == id }) { "Refresh the rejected request before replacing it." }
        check(stillOwner() && problem == null && !sending && stored.rejected && fields["id"]?.jsonPrimitive?.content == stored.entity) { "Refresh the rejected request before replacing it." }
        val key = UUID.randomUUID().toString()
        val replacement = WardrobePending(key, stored.entity, operation, stored.title, JsonObject(fields + ("idempotency_key" to JsonPrimitive(key))), System.currentTimeMillis(), context = stored.context)
        commit(items.map { if (it.id == id) replacement else it })
    }
    suspend fun drain(force: Boolean = false): Boolean {
        if (!stillOwner() || problem != null || sending) return false
        sending = true
        var changed = false
        try {
            while (stillOwner() && currentCoroutineContext().isActive) {
                val index = items.indexOfFirst { !it.rejected }
                if (index < 0) break
                if (!force && (items[index].retryAfter ?: 0) > System.currentTimeMillis()) break
                try { commit(items.toMutableList().also { it[index] = it[index].copy(dispatched = true, problem = "Awaiting acknowledgement. Retry uses the original save.") }) }
                catch (e: Exception) { problem = storageProblem(e); break }
                val item = items[index]
                val result = send(item.operation, item.body)
                if (!stillOwner() || !currentCoroutineContext().isActive) break
                try {
                    if (result is Api.Ok) {
                        commit(items.filterNot { it.id == item.id }); acknowledgements++; changed = true
                        acknowledgedIDs.add(item.id)
                    } else {
                        val rejected = result is Api.Failed && result.code in setOf("conflict", "duplicate", "invalid_input", "not_found", "too_large")
                        commit(items.toMutableList().also { it[index] = it[index].copy(rejected = rejected, problem = result.problem, retryAfter = if (rejected) null else System.currentTimeMillis() + 10_000) })
                        if (!rejected) break
                    }
                } catch (e: Exception) { problem = storageProblem(e); break }
            }
        } finally { sending = false }
        return changed
    }
    private fun commit(next: List<WardrobePending>) { save(next); items = next }
    private fun storageProblem(e: Exception) = "Pending saves could not be stored. Reopen Retro to retry. ${e.localizedMessage}"

    companion object {
        fun live(root: File, engine: Engine, stillOwner: () -> Boolean): WardrobeWrites {
            fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
            val file = File(root, "retro/${hash(engine.owner)}/wardrobe-writes-${hash(engine.cacheScope)}.json")
            return WardrobeWrites(file, stillOwner, { op, body ->
                if (op == "preferences_update") engine.call<JsonObject, WardrobePreferencesResult>(op, body).map { true }
                else if (op == "outfits_feedback_update") engine.call<JsonObject, WardrobeFeedbackResult>(op, body).map { true }
                else if (op.startsWith("garments_")) engine.call<JsonObject, WardrobeGarmentResult>(op, body).map { true }
                else engine.call<JsonObject, WardrobeOutfitResult>(op, body).map { true }
            })
        }
        private fun atomicSave(file: File, items: List<WardrobePending>) {
            Files.createDirectories(file.parentFile!!.toPath())
            val temp = File.createTempFile("pending-", ".tmp", file.parentFile)
            try {
                FileOutputStream(temp).use { it.write(ApiJson.encodeToString(items).toByteArray()); it.fd.sync() }
                Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } finally { temp.delete() }
        }
    }
}
