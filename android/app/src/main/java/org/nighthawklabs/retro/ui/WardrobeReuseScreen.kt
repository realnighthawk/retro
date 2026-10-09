package org.nighthawklabs.retro.ui

import androidx.compose.material3.*
import androidx.compose.runtime.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.time.LocalDate

@Composable
fun WardrobeReuseScreen(store: WardrobeStore, id: String, onClose: () -> Unit) {
    var day by remember { mutableStateOf(LocalDate.now().toString()) }
    var review by remember { mutableStateOf<WardrobeReuseReview?>(null) }
    var replacements by remember { mutableStateOf<Map<String, WardrobeSelection>>(emptyMap()) }
    var omitted by remember { mutableStateOf<Set<String>>(emptySet()) }
    var replacing by remember { mutableStateOf<String?>(null) }
    var seed by remember { mutableStateOf<WardrobeOutfitDraft?>(null) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        busy = true; problem = null
        try {
            val result = store.reuseOutfit(id)
            if (store.isCurrentOwner) { review = result; replacements = emptyMap(); omitted = emptySet() }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { if (store.isCurrentOwner) problem = e.localizedMessage }
        finally { busy = false }
    }
    LaunchedEffect(id) { load() }
    replacing?.let { original -> WardrobeGarmentPicker(store, replacements[original]?.let(::listOf).orEmpty(), false, {
        val selected = it.firstOrNull()
        if (selected == null) replacements = replacements - original
        else { replacements = replacements + (original to selected); omitted = omitted - original }
    }, maximum = 1, onlyReady = true) { replacing = null } }
    seed?.let { WardrobeOutfitEditor(store, seed = it) { seed = null } }
    val resolved = review?.pieces?.any { it.id !in omitted } == true && review?.pieces?.all { it.problem == null || it.id in omitted || it.id in replacements } == true
    WriteDialog("Reuse outfit", onClose, "Review plan", !busy && resolved, {
        val current = review
        if (current != null) {
            val inputDay = day; val inputReplacements = replacements; val inputOmitted = omitted
            busy = true; problem = null
            scope.launch {
                try {
                    val draft = current.plan(inputDay, inputReplacements, inputOmitted)
                    val fresh = store.refreshReusePlan(draft)
                    if (store.isCurrentOwner && day == inputDay && replacements == inputReplacements && omitted == inputOmitted) seed = fresh
                } catch (e: CancellationException) { throw e }
                catch (e: Exception) { if (store.isCurrentOwner) problem = e.localizedMessage }
                finally { busy = false }
            }
        }
    }) {
        item {
            Text("Create a new plan from these pieces. Choose its date and review current garments. The original history stays intact.")
            WardrobeDateButton("New plan date", day) { day = it }
            review?.let { Text("From ${it.outfit.day} · ${it.outfit.title}") }
            if (busy) CircularProgressIndicator()
            problem?.let { Text(it, color = Retro.tok.rust) }
            TextButton(onClick = { scope.launch { load() } }, enabled = !busy) { Text("Refresh original and pieces") }
        }
        review?.pieces?.forEach { piece -> item(key = piece.id) { Panel {
            Text(piece.name, style = MaterialTheme.typography.titleMedium)
            Text(WardrobeVocabulary.title(piece.role))
            Text(if (piece.id in omitted) "Removed from this new plan" else replacements[piece.id]?.let { "Replacement: ${it.name}" } ?: piece.problem?.let { "Needs review: $it" } ?: "Ready · current garment")
            TextButton(onClick = { replacing = piece.id }, enabled = !busy) { Text("Choose replacement") }
            if (piece.id in omitted) TextButton(onClick = { omitted = omitted - piece.id }, enabled = !busy) { Text("Keep original piece") }
            else TextButton(onClick = { omitted = omitted + piece.id; replacements = replacements - piece.id }, enabled = !busy) { Text("Remove from new plan") }
        } } }
    }
}
