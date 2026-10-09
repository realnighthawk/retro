package org.nighthawklabs.retro.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.*
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.Api
import org.nighthawklabs.retro.net.problem
import org.nighthawklabs.retro.ui.theme.Retro

@Composable
fun WardrobeImportScreen(store: WardrobeStore, onClose: () -> Unit) {
    val drafts = checkNotNull(store.drafts)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<String?>(null) }
    selected?.let { WardrobeImportItemScreen(store, it) { selected = null } }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris ->
        if (uris.isNotEmpty() && !working) scope.launch {
            working = true; problem = null
            try {
                for ((index, uri) in uris.withIndex()) {
                    try {
                        val bytes = withContext(Dispatchers.IO) {
                            val input = checkNotNull(context.contentResolver.openInputStream(uri)) { "Photo could not be opened." }
                            val data = input.use {
                                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                                while (true) {
                                    ensureActive()
                                    val n = it.read(buffer); if (n < 0) break
                                    require(output.size() + n <= 64 * 1024 * 1024) { "Photo is too large." }
                                    output.write(buffer, 0, n)
                                }
                                output.toByteArray()
                            }
                            PhotoPreparation.normalize(data)
                        }
                        currentCoroutineContext().ensureActive()
                        drafts.addImport(bytes)
                    } catch (e: CancellationException) { throw e }
                    catch (e: Exception) { problem = "Photo ${index + 1} was not kept: ${e.localizedMessage} Earlier photos can still be reviewed."; break }
                }
            } finally { working = false }
        }
    }
    WriteDialog("Add from photos", { if (!working) onClose() }, "Done", !working, onClose) {
        item {
            Text("Choose one photo per garment. Review and save each item, then accept its photo. Close and resume here later.")
            Text("Photos stay on this phone until you accept an attachment. Each completed item is independent.", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !working && drafts.imports.size < 20) { Text("Choose garment photos") }
            Text("To review · ${drafts.imports.size}/20")
            if (working) CircularProgressIndicator()
            (problem ?: drafts.problem)?.let { Text(it, color = Retro.tok.rust) }
        }
        items(drafts.imports.sortedBy { it.updatedAt }, key = { it.id }) { entry ->
            TextButton(onClick = { selected = entry.id }, enabled = !working) {
                Column {
                    Text(entry.title)
                    Text(if (store.writes?.contains(entry.entityID) == true) "Garment save pending" else if (store.photos?.contains(entry.entityID) == true) "Photo attachment pending" else if (entry.importMediaID != null) "Check photo acknowledgement" else if (entry.dependency != null || entry.garment != null) "Accept photo next" else "Review garment next")
                }
            }
        }
        if (drafts.imports.isEmpty()) item { Text("No import photos waiting.") }
    }
}

