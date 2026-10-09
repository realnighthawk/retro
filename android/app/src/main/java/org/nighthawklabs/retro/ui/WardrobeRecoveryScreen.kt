package org.nighthawklabs.retro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import org.nighthawklabs.retro.ui.theme.Retro

@Composable
fun WardrobeRecoveryScreen(store: WardrobeStore, pending: WardrobePending? = null, draft: WardrobeSavedDraft? = null, onClose: () -> Unit) {
    val entity = pending?.entity ?: draft?.entityID ?: ""
    val garment = pending?.operation?.startsWith("garments_") ?: (draft?.garmentDraft != null)
    var requested by remember { mutableStateOf<JsonObject>(JsonObject(emptyMap())) }
    var current by remember { mutableStateOf<JsonObject>(JsonObject(emptyMap())) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var version by remember { mutableStateOf<Long?>(null) }
    var loading by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        loading = true; version = null; requested = JsonObject(emptyMap()); current = JsonObject(emptyMap()); selected = emptySet(); problem = null
        try {
            if (garment) {
                val read = store.read("garments_get", WardrobeID(entity), WardrobeID.serializer(), WardrobeGarmentResult.serializer())
                val value = checkNotNull(read.value?.takeIf { !read.cached }) { read.problem ?: "A fresh record is needed before reapplying edits." }.garment
                check(value.archivedAt == null) { "Restore this garment before editing its fields." }
                version = value.version; current = WardrobeGarmentDraft(value).fields()
            } else {
                val read = store.read("outfits_get", WardrobeID(entity), WardrobeID.serializer(), WardrobeOutfitResult.serializer())
                val value = checkNotNull(read.value?.takeIf { !read.cached }) { read.problem ?: "A fresh record is needed before reapplying edits." }.outfit
                check(value.state != "void") { "Restore this outfit before correcting it." }
                version = value.version; current = WardrobeOutfitDraft(value).fields()
            }
            currentCoroutineContext().ensureActive(); check(store.isCurrentOwner) { "Sign in again to review edits." }
            val changes = if (pending != null) (pending.body["patch"] as? JsonObject) ?: pending.body
            else if (draft?.garmentDraft != null && (draft.garment != null || draft.dependency != null)) WardrobeDraftValidation.patch(draft.garmentDraft.fields(), draft.originalGarment().fields())
            else if (draft?.outfitDraft != null && (draft.outfit != null || draft.dependency != null) && !draft.confirming) WardrobeDraftValidation.patch(draft.outfitDraft.fields(), draft.originalOutfit().fields())
            else error("Resume this draft in its editor. Create and confirm flows need their full review.")
            val allowed = if (garment) setOf("name", "category", "availability", "subtype", "colours", "warmth", "seasons", "formality", "material", "brand", "notes", "favourite") else setOf("day", "time_zone", "label", "occasion", "notes", "items")
            requested = JsonObject(changes.filter { it.key in allowed })
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { version = null; if (store.isCurrentOwner) problem = e.localizedMessage }
        finally { loading = false }
    }
    LaunchedEffect(entity) { load() }
    WriteDialog("Review latest record", onClose, "Save selected", !loading && version != null && selected.isNotEmpty() && !saved, {
        try {
            val patch = JsonObject(requested.filter { it.key in selected })
            check(patch.isNotEmpty())
            val fields = JsonObject(WardrobeDraftValidation.edit(entity, checkNotNull(version)) + ("patch" to patch))
            val operation = if (garment) "garments_update" else "outfits_update"
            if (pending != null) { checkNotNull(store.writes).replaceRejected(pending.id, operation, fields); store.onEnqueued?.invoke() }
            else store.submit(operation, entity, draft?.title ?: "Reviewed edits", fields)
            saved = true; draft?.let { store.drafts?.remove(it.id) }; onClose()
        } catch (e: Exception) { problem = e.localizedMessage }
    }) {
        item {
            Text("Compare requested fields with the latest record. Only checked fields will be reapplied. This creates a new save with the reviewed version; the original request is never changed.", style = MaterialTheme.typography.bodySmall)
            if (loading) CircularProgressIndicator()
            problem?.let { Text(it, color = Retro.tok.rust) }
            TextButton(onClick = { scope.launch { load() } }, enabled = !loading && !saved) { Text("Refresh latest record") }
        }
        requested.keys.sorted().forEach { key -> item(key = key) {
            Panel {
                Text(WardrobeVocabulary.title(key), style = MaterialTheme.typography.titleMedium)
                Text("Current: ${current[key] ?: "Empty"}"); Text("Requested: ${requested[key] ?: "Empty"}")
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = key in selected, role = Role.Checkbox, onValueChange = { selected = if (it) selected + key else selected - key })) { Checkbox(key in selected, null); Text("Apply ${WardrobeVocabulary.title(key)}", Modifier.padding(top = 12.dp)) }
            }
        } }
        if (!loading && version != null && requested.isEmpty()) item { Text("No supported fields to reapply. Resume the editor for an incomplete draft, or remove a rejected lifecycle request and review the record.") }
    }
}
