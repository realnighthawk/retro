package org.nighthawklabs.retro.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kotlinx.serialization.json.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.io.File
import java.util.UUID

@Composable
fun WardrobeRemotePhoto(store: WardrobeStore, id: String, modifier: Modifier = Modifier, variant: String = "thumbnail", label: String = "Garment photo") {
    var image by remember(id, variant) { mutableStateOf<ImageBitmap?>(null) }
    var problem by remember(id, variant) { mutableStateOf(false) }
    var retry by remember(id, variant) { mutableStateOf(0) }
    LaunchedEffect(id, variant, retry) {
        image = null; problem = false
        val result = store.photos?.image(id, variant, reload = retry > 0)
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner) return@LaunchedEffect
        if (result is Api.Ok) {
            val bitmap = withContext(Dispatchers.Default) { PhotoPreparation.display(result.value)?.asImageBitmap() }
            if (store.isCurrentOwner) { image = bitmap; problem = bitmap == null }
        } else problem = true
    }
    image?.let { Image(bitmap = it, contentDescription = label, modifier = modifier.fillMaxWidth(), contentScale = ContentScale.Fit) }
        ?: Column(modifier.heightIn(min = 72.dp)) {
            Text(if (problem) "Photo unavailable" else "Loading photo", color = Retro.tok.stone)
            if (problem) TextButton(onClick = { retry++ }) { Text("Retry photo") }
        }
}

