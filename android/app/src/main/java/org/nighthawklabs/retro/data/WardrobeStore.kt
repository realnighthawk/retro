package org.nighthawklabs.retro.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.KSerializer
import kotlinx.serialization.serializer
import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.ApiJson
import org.nighthawklabs.retro.net.EngineApi
import org.nighthawklabs.retro.net.call
import org.nighthawklabs.retro.net.problem

data class WardrobeRead<T>(
    val value: T? = null,
    val loading: Boolean = false,
    val problem: String? = null,
    val cached: Boolean = false,
    val savedAt: Long? = null,
)
@Serializable data class WardrobeCached<T>(val value: T, val savedAt: Long)

/** Used on the UI dispatcher; revisions fence older queries and account guards fence old owners. */
class WardrobeStore(
    private val engine: EngineApi,
    private val cache: WardrobeReadCache,
    val writes: WardrobeWrites? = null,
    val photos: WardrobePhotos? = null,
    val drafts: WardrobeSavedDrafts? = null,
    private val stillOwner: () -> Boolean,
) {
    var onEnqueued: (() -> Unit)? = null
    val changes: Int get() = writes?.acknowledgements ?: 0
    val isCurrentOwner: Boolean get() = stillOwner()

    suspend fun sync(force: Boolean = false) {
        var changed = writes?.drain(force) == true
        photos?.step()
        if (writes?.drain() == true) changed = true
        photos?.reconcile()
        if (!changed || !stillOwner()) return
        refreshInventory(inventoryQuery)
        refreshHistory(historyQuery)
        selectedDay?.let { refreshDay(it) }
    }

    fun submit(operation: String, entity: String, title: String, fields: kotlinx.serialization.json.JsonObject, context: String? = null) {
        checkNotNull(writes) { "Pending saves are unavailable." }.enqueue(operation, entity, title, fields, context)
        onEnqueued?.invoke()
    }

    suspend fun choices(query: WardrobeInventoryQuery): Api<WardrobePage<WardrobeGarment>> = engine.call("garments_list", query)

    suspend fun currentSummary(item: WardrobePending): String {
        if (item.operation.startsWith("garments_")) {
            val result = engine.call<WardrobeID, WardrobeGarmentResult>("garments_get", WardrobeID(item.entity))
            return if (result is Api.Ok) result.value.garment.let { g ->
                "Current: ${g.name} · ${WardrobeVocabulary.title(g.category)} · ${if (g.archivedAt == null) g.availability else "archived"}\nColours: ${g.colours.joinToString(", ")}\nNotes: ${g.notes ?: ""}\nOpen the garment to review all current details."
            } else result.problem ?: "Could not load the current garment."
        }
        val result = engine.call<WardrobeID, WardrobeOutfitResult>("outfits_get", WardrobeID(item.entity))
        return if (result is Api.Ok) result.value.outfit.let { o ->
            "Current: ${o.title} · ${o.day} · ${o.state} · ${o.timeZone}\nPieces: ${o.items.joinToString(", ") { it.snapshot?.name ?: it.garmentID }}\nNotes: ${o.notes ?: ""}"
        } else result.problem ?: "Could not load the current outfit."
    }
    var inventory by mutableStateOf(WardrobeRead<WardrobePage<WardrobeGarment>>())
        private set
    var history by mutableStateOf(WardrobeRead<WardrobePage<WardrobeOutfit>>())
        private set
    var day by mutableStateOf(WardrobeRead<WardrobeDay>())
        private set
    private var inventoryQuery = WardrobeInventoryQuery()
    private var historyQuery = WardrobeHistoryQuery()
    @Volatile private var inventoryRevision = 0
    @Volatile private var historyRevision = 0
    @Volatile private var dayRevision = 0
    private val recordRevisions = ConcurrentHashMap<String, Int>()
    private var selectedDay: String? = null

    suspend fun refreshInventory(query: WardrobeInventoryQuery, debounce: Boolean = false) {
        if (!stillOwner()) return
        val revision = ++inventoryRevision
        val previous = if (query == inventoryQuery) inventory else WardrobeRead<WardrobePage<WardrobeGarment>>()
        inventoryQuery = query
        inventory = previous.copy(loading = true, problem = null)
        val key = "inventory:" + ApiJson.encodeToString(query)
        try {
            val restored = restore(key, serializer<WardrobePage<WardrobeGarment>>())
            if (revision != inventoryRevision || !stillOwner()) return
            inventory = (if (restored.value != null) restored else previous.copy(cached = previous.value != null)).copy(loading = true, problem = null)
            if (debounce && query.search.isNotEmpty()) delay(300)
            val result = engine.call<WardrobeInventoryQuery, WardrobePage<WardrobeGarment>>("garments_list", query)
            currentCoroutineContext().ensureActive()
            if (revision == inventoryRevision && stillOwner()) {
                val next = receive(result, inventory, key, serializer<WardrobePage<WardrobeGarment>>()) { revision == inventoryRevision && stillOwner() }
                if (revision == inventoryRevision && stillOwner()) inventory = next
            }
        } finally { if (revision == inventoryRevision) inventory = inventory.copy(loading = false) }
    }

    suspend fun moreInventory() {
        val cursor = inventory.value?.nextCursor ?: return
        if (!stillOwner() || inventory.loading) return
        val revision = inventoryRevision
        val query = inventoryQuery
        inventory = inventory.copy(loading = true)
        try {
            val result = engine.call<WardrobeInventoryQuery, WardrobePage<WardrobeGarment>>("garments_list", query.copy(cursor = cursor))
            currentCoroutineContext().ensureActive()
            if (revision != inventoryRevision || !stillOwner()) return
            val combined = result.let {
                if (it is Api.Ok) Api.Ok(WardrobePage((inventory.value!!.items + it.value.items).distinctBy { g -> g.id }, it.value.nextCursor))
                else it
            }
            val next = receive(combined, inventory, "inventory:" + ApiJson.encodeToString(query), serializer<WardrobePage<WardrobeGarment>>()) { revision == inventoryRevision && stillOwner() }
            if (revision == inventoryRevision && stillOwner()) inventory = next
        } finally { if (revision == inventoryRevision) inventory = inventory.copy(loading = false) }
    }

    suspend fun refreshHistory(query: WardrobeHistoryQuery) {
        if (!stillOwner()) return
        val revision = ++historyRevision
        val previous = if (query == historyQuery) history else WardrobeRead<WardrobePage<WardrobeOutfit>>()
        historyQuery = query
        history = previous.copy(loading = true, problem = null)
        val key = "history:" + ApiJson.encodeToString(query)
        try {
            val restored = restore(key, serializer<WardrobePage<WardrobeOutfit>>())
            if (revision != historyRevision || !stillOwner()) return
            history = (if (restored.value != null) restored else previous.copy(cached = previous.value != null)).copy(loading = true, problem = null)
            val result = engine.call<WardrobeHistoryQuery, WardrobePage<WardrobeOutfit>>("outfits_list", query)
            currentCoroutineContext().ensureActive()
            if (revision == historyRevision && stillOwner()) {
                val next = receive(result, history, key, serializer<WardrobePage<WardrobeOutfit>>()) { revision == historyRevision && stillOwner() }
                if (revision == historyRevision && stillOwner()) history = next
            }
        } finally { if (revision == historyRevision) history = history.copy(loading = false) }
    }

    suspend fun moreHistory() {
        val cursor = history.value?.nextCursor ?: return
        if (!stillOwner() || history.loading) return
        val revision = historyRevision
        val query = historyQuery
        history = history.copy(loading = true)
        try {
            val result = engine.call<WardrobeHistoryQuery, WardrobePage<WardrobeOutfit>>("outfits_list", query.copy(cursor = cursor))
            currentCoroutineContext().ensureActive()
            if (revision != historyRevision || !stillOwner()) return
            val combined = result.let {
                if (it is Api.Ok) Api.Ok(WardrobePage((history.value!!.items + it.value.items).distinctBy { o -> o.id }, it.value.nextCursor))
                else it
            }
            val next = receive(combined, history, "history:" + ApiJson.encodeToString(query), serializer<WardrobePage<WardrobeOutfit>>()) { revision == historyRevision && stillOwner() }
            if (revision == historyRevision && stillOwner()) history = next
        } finally { if (revision == historyRevision) history = history.copy(loading = false) }
    }

    suspend fun refreshDay(selectedDay: String) {
        if (!stillOwner()) return
        val revision = ++dayRevision
        val previous = if (selectedDay == this.selectedDay) day else WardrobeRead<WardrobeDay>()
        this.selectedDay = selectedDay
        day = previous.copy(loading = true, problem = null)
        val key = "day:$selectedDay"
        try {
            val restored = restore(key, serializer<WardrobeDay>())
            if (revision != dayRevision || !stillOwner()) return
            day = (if (restored.value != null) restored else previous.copy(cached = previous.value != null)).copy(loading = true, problem = null)
            val result = engine.call<WardrobeDayQuery, WardrobeDay>("wardrobe_day_get", WardrobeDayQuery(selectedDay))
            currentCoroutineContext().ensureActive()
            if (revision == dayRevision && stillOwner()) {
                val next = receive(result, day, key, serializer<WardrobeDay>()) { revision == dayRevision && stillOwner() }
                if (revision == dayRevision && stillOwner()) day = next
            }
        } finally { if (revision == dayRevision) day = day.copy(loading = false) }
    }

    suspend fun <T> record(operation: String, id: String, fallback: T?, serializer: KSerializer<T>): WardrobeRead<T> {
        if (!stillOwner()) return WardrobeRead(problem = Api.Unauthorized.problem)
        val key = "$operation:$id"
        val revision = (recordRevisions[key] ?: 0) + 1
        recordRevisions[key] = revision
        var previous = restore(key, serializer)
        if (recordRevisions[key] != revision || !stillOwner()) return WardrobeRead()
        if (previous.value == null && fallback != null) previous = previous.copy(value = fallback, cached = true)
        val result = engine.call(operation, WardrobeID(id), WardrobeID.serializer(), serializer)
        currentCoroutineContext().ensureActive()
        if (!stillOwner()) return WardrobeRead()
        return receive(result, previous, key, serializer) { recordRevisions[key] == revision && stillOwner() }
    }

    suspend fun <I, T> read(operation: String, input: I, inputSerializer: KSerializer<I>, serializer: KSerializer<T>): WardrobeRead<T> {
        if (!stillOwner()) return WardrobeRead(problem = Api.Unauthorized.problem)
        val key = "$operation:" + ApiJson.encodeToString(inputSerializer, input)
        val revision = (recordRevisions[key] ?: 0) + 1
        recordRevisions[key] = revision
        val previous = restore(key, serializer)
        if (!stillOwner() || recordRevisions[key] != revision) return WardrobeRead()
        val result = engine.call(operation, input, inputSerializer, serializer)
        currentCoroutineContext().ensureActive()
        return if (stillOwner() && recordRevisions[key] == revision) receive(result, previous, key, serializer) { stillOwner() && recordRevisions[key] == revision } else WardrobeRead()
    }

    suspend fun reviewSuggestion(suggestion: WardrobeSuggestion, query: WardrobeSuggestQuery): WardrobeOutfitDraft {
        query.validate()
        val ids = suggestion.items.map { it.garmentID }
        require(ids.size in 1..30 && ids.distinct().size == ids.size && query.requiredIDs.all { it in ids } && query.excludedIDs.none { it in ids } && suggestion.fingerprint !in query.excludedCombinations) { "This suggestion does not match the requested pieces. Generate again." }
        val pieces = suggestion.items.map { item ->
            require(WardrobeMediaPath.path(item.garmentID) != null && item.role in WardrobeDraftValidation.roles && writes?.contains(item.garmentID) != true) { "Resolve the pieces' pending saves and generate again." }
            val result = engine.call<WardrobeID, WardrobeGarmentResult>("garments_get", WardrobeID(item.garmentID))
            currentCoroutineContext().ensureActive()
            check(stillOwner()) { "Sign in again before reviewing this suggestion." }
            check(result is Api.Ok) { result.problem ?: "Could not refresh the suggested garment." }
            val garment = result.value.garment
            check(garment.id == item.garmentID && garment.version == item.version && garment.archivedAt == null && garment.availability == "ready") { "A suggested piece changed or is unavailable. Generate fresh suggestions." }
            WardrobeSelection(garment.id, garment.name, item.role)
        }
        return WardrobeOutfitDraft(day = query.day, occasion = query.occasion, items = pieces, source = "suggestion")
    }

    suspend fun reuseOutfit(id: String): WardrobeReuseReview {
        check(stillOwner() && writes?.contains(id) != true) { "Wait for the original outfit's pending save before reusing it." }
        val result = engine.call<WardrobeID, WardrobeOutfitResult>("outfits_get", WardrobeID(id))
        currentCoroutineContext().ensureActive()
        check(result is Api.Ok && result.value.outfit.id == id && stillOwner()) { result.problem ?: "A fresh outfit is needed before reusing it." }
        val outfit = result.value.outfit
        require(outfit.items.size in 1..30 && outfit.items.map { it.garmentID }.distinct().size == outfit.items.size) { "Invalid original outfit pieces." }
        val pieces = outfit.items.map { item ->
            require(WardrobeMediaPath.path(item.garmentID) != null && item.role in WardrobeDraftValidation.roles) { "Invalid original outfit piece." }
            val current = engine.call<WardrobeID, WardrobeGarmentResult>("garments_get", WardrobeID(item.garmentID))
            currentCoroutineContext().ensureActive(); check(stillOwner()) { "Sign in again to reuse an outfit." }
            if (current is Api.Ok) {
                val garment = current.value.garment
                check(garment.id == item.garmentID) { "The current garment does not match the original piece." }
                val problem = if (writes?.contains(garment.id) == true) "Pending save" else if (garment.archivedAt != null) "Archived" else if (garment.availability != "ready") WardrobeVocabulary.title(garment.availability) else null
                WardrobeReusePiece(garment.id, garment.name, item.role, problem)
            } else if (current is Api.Failed && current.code == "not_found") WardrobeReusePiece(item.garmentID, item.snapshot?.name ?: "Missing garment", item.role, "No longer available")
            else error(current.problem ?: "Could not refresh an original piece. Try again when connected.")
        }
        check(writes?.contains(id) != true) { "The original outfit has a pending save. Refresh before reusing it." }
        return WardrobeReuseReview(outfit, pieces)
    }
    suspend fun refreshReusePlan(draft: WardrobeOutfitDraft): WardrobeOutfitDraft {
        val pieces = draft.items.map { item ->
            val result = engine.call<WardrobeID, WardrobeGarmentResult>("garments_get", WardrobeID(item.id))
            currentCoroutineContext().ensureActive(); check(stillOwner()) { "Sign in again before composing this plan." }
            check(result is Api.Ok && result.value.garment.id == item.id && result.value.garment.archivedAt == null && result.value.garment.availability == "ready" && writes?.contains(item.id) != true) { "${item.name} changed or could not be refreshed. Review the pieces again." }
            item.copy(name = result.value.garment.name)
        }
        return draft.copy(items = pieces).also { it.fields() }
    }

    private suspend fun <T> restore(key: String, serializer: KSerializer<T>): WardrobeRead<T> = withContext(Dispatchers.IO) {
        if (!stillOwner()) return@withContext WardrobeRead<T>()
        val saved = cache.read(key)?.let { runCatching { ApiJson.decodeFromString(WardrobeCached.serializer(serializer), it) }.getOrNull() }
        if (saved == null) WardrobeRead() else WardrobeRead(value = saved.value, cached = true, savedAt = saved.savedAt)
    }

    private suspend fun <T> receive(result: Api<T>, previous: WardrobeRead<T>, key: String, serializer: KSerializer<T>, valid: () -> Boolean = stillOwner): WardrobeRead<T> {
        if (result !is Api.Ok) return previous.copy(loading = false, problem = result.problem)
        val now = System.currentTimeMillis()
        withContext(Dispatchers.IO) {
            currentCoroutineContext().ensureActive()
            if (valid()) cache.write(key, ApiJson.encodeToString(WardrobeCached.serializer(serializer), WardrobeCached(result.value, now)))
        }
        return if (valid()) WardrobeRead(value = result.value, savedAt = now) else WardrobeRead()
    }
}
