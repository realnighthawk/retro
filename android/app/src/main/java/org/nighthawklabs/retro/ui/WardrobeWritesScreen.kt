package org.nighthawklabs.retro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.time.LocalDate
import java.util.UUID
import java.text.DateFormat
import java.util.Date

@Composable
fun WardrobeGarmentEditor(store: WardrobeStore, garment: WardrobeGarment? = null, resume: WardrobeSavedDraft? = null, onClose: () -> Unit) {
    val entry = remember(garment?.id, resume?.id) { resume ?: store.drafts?.garment(garment?.id) ?: WardrobeSavedDraft(UUID.randomUUID().toString(), garment?.id ?: UUID.randomUUID().toString(), garment = garment, garmentDraft = garment?.let(::WardrobeGarmentDraft) ?: WardrobeGarmentDraft()) }
    val baseline = entry.garment ?: garment
    val original = remember(entry.id) { entry.originalGarment() }
    val rejectedCreate = entry.dependency?.let { dependency -> store.writes?.items?.any { it.id == dependency.id && it.rejected && it.operation == dependency.operation } } == true
    var draft by rememberSaveable(entry.id, stateSaver = Saver<WardrobeGarmentDraft, String>(
        save = { ApiJson.encodeToString(it) }, restore = { ApiJson.decodeFromString(it) },
    )) { mutableStateOf(entry.garmentDraft ?: baseline?.let(::WardrobeGarmentDraft) ?: WardrobeGarmentDraft()) }
    var discarding by remember { mutableStateOf(false) }
    val close = { if (draft != original) discarding = true else onClose() }
    var problem by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }
    LaunchedEffect(draft) {
        if (!saved) try { if (draft == original && entry.dependency == null && entry.importPhoto == null) store.drafts?.remove(entry.id) else store.drafts?.put(entry.copy(garmentDraft = draft)) } catch (e: Exception) { problem = e.localizedMessage }
    }
    if (discarding) DraftEdits("Keep or discard garment edits?", { discarding = false }, {
        try { store.drafts?.put(entry.copy(garmentDraft = draft)); onClose() } catch (e: Exception) { problem = e.localizedMessage; discarding = false }
    }, { try { store.drafts?.remove(entry.id); onClose() } catch (e: Exception) { problem = e.localizedMessage; discarding = false } })
    WriteDialog(if (baseline == null) "Add garment" else "Edit garment", close, if (entry.dependency == null) "Save" else if (rejectedCreate) "Replace create" else "Keep draft", !saved && (entry.dependency != null || store.writes?.contains(entry.entityID) != true), {
        if (!saved) try {
            if (entry.dependency != null && !rejectedCreate) { store.drafts?.put(entry.copy(garmentDraft = draft)); onClose(); return@WriteDialog }
            var fields = draft.fields()
            val id = entry.entityID
            if (baseline != null) {
                val patch = WardrobeDraftValidation.patch(fields, WardrobeGarmentDraft(baseline).fields())
                if (patch.isEmpty()) { if (entry.importPhoto == null) store.drafts?.remove(entry.id); onClose(); return@WriteDialog }
                fields = JsonObject(WardrobeDraftValidation.edit(id, baseline.version) + ("patch" to patch))
            } else fields = JsonObject(fields + ("id" to JsonPrimitive(id)))
            store.drafts?.put(entry.copy(garmentDraft = draft))
            val accepted = if (entry.dependency != null) {
                val queue = checkNotNull(store.writes)
                queue.replaceRejected(entry.dependency.id, entry.dependency.operation, fields)
                val pending = queue.items.first { it.entity == id }
                store.onEnqueued?.invoke(); pending
            } else store.submit(if (baseline == null) "garments_create" else "garments_update", id, draft.name, fields)
            saved = true
            if (entry.importPhoto != null) store.drafts?.put(entry.copy(garmentDraft = if (baseline == null) draft else original, dependency = if (baseline == null) accepted else null))
            else store.drafts?.remove(entry.id)
            onClose()
        } catch (e: Exception) { problem = e.localizedMessage ?: "Could not save garment." }
    }) {
        if (entry.importPhoto != null) item { WardrobeImportPhoto(store, entry.id) }
        item { Text("Edits stay on this phone and can be resumed from Pending saves. If this record has a pending save, keep editing and review against the latest record after acknowledgement."); store.drafts?.problem?.let { Text(it, color = Retro.tok.rust) } }
        if (entry.dependency != null) item { Text("These are later edits to the queued create. Keep them locally, then review selected fields after acknowledgement. A rejected create can be replaced explicitly.") }
        item { Text(if (entry.importPhoto == null) "Photos are optional. Save the garment first, then add or manage photos from its detail." else "Save the garment, then return to this photo review to accept its attachment.", style = MaterialTheme.typography.bodySmall) }
        item { WriteField("Name", draft.name) { draft = draft.copy(name = it) } }
        item { WriteChoice("Category", draft.category, WardrobeVocabulary.categories) { draft = draft.copy(category = it) } }
        item { WriteChoice("Availability", draft.availability, WardrobeVocabulary.availability) { draft = draft.copy(availability = it) } }
        item { Row { Checkbox(checked = draft.favourite, onCheckedChange = { draft = draft.copy(favourite = it) }); Text("Favourite", Modifier.padding(top = 12.dp)) } }
        item { WriteField("Subtype", draft.subtype) { draft = draft.copy(subtype = it) } }
        item { WriteField("Colours, separated by commas", draft.colours) { draft = draft.copy(colours = it) } }
        item { WriteChoice("Warmth", draft.warmth, WardrobeDraftValidation.warmths) { draft = draft.copy(warmth = it) } }
        item { WriteField("Seasons, separated by commas", draft.seasons) { draft = draft.copy(seasons = it) } }
        item { WriteField("Formality", draft.formality) { draft = draft.copy(formality = it) } }
        item { WriteField("Material", draft.material) { draft = draft.copy(material = it) } }
        item { WriteField("Brand", draft.brand) { draft = draft.copy(brand = it) } }
        item { WriteField("Notes", draft.notes, multiline = true) { draft = draft.copy(notes = it) } }
        problem?.let { item { Text(it, color = Retro.tok.rust) } }
        item { Text("Save stores this request on this phone before sending it. Check Pending saves for acknowledgement.", style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable
fun WardrobeOutfitEditor(store: WardrobeStore, outfit: WardrobeOutfit? = null, day: String = LocalDate.now().toString(), confirming: Boolean = false, seed: WardrobeOutfitDraft? = null, resume: WardrobeSavedDraft? = null, onClose: () -> Unit) {
    val entry = remember(outfit?.id, confirming, resume?.id) { resume ?: (if (seed == null) store.drafts?.outfit(outfit?.id, confirming) else null) ?: WardrobeSavedDraft(UUID.randomUUID().toString(), outfit?.id ?: UUID.randomUUID().toString(), outfit = outfit, confirming = confirming, outfitDraft = (seed ?: outfit?.let(::WardrobeOutfitDraft) ?: WardrobeOutfitDraft(day = day)).let { if (confirming) it.copy(state = "worn") else it }) }
    val baseline = entry.outfit ?: outfit
    val rejectedCreate = entry.dependency?.let { dependency -> store.writes?.items?.any { it.id == dependency.id && it.rejected && it.operation == dependency.operation } } == true
    var draft by rememberSaveable(entry.id, confirming, stateSaver = Saver<WardrobeOutfitDraft, String>(
        save = { ApiJson.encodeToString(it) }, restore = { ApiJson.decodeFromString(it) },
    )) { mutableStateOf((entry.outfitDraft ?: baseline?.let(::WardrobeOutfitDraft) ?: WardrobeOutfitDraft(day = day)).let { if (confirming) it.copy(state = "worn") else it }) }
    var discarding by remember { mutableStateOf(false) }
    val original = remember(entry.id) { entry.originalOutfit().let { if (confirming) it.copy(state = "worn") else it } }
    val close = { if (draft != original) discarding = true else onClose() }
    var problem by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }
    var selecting by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    LaunchedEffect(draft) {
        if (!saved) try { if (draft == original && entry.dependency == null) store.drafts?.remove(entry.id) else store.drafts?.put(entry.copy(outfitDraft = draft)) } catch (e: Exception) { problem = e.localizedMessage }
    }
    if (discarding) DraftEdits("Keep or discard outfit edits?", { discarding = false }, {
        try { store.drafts?.put(entry.copy(outfitDraft = draft)); onClose() } catch (e: Exception) { problem = e.localizedMessage; discarding = false }
    }, { try { store.drafts?.remove(entry.id); onClose() } catch (e: Exception) { problem = e.localizedMessage; discarding = false } })
    WriteDialog(if (confirming) "Record wear" else if (baseline == null) "Compose outfit" else "Correct outfit", close,
        if (entry.dependency != null) (if (rejectedCreate) "Replace create" else "Keep draft") else if (confirming) "Record wear" else "Save", !saved && (entry.dependency != null || store.writes?.contains(entry.entityID) != true), {
        if (!saved) try {
            if (entry.dependency != null && !rejectedCreate) { store.drafts?.put(entry.copy(outfitDraft = draft)); onClose(); return@WriteDialog }
            require(draft.items.none { store.writes?.contains(it.id) == true }) { "Wait for the selected garments' pending saves, then review this outfit." }
            var fields = draft.fields()
            val id = entry.entityID
            val operation: String
            if (baseline != null) {
                if (confirming) {
                    fields = JsonObject(WardrobeDraftValidation.edit(id, baseline.version) + ("items" to JsonArray(draft.items.map { it.fields() })))
                    operation = "outfits_confirm"
                } else {
                    val patch = WardrobeDraftValidation.patch(fields, WardrobeOutfitDraft(baseline).fields())
                    if (patch.isEmpty()) { store.drafts?.remove(entry.id); onClose(); return@WriteDialog }
                    fields = JsonObject(WardrobeDraftValidation.edit(id, baseline.version) + ("patch" to patch))
                    operation = "outfits_update"
                }
            } else {
                fields = JsonObject(fields + mapOf("id" to JsonPrimitive(id), "state" to JsonPrimitive(draft.state), "source" to JsonPrimitive(draft.source)))
                operation = "outfits_create"
            }
            store.drafts?.put(entry.copy(outfitDraft = draft))
            if (entry.dependency != null) {
                fields = JsonObject(fields + mapOf("state" to JsonPrimitive(original.state), "source" to JsonPrimitive(original.source)))
                checkNotNull(store.writes).replaceRejected(entry.dependency.id, entry.dependency.operation, fields); store.onEnqueued?.invoke()
            } else store.submit(operation, id, draft.label.ifEmpty { "Outfit · ${draft.day}" }, fields,
                context = "Pieces: " + draft.items.joinToString(", ") { "${it.name} (${WardrobeVocabulary.title(it.role)})" })
            saved = true; store.drafts?.remove(entry.id); onClose()
        } catch (e: Exception) { problem = e.localizedMessage ?: "Could not save outfit." }
    }) {
        item { Text("Edits stay on this phone and can be resumed from Pending saves. Wait for pending saves, then review against the latest record before saving these edits."); store.drafts?.problem?.let { Text(it, color = Retro.tok.rust) } }
        if (entry.dependency != null) item { Text("Keep later edits locally, then review selected fields after acknowledgement. The queued outfit keeps its planned or worn state.") }
        item {
            TextButton(onClick = {
                val date = LocalDate.parse(draft.day)
                DatePickerDialog(context, { _, y, m, d -> draft = draft.copy(day = LocalDate.of(y, m + 1, d).toString()) }, date.year, date.monthValue - 1, date.dayOfMonth).show()
            }, enabled = !confirming) { Text("Date: ${draft.day}") }
        }
        item { WriteField("IANA time zone", draft.timeZone, enabled = !confirming) { draft = draft.copy(timeZone = it) } }
        if (baseline == null && entry.dependency == null) item { WriteChoice("Save as", draft.state, listOf("planned", "worn")) { draft = draft.copy(state = it) } }
        else if (entry.dependency == null) item { Text(if (confirming) "Review the pieces you actually wore." else "Editing a recorded outfit corrects its history.") }
        if (baseline?.state == "worn") item { Text("Changing pieces or roles refreshes garment facts for the whole outfit. Other edits keep the saved garment facts.", style = MaterialTheme.typography.bodySmall) }
        item { Text("Pieces · ${draft.items.size}/30", style = MaterialTheme.typography.titleMedium) }
        items(draft.items, key = { it.id }) { selection ->
            Panel {
                Text(selection.name, style = MaterialTheme.typography.titleMedium)
                WriteChoice("Role", selection.role, WardrobeDraftValidation.roles) { role -> draft = draft.copy(items = draft.items.map { if (it.id == selection.id) it.copy(role = role) else it }) }
                TextButton(onClick = { draft = draft.copy(items = draft.items.filterNot { it.id == selection.id }) }) { Text("Remove ${selection.name}") }
            }
        }
        item { TextButton(onClick = { selecting = true }) { Text("Choose garments") } }
        item { Text("Several layers and accessories are allowed. Wearing never changes laundry availability automatically.", style = MaterialTheme.typography.bodySmall) }
        if (!confirming) {
            item { WriteField("Label", draft.label) { draft = draft.copy(label = it) } }
            item { WriteField("Occasion", draft.occasion) { draft = draft.copy(occasion = it) } }
            item { WriteField("Notes", draft.notes, multiline = true) { draft = draft.copy(notes = it) } }
        }
        problem?.let { item { Text(it, color = Retro.tok.rust) } }
        item { Text("Pending wears do not count until Retro acknowledges them.", style = MaterialTheme.typography.bodySmall) }
    }
    if (selecting) WardrobeGarmentPicker(store, draft.items, draft.state == "worn" && !confirming, { draft = draft.copy(items = it) }) { selecting = false }
}

@Composable
internal fun WardrobeGarmentPicker(store: WardrobeStore, selected: List<WardrobeSelection>, historical: Boolean, onSelection: (List<WardrobeSelection>) -> Unit, maximum: Int = 30, onlyReady: Boolean = false, onClose: () -> Unit) {
    var search by rememberSaveable { mutableStateOf("") }
    var page by remember { mutableStateOf<WardrobePage<WardrobeGarment>?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var revision by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    suspend fun load(more: Boolean) {
        val ticket = ++revision
        val input = WardrobeInventoryQuery(search = search, includeArchived = historical, availability = if (onlyReady) "ready" else "", cursor = if (more) page?.nextCursor else null)
        if (!more) page = null
        loading = true; problem = null
        try {
            val result = store.choices(input)
            currentCoroutineContext().ensureActive()
            if (!store.isCurrentOwner || ticket != revision || input.search != search) return
            if (result is Api.Ok) page = WardrobePage(((if (more) page?.items else null).orEmpty() + result.value.items).distinctBy { it.id }, result.value.nextCursor)
            else {
                if (!more) page = WardrobePage(store.inventory.value?.items.orEmpty().filter { (historical || it.archivedAt == null) && (!onlyReady || it.availability == "ready") && (search.isEmpty() || it.name.contains(search, ignoreCase = true)) })
                problem = "${result.problem} Previously loaded choices may be incomplete."
            }
        } finally { if (ticket == revision) loading = false }
    }
    LaunchedEffect(search) { load(false) }
    WriteDialog("Choose garments", onClose, "Done", true, onClose) {
        item { WriteField("Search garment names", search) { search = it } }
        if (loading) item { CircularProgressIndicator() }
        problem?.let { item { Text(it, color = Retro.tok.rust) } }
        items(page?.items.orEmpty(), key = { it.id }) { garment ->
            val checked = selected.any { it.id == garment.id }
            TextButton(onClick = {
                val piece = WardrobeSelection(garment.id, garment.name, WardrobeDraftValidation.role(garment.category))
                val next = if (checked) selected.filterNot { it.id == garment.id } else if (maximum == 1) listOf(piece) else selected + piece
                assert(next.size <= maximum)
                onSelection(next)
            }, enabled = store.writes?.contains(garment.id) != true && (checked || maximum == 1 || selected.size < maximum), modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text("${if (checked) "Selected · " else ""}${garment.name} · ${if (garment.archivedAt == null) WardrobeVocabulary.title(garment.availability) else "Archived"}")
            }
        }
        if (page?.nextCursor != null) item { TextButton(onClick = { scope.launch { load(true) } }, enabled = !loading) { Text("Load more garments") } }
        if (!loading && page?.items?.isEmpty() == true) item { Text("No matching garments") }
    }
}

@Composable
fun WardrobePendingScreen(store: WardrobeStore, onClose: () -> Unit) {
    var resumingPhotos by remember { mutableStateOf<WardrobePhotoDraft?>(null) }
    var discardingPhotos by remember { mutableStateOf<WardrobePhotoDraft?>(null) }
    resumingPhotos?.let { WardrobePhotosScreen(store, it.garment) { resumingPhotos = null } }
    var resuming by remember { mutableStateOf<WardrobeSavedDraft?>(null) }
    var reviewing by remember { mutableStateOf<WardrobePending?>(null) }
    var reviewingDraft by remember { mutableStateOf<WardrobeSavedDraft?>(null) }
    var discardingDraft by remember { mutableStateOf<WardrobeSavedDraft?>(null) }
    resuming?.let { entry -> if (entry.importPhoto != null) WardrobeImportItemScreen(store, entry.id) { resuming = null }
        else if (entry.garmentDraft != null) WardrobeGarmentEditor(store, garment = entry.garment, resume = entry) { resuming = null }
        else WardrobeOutfitEditor(store, outfit = entry.outfit, confirming = entry.confirming, resume = entry) { resuming = null } }
    reviewing?.let { WardrobeRecoveryScreen(store, pending = it) { reviewing = null } }
    reviewingDraft?.let { WardrobeRecoveryScreen(store, draft = it) { reviewingDraft = null } }
    var problem by remember { mutableStateOf<String?>(null) }
    var current by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    discardingPhotos?.let { entry -> AlertDialog(onDismissRequest = { discardingPhotos = null }, title = { Text("Discard this local photo draft?") },
        dismissButton = { TextButton(onClick = { discardingPhotos = null }) { Text("Keep draft") } },
        confirmButton = { TextButton(onClick = { try { store.photos?.discardDraft(entry.id); discardingPhotos = null } catch (e: Exception) { problem = e.localizedMessage; discardingPhotos = null } }) { Text("Discard photo draft") } }) }
    discardingDraft?.let { entry -> AlertDialog(onDismissRequest = { discardingDraft = null }, title = { Text("Discard this local draft?") },
        dismissButton = { TextButton(onClick = { discardingDraft = null }) { Text("Keep draft") } },
        confirmButton = { TextButton(onClick = { try { store.drafts?.remove(entry.id); discardingDraft = null } catch (e: Exception) { problem = e.localizedMessage; discardingDraft = null } }) { Text("Discard draft") } }) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(store.photos?.foreground) {
        if (store.photos?.foreground == false) return@LaunchedEffect
        repeat(15) {
            store.sync()
            if (store.photos?.batches.isNullOrEmpty()) return@LaunchedEffect
            kotlinx.coroutines.delay(2000)
        }
    }
    WriteDialog("Pending saves", onClose, "Done", true, onClose) {
        item {
            Text("Saved on this phone. Confirmed history and counts change only after acknowledgement.")
            TextButton(onClick = { scope.launch { store.sync(force = true) } }, enabled = store.writes?.sending != true) { Text(if (store.writes?.sending == true) "Sending…" else "Retry pending saves") }
            (store.writes?.problem ?: problem)?.let { Text(it, color = Retro.tok.rust) }
        }
        store.drafts?.problem?.let { item { Text(it, color = Retro.tok.rust) } }
        items(store.drafts?.items.orEmpty(), key = { "draft:" + it.id }) { draft -> Panel {
            Text("Draft · ${draft.title}", style = MaterialTheme.typography.titleMedium)
            Text(if (draft.importPhoto == null) "Local draft · not sent" else "Photo import · resume to check save and attachment progress")
            TextButton(onClick = { resuming = draft }) { Text("Resume editing") }
            if (draft.dependency != null || draft.garment != null || (draft.outfit != null && !draft.confirming)) TextButton(onClick = { reviewingDraft = draft }, enabled = store.writes?.contains(draft.entityID) != true) { Text("Review against latest record") }
            draft.dependency?.let { dependency ->
                Text("The original create keeps its request identity. After acknowledgement, review only these later edits against the current record.")
                TextButton(onClick = { try { checkNotNull(store.writes).restoreCreate(dependency); scope.launch { store.sync(force = true) } } catch (e: Exception) { problem = e.localizedMessage } },
                    enabled = store.writes?.sending != true && (store.writes?.contains(draft.entityID) != true || store.writes?.items?.any { it.id == dependency.id } == true)) { Text("Retry original create") }
            }
            TextButton(onClick = { discardingDraft = draft }) { Text("Discard draft") }
        } }
        items(store.photos?.drafts.orEmpty(), key = { "photo-draft:" + it.id }) { draft -> Panel {
            Text("Photo draft · ${draft.garment.name}", style = MaterialTheme.typography.titleMedium)
            Text("Local photo edits · not sent")
            TextButton(onClick = { resumingPhotos = draft }) { Text("Resume photo edits") }
            TextButton(onClick = { discardingPhotos = draft }) { Text("Discard photo draft") }
        } }
        item { WardrobePhotoJobs(store) }
        if (store.writes?.items.isNullOrEmpty() && store.photos?.batches.isNullOrEmpty() && store.drafts?.items.isNullOrEmpty() && store.photos?.drafts.isNullOrEmpty()) item { Text("No pending saves or drafts") }
        items(store.writes?.items.orEmpty(), key = { it.id }) { item ->
            Panel {
                Text(item.title, style = MaterialTheme.typography.titleMedium)
                Text(if (item.rejected) "Needs review · server rejected this save" else if (item.dispatched) "Awaiting acknowledgement" else "Queued")
                item.problem?.let { Text(it, color = Retro.tok.rust) }
                Text(DateFormat.getDateTimeInstance().format(Date(item.createdAt)), style = MaterialTheme.typography.bodySmall)
                if (item.operation in listOf("garments_create", "outfits_create")) TextButton(onClick = { try { resuming = checkNotNull(store.drafts).follow(item, store.inventory.value?.items.orEmpty().associate { it.id to it.name }) } catch (e: Exception) { problem = e.localizedMessage } }) { Text("Continue editing locally") }
                if (item.rejected) {
                    Text("Compare requested changes with the latest record. Reapply selected fields with a new save, or remove this rejected request before editing manually.", style = MaterialTheme.typography.bodySmall)
                    if (item.operation in listOf("garments_update", "garments_create", "outfits_update", "outfits_create", "preferences_update", "outfits_feedback_update") && store.photos?.batches?.none { it.attachmentKey == item.id } != false) TextButton(onClick = { reviewing = item }) { Text("Review and reapply selected fields") }
                    Text(item.requestedSummary, style = MaterialTheme.typography.bodySmall)
                    TextButton(onClick = { scope.launch { current = current + (item.id to store.currentSummary(item)) } }) { Text("Load current record") }
                    current[item.id]?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
                if (!item.dispatched || item.rejected) {
                    TextButton(onClick = { try { store.writes?.remove(item) } catch (e: Exception) { problem = e.localizedMessage } }, enabled = store.writes?.sending != true) {
                        Text(if (item.rejected) "Remove rejected request" else "Remove unsent request")
                    }
                } else Text("Retry to reconcile this request before removing it.", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WriteDialog(title: String, onClose: () -> Unit, saveLabel: String, enabled: Boolean, onSave: () -> Unit,
                        content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(containerColor = Retro.tok.bone, topBar = {
            TopAppBar(title = { Text(title) }, navigationIcon = { TextButton(onClick = onClose) { Text("Cancel") } },
                actions = { TextButton(onClick = onSave, enabled = enabled) { Text(saveLabel) } })
        }) { padding ->
            LazyColumn(Modifier.fillMaxSize().padding(padding).imePadding(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
        }
    }
}
@Composable private fun WriteField(label: String, value: String, multiline: Boolean = false, enabled: Boolean = true, onChange: (String) -> Unit) {
    OutlinedTextField(value = value, onValueChange = onChange, label = { Text(label) }, singleLine = !multiline, minLines = if (multiline) 3 else 1, enabled = enabled, modifier = Modifier.fillMaxWidth())
}
@Composable private fun WriteChoice(label: String, value: String, choices: List<String>, onChange: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { open = true }, modifier = Modifier.heightIn(min = 48.dp)) { Text("$label: ${WardrobeVocabulary.title(value)}") }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.forEach { choice -> DropdownMenuItem(text = { Text(WardrobeVocabulary.title(choice)) }, onClick = { onChange(choice); open = false }) }
        }
    }
}

@Composable
fun WardrobeGarmentActions(store: WardrobeStore, garment: WardrobeGarment, enabled: Boolean) {
    var photos by remember { mutableStateOf<WardrobeGarment?>(null) }
    var editing by remember { mutableStateOf<WardrobeGarment?>(null) }
    var lifecycle by remember { mutableStateOf<WardrobeGarment?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    editing?.let { frozen -> WardrobeGarmentEditor(store, frozen) { editing = null } }
    photos?.let { frozen -> WardrobePhotosScreen(store, frozen) { photos = null } }
    lifecycle?.let { frozen ->
        val archive = frozen.archivedAt == null
        AlertDialog(onDismissRequest = { lifecycle = null }, title = { Text(if (archive) "Archive this garment?" else "Restore this garment?") },
            text = { Text("Existing outfit history stays intact.") }, dismissButton = { TextButton(onClick = { lifecycle = null }) { Text("Cancel") } },
            confirmButton = { TextButton(onClick = {
                try { store.submit(if (archive) "garments_archive" else "garments_restore", frozen.id, frozen.name, WardrobeDraftValidation.edit(frozen.id, frozen.version)); lifecycle = null }
                catch (e: Exception) { problem = e.localizedMessage; lifecycle = null }
            }, enabled = store.writes?.contains(frozen.id) != true) { Text(if (archive) "Archive" else "Restore") } })
    }
    Column {
        if (store.writes?.contains(garment.id) == true) Text("This garment has a pending save. Open Pending saves to review it.")
        problem?.let { Text(it, color = Retro.tok.rust) }
        Row {
            if (garment.archivedAt == null) TextButton(onClick = { photos = garment }, enabled = enabled) { Text("Photos") }
            if (garment.archivedAt == null) TextButton(onClick = { editing = garment }, enabled = enabled) { Text("Edit") }
            TextButton(onClick = { lifecycle = garment }, enabled = enabled && store.writes?.contains(garment.id) != true) { Text(if (garment.archivedAt == null) "Archive" else "Restore") }
        }
    }
}

@Composable
fun WardrobeOutfitActions(store: WardrobeStore, outfit: WardrobeOutfit, enabled: Boolean) {
    var reusing by remember { mutableStateOf(false) }
    if (reusing) WardrobeReuseScreen(store, outfit.id) { reusing = false }
    var editing by remember { mutableStateOf<WardrobeOutfit?>(null) }
    var confirming by remember { mutableStateOf<WardrobeOutfit?>(null) }
    var lifecycle by remember { mutableStateOf<WardrobeOutfit?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    editing?.let { frozen -> WardrobeOutfitEditor(store, frozen) { editing = null } }
    confirming?.let { frozen -> WardrobeOutfitEditor(store, frozen, confirming = true) { confirming = null } }
    lifecycle?.let { frozen ->
        val restore = frozen.state == "void"
        AlertDialog(onDismissRequest = { lifecycle = null }, title = { Text(if (restore) "Restore this outfit?" else "Void this outfit?") },
            text = { Text(if (restore) "Reinstate the previous outfit state." else "Its wears stop counting after acknowledgement.") },
            dismissButton = { TextButton(onClick = { lifecycle = null }) { Text("Cancel") } },
            confirmButton = { TextButton(onClick = {
                try { store.submit(if (restore) "outfits_restore" else "outfits_void", frozen.id, frozen.title, WardrobeDraftValidation.edit(frozen.id, frozen.version)); lifecycle = null }
                catch (e: Exception) { problem = e.localizedMessage; lifecycle = null }
            }, enabled = store.writes?.contains(frozen.id) != true) { Text(if (restore) "Restore" else "Void") } })
    }
    Column {
        if (store.writes?.contains(outfit.id) == true) Text("This outfit has a pending save. It is not confirmed until acknowledged.")
        problem?.let { Text(it, color = Retro.tok.rust) }
        val available = enabled && store.writes?.contains(outfit.id) != true
        TextButton(onClick = { reusing = true }, enabled = available) { Text("Reuse as a new plan") }
        if (outfit.state != "void") TextButton(onClick = { editing = outfit }, enabled = enabled) { Text("Correct outfit") }
        if (outfit.state == "planned") TextButton(onClick = { confirming = outfit }, enabled = available) { Text("Record wear") }
        TextButton(onClick = { lifecycle = outfit }, enabled = available) { Text(if (outfit.state == "void") "Restore outfit" else "Void outfit") }
    }
}

@Composable private fun DiscardEdits(title: String, onCancel: () -> Unit, onDiscard: () -> Unit) {
    AlertDialog(onDismissRequest = onCancel, title = { Text(title) },
        dismissButton = { TextButton(onClick = onCancel) { Text("Keep editing") } },
        confirmButton = { TextButton(onClick = onDiscard) { Text("Discard edits") } })
}

@Composable private fun DraftEdits(title: String, onCancel: () -> Unit, onKeep: () -> Unit, onDiscard: () -> Unit) {
    AlertDialog(onDismissRequest = onCancel, title = { Text(title) },
        dismissButton = { TextButton(onClick = onCancel) { Text("Keep editing") } },
        confirmButton = { Column { TextButton(onClick = onKeep) { Text("Keep draft") }; TextButton(onClick = onDiscard) { Text("Discard edits") } } })
}