@Composable
internal fun WardrobeImportPhoto(store: WardrobeStore, id: String) {
    var image by remember(id) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var problem by remember(id) { mutableStateOf<String?>(null) }
    LaunchedEffect(id) {
        try {
            val bytes = checkNotNull(store.drafts).importBytes(id)
            val bitmap = withContext(Dispatchers.Default) { PhotoPreparation.display(bytes)?.asImageBitmap() }
            currentCoroutineContext().ensureActive()
            if (store.isCurrentOwner) image = bitmap
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { problem = e.localizedMessage }
    }
    image?.let { Image(it, "Selected garment photo", Modifier.fillMaxWidth().heightIn(max = 320.dp)) }
    problem?.let { Text(it, color = Retro.tok.rust) }
}

@Composable
fun WardrobeImportItemScreen(store: WardrobeStore, id: String, onClose: () -> Unit) {
    val entry = store.drafts?.items?.find { it.id == id }
    var editing by remember { mutableStateOf(false) }
    var choosing by remember { mutableStateOf(false) }
    var candidate by remember { mutableStateOf<WardrobeGarment?>(null) }
    var removing by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    fun run(action: suspend () -> Unit) {
        if (!busy) scope.launch {
            busy = true; problem = null
            try { action() } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (store.isCurrentOwner) problem = e.localizedMessage }
            finally { busy = false }
        }
    }
    if (editing && entry != null) WardrobeGarmentEditor(store, resume = entry) { editing = false }
    if (choosing) WardrobeImportPicker(store, { choosing = false; candidate = it }) { choosing = false }
    candidate?.let { garment -> AlertDialog(onDismissRequest = { candidate = null },
        title = { Text("Use ${garment.name}?") }, text = { Text("This replaces the unsaved new garment details. The current item is checked again before accepting it.") },
        confirmButton = { TextButton(onClick = { candidate = null; run { store.useExistingImport(id, garment) } }) { Text("Use existing garment") } },
        dismissButton = { TextButton(onClick = { candidate = null }) { Text("Cancel") } }) }
    if (removing) AlertDialog(onDismissRequest = { removing = false }, title = { Text("Remove local import item?") },
        text = { Text("Queued garment saves and accepted photo work continue. An unaccepted photo draft stays in Pending saves.") },
        confirmButton = { TextButton(onClick = { try { store.drafts?.remove(id); onClose() } catch (e: Exception) { problem = e.localizedMessage; removing = false } }) { Text("Remove local import") } },
        dismissButton = { TextButton(onClick = { removing = false }) { Text("Cancel") } })
    WriteDialog("Review photo", { if (!busy) onClose() }, "Done", !busy, onClose) {
        if (entry != null) {
            item { WardrobeImportPhoto(store, id); Text(entry.title, style = MaterialTheme.typography.titleMedium) }
            item { Text("1. Review details. 2. Wait for the garment save. 3. Accept this photo. 4. Finish after acknowledgement.") }
            item { TextButton(onClick = { editing = true }, enabled = !busy && entry.importMediaID == null) { Text("Review garment details") } }
            if (entry.garment == null && entry.dependency == null && store.writes?.contains(entry.entityID) != true) item { TextButton(onClick = { choosing = true }, enabled = !busy) { Text("Choose an existing garment") } }
            if (store.writes?.contains(entry.entityID) == true) item { Text("Garment save pending. Check Pending saves for errors or retry.") }
            if (store.photos?.contains(entry.entityID) == true) item { Text("Photo work is pending. Its saved request and bytes are kept for retry.") }
            item { TextButton(onClick = { run { store.attachImport(id) } }, enabled = !busy && store.writes?.contains(entry.entityID) != true) { Text(if (entry.importMediaID == null) "Accept photo attachment" else "Resume photo attachment") } }
            item { TextButton(onClick = { run { store.finishImport(id); onClose() } }, enabled = !busy && entry.importMediaID != null) { Text("Check acknowledgement and finish") } }
            item { TextButton(onClick = { removing = true }, enabled = !busy) { Text("Remove from import…") } }
        } else item { Text("This import item is finished.") }
        if (busy) item { CircularProgressIndicator() }
        problem?.let { item { Text(it, color = Retro.tok.rust) } }
    }
}

@Composable
private fun WardrobeImportPicker(store: WardrobeStore, choose: (WardrobeGarment) -> Unit, onClose: () -> Unit) {
    var search by remember { mutableStateOf("") }
    var values by remember { mutableStateOf<List<WardrobeGarment>>(emptyList()) }
    var cursor by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var revision by remember { mutableStateOf(0) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load(more: Boolean) {
        revision++; val ticket = revision
        val query = WardrobeInventoryQuery(search = search, cursor = if (more) cursor else null)
        if (!more) { values = emptyList(); cursor = null }
        loading = true; problem = null
        val result = store.choices(query)
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner || search != query.search || ticket != revision) return
        loading = false
        if (result is Api.Ok) {
            val active = result.value.items.filter { it.archivedAt == null }
            values = if (more) (values + active).distinctBy { it.id } else active
            cursor = result.value.nextCursor
        } else problem = result.problem
    }
    LaunchedEffect(search) { load(false) }
    WriteDialog("Existing garment", onClose, "Cancel", true, onClose) {
        item { Text("Review a current garment before accepting a photo. This does not merge or delete garments."); OutlinedTextField(search, { search = it }, label = { Text("Search names") }, modifier = Modifier.fillMaxWidth(), singleLine = true) }
        items(values, key = { it.id }) { garment -> TextButton(onClick = { choose(garment) }, enabled = !loading) { Text(garment.name) } }
        if (loading) item { CircularProgressIndicator() }
        if (cursor != null) item { TextButton(onClick = { scope.launch { load(true) } }, enabled = !loading) { Text("Load more") } }
        problem?.let { item { Text(it, color = Retro.tok.rust); TextButton(onClick = { scope.launch { load(false) } }, enabled = !loading) { Text("Retry") } } }
        if (values.isEmpty() && !loading && problem == null) item { Text("No matching garments") }
    }
}
