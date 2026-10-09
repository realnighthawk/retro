package org.nighthawklabs.retro.ui

import androidx.compose.material3.*
import androidx.compose.runtime.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.ui.theme.Retro

@Composable
fun WardrobeComparisonScreen(store: WardrobeStore, comparison: WardrobeComparison, currentQuery: () -> WardrobeSuggestQuery, onClose: () -> Unit) {
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var seed by remember { mutableStateOf<WardrobeOutfitDraft?>(null) }
    val scope = rememberCoroutineScope()
    seed?.let { WardrobeOutfitEditor(store, seed = it) { seed = null } }
    WriteDialog("Compare outfits", onClose, "Done", true, onClose) {
        item {
            Text("For ${comparison.query.day}")
            if (comparison.query.occasion.isNotEmpty()) Text("Occasion: ${comparison.query.occasion}")
            if (comparison.query.warmth.isNotEmpty()) Text("Warmth: ${WardrobeVocabulary.title(comparison.query.warmth)}")
            Text("Compare real pieces and the engine's reasons. Warmth and occasion use saved tags; weather and fit are not assessed.", style = MaterialTheme.typography.bodySmall)
            Text("${comparison.sharedIDs.size} pieces appear in every option.")
            if (busy) CircularProgressIndicator()
            problem?.let { Text(it, color = Retro.tok.rust) }
        }
        comparison.candidates.forEachIndexed { index, candidate -> item(key = candidate.option.fingerprint) { Panel {
            Text("Option ${index + 1}", style = MaterialTheme.typography.titleMedium)
            candidate.draft.items.forEach { piece ->
                Text(piece.name)
                Text("${WardrobeVocabulary.title(piece.role)} · ${if (piece.id in comparison.sharedIDs) "In every option" else "Varies between options"}", style = MaterialTheme.typography.bodySmall)
            }
            candidate.option.reasons.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
            if (candidate.option.missingRoles.isNotEmpty()) Text("Missing roles: ${candidate.option.missingRoles.joinToString(", ") { WardrobeVocabulary.title(it) }}")
            TextButton(onClick = {
                if (currentQuery() != comparison.query) problem = "Your request changed. Generate and compare fresh options."
                else {
                    busy = true; problem = null
                    scope.launch {
                        try {
                            val fresh = store.reviewSuggestion(candidate.option, comparison.query)
                            if (store.isCurrentOwner && currentQuery() == comparison.query) seed = fresh
                        } catch (e: CancellationException) { throw e }
                        catch (e: Exception) { if (store.isCurrentOwner) problem = e.localizedMessage }
                        finally { busy = false }
                    }
                }
            }, enabled = !busy) { Text("Review option ${index + 1}") }
        } } }
    }
}
