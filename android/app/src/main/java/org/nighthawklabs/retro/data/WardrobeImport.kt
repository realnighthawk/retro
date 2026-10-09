package org.nighthawklabs.retro.data

import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.problem
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

suspend fun WardrobeStore.importGarment(id: String): WardrobeGarment {
    require(WardrobeMediaPath.path(id) != null) { "Invalid garment identity." }
    val result = checkNotNull(photos).currentGarment(id)
    currentCoroutineContext().ensureActive()
    check(isCurrentOwner && result is Api.Ok && result.value.garment.id == id && result.value.garment.version > 0 && result.value.garment.archivedAt == null && result.value.garment.mediaIDs.size <= 10 && result.value.garment.mediaIDs.distinct().size == result.value.garment.mediaIDs.size && result.value.garment.mediaIDs.all { WardrobeMediaPath.path(it) != null }) { result.problem ?: "Open an active, freshly loaded garment." }
    return result.value.garment
}
suspend fun WardrobeStore.useExistingImport(entryID: String, candidate: WardrobeGarment) {
    check(isCurrentOwner) { "Sign in before reviewing this import." }
    val drafts = checkNotNull(drafts); val photos = checkNotNull(photos); val writes = checkNotNull(writes)
    val entry = checkNotNull(drafts.items.find { it.id == entryID })
    check(entry.importPhoto != null && entry.dependency == null && entry.garment == null && !writes.contains(entry.entityID)) { "Use an existing item before saving the new garment." }
    val original = photos.currentGarment(entry.entityID)
    check(original is Api.Failed && original.code == "not_found") { original.problem ?: "This garment was already saved. Finish its photo or discard the import." }
    val current = importGarment(candidate.id)
    check(current.version == candidate.version && current.mediaIDs == candidate.mediaIDs && !writes.contains(current.id) && !photos.contains(current.id) && photos.drafts.none { it.garment.id == current.id } && drafts.items.find { it.id == entryID } == entry) { "The item changed or has pending work. Refresh and review it again." }
    drafts.put(entry.copy(entityID = current.id, garment = current, garmentDraft = WardrobeGarmentDraft(current), dependency = null, importMediaID = null))
}
suspend fun WardrobeStore.attachImport(entryID: String) {
    check(isCurrentOwner) { "Sign in before accepting this photo." }
    val drafts = checkNotNull(drafts); val photos = checkNotNull(photos); val writes = checkNotNull(writes)
    var entry = checkNotNull(drafts.items.find { it.id == entryID })
    check(entry.importPhoto != null && !writes.contains(entry.entityID)) { "Wait for the garment's save to be acknowledged first." }
    check(!entry.hasImportEdits()) { "Review later garment edits against the latest record in Pending saves before accepting the photo." }
    val current = importGarment(entry.entityID)
    check(drafts.items.find { it.id == entryID } == entry && !writes.contains(current.id)) { "The import changed. Review it again." }
    if (entry.dependency == null && entry.garment == null) {
        drafts.put(entry.copy(garment = current))
        entry = drafts.items.first { it.id == entryID }
        check(!entry.hasImportEdits()) { "The garment was saved before this import's handoff finished. Review its kept edits against the latest record in Pending saves." }
    }
    if (photos.batches.any { it.id == entryID }) return
    if (entry.importMediaID != null) {
        if (entry.importMediaID in current.mediaIDs) return
        val photoDraft = photos.drafts.find { it.id == entryID }
        check(photoDraft != null && photoDraft.photos.size == 1 && photoDraft.photos[0].chosen.id == entry.importMediaID) { "Photo work was removed or changed. Manage this garment's photos or finish without a photo; it will not be attached twice." }
        photos.acceptDraft(entryID)
    } else {
        if (photos.drafts.none { it.id == entryID }) {
            val bytes = drafts.importBytes(entryID)
            check(drafts.items.find { it.id == entryID } == entry && !writes.contains(current.id)) { "The import changed. Review it again." }
            photos.saveDraft(entryID, current, current.mediaIDs, listOf(WardrobePreparedPhoto(entryID, bytes, bytes)))
        }
        val photoDraft = checkNotNull(photos.drafts.find { it.id == entryID })
        check(photoDraft.garment.id == current.id && photoDraft.photos.size == 1) { "Review the stored photo draft first." }
        entry = entry.copy(importMediaID = photoDraft.photos[0].chosen.id)
        drafts.put(entry)
        photos.acceptDraft(entryID)
    }
    onEnqueued?.invoke()
}
suspend fun WardrobeStore.finishImport(entryID: String) {
    check(isCurrentOwner) { "Sign in before finishing this import." }
    val drafts = checkNotNull(drafts); val photos = checkNotNull(photos)
    val entry = checkNotNull(drafts.items.find { it.id == entryID })
    val mediaID = checkNotNull(entry.importMediaID) { "Attach the photo, or explicitly finish without it." }
    check(!entry.hasImportEdits()) { "Review later garment edits in Pending saves before finishing." }
    val current = importGarment(entry.entityID)
    check(drafts.items.find { it.id == entryID } == entry && mediaID in current.mediaIDs && writes?.contains(current.id) != true && !photos.contains(current.id) && photos.drafts.none { it.id == entryID }) { "Wait for the photo attachment to be acknowledged. Pending saves shows any errors." }
    drafts.remove(entryID)
}