@Composable
fun WardrobePhotosScreen(store: WardrobeStore, garment: WardrobeGarment, onClose: () -> Unit) {
    val savedDraft = remember(garment.id) { store.photos?.drafts?.find { it.garment.id == garment.id } }
    val record = savedDraft?.garment ?: garment
    val draftID = remember(garment.id) { savedDraft?.id ?: UUID.randomUUID().toString() }
    var loaded by remember { mutableStateOf(savedDraft == null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var retained by remember(record.id) { mutableStateOf(savedDraft?.retained ?: record.mediaIDs) }
    var prepared by remember { mutableStateOf<List<WardrobePreparedPhoto>>(emptyList()) }
    var working by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var discarding by remember { mutableStateOf(false) }
    var submitted by remember { mutableStateOf(false) }
    var cameraName by rememberSaveable { mutableStateOf<String?>(null) }
    val dirty = retained != record.mediaIDs || prepared.isNotEmpty()
    val close = { if ((dirty || !loaded) && !submitted) discarding = true else onClose() }
    fun persist(): Boolean = try {
        if (dirty) checkNotNull(store.photos).saveDraft(draftID, record, retained, prepared) else store.photos?.discardDraft(draftID)
        true
    } catch (e: Exception) { problem = e.localizedMessage; false }
    suspend fun restore() {
        working = true; problem = null
        try {
            val images = checkNotNull(store.photos).loadDraft(draftID)
            currentCoroutineContext().ensureActive()
            if (store.isCurrentOwner && !loaded) { prepared = images; loaded = true }
        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (e: Exception) { if (store.isCurrentOwner) problem = e.localizedMessage }
        finally { working = false }
    }
    LaunchedEffect(draftID) { if (!loaded) restore() }
    LaunchedEffect(retained, prepared) { if (loaded && !submitted) persist() }
    if (discarding) AlertDialog(onDismissRequest = { discarding = false }, title = { Text("Keep or discard photo edits?") },
        dismissButton = { TextButton(onClick = { discarding = false }) { Text("Keep editing") } },
        confirmButton = { Column {
            TextButton(onClick = { if (!loaded || persist()) onClose() }) { Text("Keep draft") }
            TextButton(onClick = { try { store.photos?.discardDraft(draftID); onClose() } catch (e: Exception) { problem = e.localizedMessage; discarding = false } }) { Text("Discard edits") }
        } })
    fun prepare(uris: List<android.net.Uri>, deleteAfter: File? = null) {
        if (!store.isCurrentOwner) { deleteAfter?.delete(); return }
        working = true; problem = null
        scope.launch {
            try {
                if (!loaded) restore()
                check(loaded) { "Restore the existing photo draft before adding photos." }
                val images = withContext(Dispatchers.IO) {
                    uris.map { uri ->
                        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                            val buffer = ByteArray(8192); val output = java.io.ByteArrayOutputStream()
                            while (true) {
                                val n = input.read(buffer); if (n < 0) break
                                require(output.size() + n <= 64 * 1024 * 1024) { "The selected photo is too large to open safely." }
                                output.write(buffer, 0, n)
                            }
                            output.toByteArray()
                        } ?: error("Selected photo could not be opened.")
                        PhotoPreparation.normalize(bytes).let { WardrobePreparedPhoto(original = it, chosen = it) }
                    }
                }
                currentCoroutineContext().ensureActive()
                if (!store.isCurrentOwner) return@launch
                require(retained.size + prepared.size + images.size <= 10) { "A garment can have up to 10 photos." }
                prepared = prepared + images
                persist()
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) { problem = e.localizedMessage ?: "Could not prepare photo." }
            finally { deleteAfter?.delete(); working = false }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris -> if (uris.isNotEmpty()) prepare(uris) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        cameraName?.let { name ->
            val file = File(context.cacheDir, "retro-camera/$name")
            if (success && file.exists()) prepare(listOf(FileProvider.getUriForFile(context, "${context.packageName}.photos", file)), file)
            else { file.delete(); working = false; if (!success) problem = "No camera photo was saved. Try again or choose a photo." }
        }
        cameraName = null
    }
    LaunchedEffect(store, record.id, store.photos?.foreground) {
        if (store.photos?.foreground == false) return@LaunchedEffect
        repeat(15) {
            store.sync()
            if (store.photos?.contains(record.id) != true) return@LaunchedEffect
            delay(2000)
        }
    }
    WriteDialog("Garment photos", close, "Save photos", loaded && dirty && !working && !submitted && store.photos?.contains(record.id) != true && store.writes?.contains(record.id) != true, {
        if (!submitted) try {
            check(loaded && persist()) { problem ?: "Photo draft could not be stored." }
            checkNotNull(store.photos).acceptDraft(draftID); store.onEnqueued?.invoke()
            submitted = true; onClose()
        } catch (e: Exception) { problem = e.localizedMessage ?: "Could not save photos." }
    }) {
        item {
            Text("Unsaved photo edits stay on this phone and can be resumed from Pending saves.")
            if (!loaded) TextButton(onClick = { scope.launch { restore() } }, enabled = !working) { Text("Retry loading photo draft") }
        }
        item { Text("Saved photos · first is primary", style = MaterialTheme.typography.titleMedium) }
        items(retained.size, key = { retained[it] }) { index ->
            val id = retained[index]
            Panel {
                WardrobeRemotePhoto(store, id, Modifier.height(220.dp), variant = "display")
                TextButton(onClick = { retained = listOf(id) + retained.filterNot { it == id } }, enabled = loaded && !working && index != 0) { Text("Make primary") }
                TextButton(onClick = { retained = retained.toMutableList().also { java.util.Collections.swap(it, index, index - 1) } }, enabled = loaded && !working && index > 0) { Text("Move earlier") }
                TextButton(onClick = { retained = retained.filterNot { it == id } }, enabled = loaded && !working) { Text("Remove reference") }
            }
        }
        item { Text("Removing a reference keeps photos used by past outfits. It does not permanently delete stored objects.", style = MaterialTheme.typography.bodySmall) }
        items(prepared.size, key = { prepared[it].id }) { index ->
            val photo = prepared[index]
            Panel {
                val image = remember(photo.id) { PhotoPreparation.display(photo.chosen)?.asImageBitmap() }
                image?.let { Image(bitmap = it, contentDescription = "New garment photo", modifier = Modifier.fillMaxWidth().height(220.dp), contentScale = ContentScale.Fit) }
                TextButton(onClick = { prepared = prepared.toMutableList().also { java.util.Collections.swap(it, index, index - 1) } }, enabled = index > 0 && !working) { Text("Move earlier") }
                TextButton(onClick = { prepared = prepared.filterNot { it.id == photo.id } }, enabled = !working) { Text("Remove new photo") }
            }
        }
        if (store.photos?.contains(record.id) != true) item {
            TextButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = loaded && !working && retained.size + prepared.size < 10) { Text("Choose photos") }
            TextButton(onClick = {
                try {
                    val name = "${UUID.randomUUID()}.jpg"
                    val file = File(context.cacheDir, "retro-camera/$name").apply { parentFile?.mkdirs(); createNewFile() }
                    cameraName = name
                    working = true
                    camera.launch(FileProvider.getUriForFile(context, "${context.packageName}.photos", file))
                } catch (e: Exception) { working = false; problem = "Camera is unavailable. Choose a photo instead." }
            }, enabled = loaded && !working && retained.size + prepared.size < 10) { Text("Take photo") }
            Text("Exports strip source metadata and normalize orientation. Android capture is manual; no cloud inference is used.", style = MaterialTheme.typography.bodySmall)
        }
        if (working) item { CircularProgressIndicator(); Text("Preparing photo on this device") }
        (store.photos?.problem ?: problem)?.let { item { Text(it, color = Retro.tok.rust) } }
        item { WardrobePhotoJobs(store, record.id) }
    }
}

@Composable
fun WardrobePhotoJobs(store: WardrobeStore, garmentID: String? = null) {
    val scope = rememberCoroutineScope()
    var problem by remember { mutableStateOf<String?>(null) }
    var discarding by remember { mutableStateOf<String?>(null) }
    var reviewing by remember { mutableStateOf<WardrobePhotoBatch?>(null) }
    reviewing?.let { PhotoAttachmentReview(store, it) { reviewing = null } }
    if (discarding != null) AlertDialog(onDismissRequest = { discarding = null }, title = { Text("Stop attaching this photo batch?") },
        dismissButton = { TextButton(onClick = { discarding = null }) { Text("Keep batch") } },
        confirmButton = { TextButton(onClick = { try { store.photos?.discard(discarding!!); discarding = null } catch (e: Exception) { problem = e.localizedMessage; discarding = null } }) { Text("Stop attaching") } })
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        store.photos?.batches.orEmpty().filter { garmentID == null || it.garmentID == garmentID }.forEach { batch ->
            key(batch.id) { Panel {
                Text("Photos · ${batch.title}", style = MaterialTheme.typography.titleMedium)
                batch.problem?.let { Text(it, color = Retro.tok.rust) }
                batch.photos.forEach { photo ->
                    Text(photo.media?.state?.let(WardrobeVocabulary::title) ?: "Queued")
                    photo.problem?.let { Text(it, color = Retro.tok.rust) }
                    if (photo.media?.state == "failed") TextButton(onClick = {
                        try { store.photos?.retryProcessing(batch.id, photo.id); scope.launch { store.sync(force = true) } } catch (e: Exception) { problem = e.localizedMessage }
                    }, enabled = store.photos?.running != true) { Text("Retry processing") }
                }
                if (batch.attachment != null) Text("Attachment pending acknowledgement", style = MaterialTheme.typography.bodySmall)
                if ((batch.blocked || batch.problem != null) && batch.photos.all { it.media?.state == "ready" }) TextButton(onClick = { reviewing = batch }, enabled = store.photos?.running != true) { Text("Review attachment") }
                TextButton(onClick = { scope.launch { store.sync(force = true) } }, enabled = store.photos?.running != true) { Text("Refresh and retry photos") }
                TextButton(onClick = { discarding = batch.id }, enabled = store.photos?.running != true) { Text("Stop attaching this batch") }
                Text("Uploaded objects stay private in storage. Local source bytes remain until attachment acknowledgement.", style = MaterialTheme.typography.bodySmall)
            } }
        }
        (store.photos?.problem ?: problem)?.let { Text(it, color = Retro.tok.rust) }
    }
}

@Composable
private fun PhotoAttachmentReview(store: WardrobeStore, batch: WardrobePhotoBatch, onClose: () -> Unit) {
    var current by remember { mutableStateOf<WardrobeGarment?>(null) }
    var retained by remember { mutableStateOf<List<String>>(emptyList()) }
    var problem by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableStateOf(0) }
    LaunchedEffect(revision) {
        val result = store.photos?.currentGarment(batch.garmentID)
        if (!store.isCurrentOwner) return@LaunchedEffect
        if (result is Api.Ok) { current = result.value.garment; retained = result.value.garment.mediaIDs.filter { id -> batch.photos.none { it.id == id } }; problem = null }
        else problem = result?.problem ?: "Could not load garment."
    }
    WriteDialog("Review attachment", onClose, "Use reviewed photos", current?.archivedAt == null && current != null && retained.size + batch.photos.size <= 10 && store.photos?.running != true, {
        try { store.photos?.review(batch.id, checkNotNull(current), retained); store.onEnqueued?.invoke(); onClose() }
        catch (e: Exception) { problem = e.localizedMessage }
    }) {
        item { Text("Review the current garment's photos. The ${batch.photos.size} already uploaded photos will be appended; no image is uploaded again.") }
        current?.let { garment ->
            item { Text(garment.name, style = MaterialTheme.typography.titleMedium) }
            if (garment.archivedAt != null) item { Text("Restore the garment before attaching photos.") }
            garment.mediaIDs.filter { id -> batch.photos.none { it.id == id } }.forEach { id -> item(key = id) {
                WardrobeRemotePhoto(store, id, Modifier.height(120.dp))
                Row { Checkbox(id in retained, { keep -> retained = retained.filterNot { it == id } + (if (keep) listOf(id) else emptyList()) }); Text("Keep this existing photo", Modifier.padding(top = 12.dp)) }
            } }
            batch.photos.forEach { photo -> item(key = "ready-${photo.id}") { WardrobeRemotePhoto(store, photo.id, Modifier.height(120.dp), label = "Ready photo to append") } }
        }
        problem?.let { item { Text(it, color = Retro.tok.rust) } }
        item { TextButton(onClick = { revision++ }) { Text("Refresh current garment") } }
    }
}
