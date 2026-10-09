package org.nighthawklabs.retro.data

import androidx.compose.runtime.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import org.nighthawklabs.retro.net.ApiJson
import org.nighthawklabs.retro.net.Engine
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID

@Serializable data class WardrobeSavedDraft(
    val id: String, val entityID: String, val garment: WardrobeGarment? = null, val outfit: WardrobeOutfit? = null,
    val confirming: Boolean = false, val garmentDraft: WardrobeGarmentDraft? = null, val outfitDraft: WardrobeOutfitDraft? = null,
    val dependency: WardrobePending? = null,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    fun originalGarment() = dependency?.let { WardrobeGarmentDraft(it.createFields()) } ?: garment?.let(::WardrobeGarmentDraft) ?: WardrobeGarmentDraft()
    fun originalOutfit() = dependency?.let { WardrobeOutfitDraft(it.createFields()) } ?: outfit?.let(::WardrobeOutfitDraft) ?: WardrobeOutfitDraft(day = outfitDraft?.day ?: java.time.LocalDate.now().toString())
    fun validateDependency() {
        val original = dependency ?: return
        check(original.entity == entityID && garment == null && outfit == null && !confirming && original.operation == (if (garmentDraft != null) "garments_create" else "outfits_create")) { "Invalid draft dependency." }
        if (garmentDraft != null) originalGarment() else {
            val baseline = originalOutfit()
            check(outfitDraft?.state == baseline.state && outfitDraft?.source == baseline.source) { "A followup draft must keep the original outfit state and source." }
        }
    }
    val title: String get() = garmentDraft?.name?.takeIf { it.isNotEmpty() } ?: outfitDraft?.label?.takeIf { it.isNotEmpty() } ?: if (garmentDraft != null) "Garment draft" else "Outfit draft"
}
class WardrobeSavedDrafts(private val file: File, private val stillOwner: () -> Boolean) {
    var items by mutableStateOf<List<WardrobeSavedDraft>>(emptyList())
        private set
    var problem by mutableStateOf<String?>(null)
        private set
    init {
        try {
            if (file.exists()) {
                check(file.length() <= 4L * 1024 * 1024) { "Draft storage exceeds its limit." }
                val values = ApiJson.decodeFromString<List<WardrobeSavedDraft>>(file.readText())
                check(values.size <= 100 && values.map { it.id }.distinct().size == values.size && values.all { runCatching { UUID.fromString(it.id) }.isSuccess && WardrobeMediaPath.path(it.entityID) != null && (it.garmentDraft == null) != (it.outfitDraft == null) && (it.garment?.id ?: it.outfit?.id ?: it.entityID) == it.entityID }) { "Invalid draft records." }
                values.forEach { it.validateDependency() }
                items = values
            }
        } catch (e: Exception) { problem = "Drafts could not be opened. Keep app data and reopen Retro. ${e.localizedMessage}" }
    }
    fun garment(id: String?) = items.lastOrNull { it.dependency == null && it.garmentDraft != null && it.garment?.id == id }
    fun outfit(id: String?, confirming: Boolean) = items.lastOrNull { it.dependency == null && it.outfitDraft != null && it.outfit?.id == id && it.confirming == confirming }
    fun follow(pending: WardrobePending, names: Map<String, String> = emptyMap()): WardrobeSavedDraft {
        check(stillOwner() && problem == null) { problem ?: "Sign in before editing a queued create." }
        items.lastOrNull { it.dependency?.id == pending.id }?.let { return it }
        val fields = pending.createFields()
        val garment = pending.operation == "garments_create"
        val value = WardrobeSavedDraft(UUID.randomUUID().toString(), pending.entity,
            garmentDraft = if (garment) WardrobeGarmentDraft(fields) else null, outfitDraft = if (garment) null else WardrobeOutfitDraft(fields).let { outfit -> outfit.copy(items = outfit.items.map { it.copy(name = names[it.id] ?: it.name) }) }, dependency = pending)
        put(value)
        return value
    }
    fun put(value: WardrobeSavedDraft) {
        check(stillOwner() && problem == null) { problem ?: "Sign in before storing a draft." }
        value.validateDependency()
        val next = items.filterNot { it.id == value.id } + value.copy(updatedAt = System.currentTimeMillis())
        require(next.size <= 100) { "Resolve older drafts before adding more." }
        commit(next)
    }
    fun remove(id: String) {
        check(stillOwner() && problem == null) { problem ?: "Sign in before discarding a draft." }
        if (items.none { it.id == id }) return
        commit(items.filterNot { it.id == id })
    }
    private fun commit(next: List<WardrobeSavedDraft>) {
        val bytes = ApiJson.encodeToString(next).toByteArray()
        require(bytes.size <= 4 * 1024 * 1024) { "Draft storage is full. Resolve older drafts first." }
        Files.createDirectories(file.parentFile!!.toPath())
        val temp = File.createTempFile("draft-", ".tmp", file.parentFile)
        try { FileOutputStream(temp).use { it.write(bytes); it.fd.sync() }; Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING) }
        finally { temp.delete() }
        items = next
    }
    companion object {
        fun live(root: File, engine: Engine): WardrobeSavedDrafts {
            fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
            return WardrobeSavedDrafts(File(root, "retro/${hash(engine.owner)}/wardrobe-drafts-${hash(engine.cacheScope)}.json")) { engine.isCurrentOwner }
        }
    }
}
