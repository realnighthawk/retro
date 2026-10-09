package org.nighthawklabs.retro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.time.LocalDate

@Composable
fun WardrobeSuggestionsScreen(store: WardrobeStore, day: String, onClose: () -> Unit) {
    var occasion by rememberSaveable { mutableStateOf("") }
    var warmth by rememberSaveable { mutableStateOf("") }
    var required by remember { mutableStateOf<List<WardrobeSelection>>(emptyList()) }
    var excluded by remember { mutableStateOf<List<WardrobeSelection>>(emptyList()) }
    var seen by remember { mutableStateOf<List<String>>(emptyList()) }
    var variant by remember { mutableStateOf(0) }
    var choosing by remember { mutableStateOf<String?>(null) }
    var read by remember { mutableStateOf(WardrobeRead<WardrobeSuggestions>()) }
    var drafts by remember { mutableStateOf<Map<String, WardrobeOutfitDraft>>(emptyMap()) }
    var errors by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var request by remember { mutableStateOf(0) }
    var seed by remember { mutableStateOf<WardrobeOutfitDraft?>(null) }
    var reviewing by remember { mutableStateOf(false) }
    var comparison by remember { mutableStateOf<WardrobeComparison?>(null) }
    fun currentQuery() = WardrobeSuggestQuery(day, occasion, warmth, required.map { it.id }, excluded.map { it.id }, seen, variant)
    val scope = rememberCoroutineScope()
    fun reset() { seen = emptyList(); variant = 0; read = WardrobeRead(); drafts = emptyMap(); errors = emptyMap() }
    LaunchedEffect(request) {
        val input = currentQuery()
        try { input.validate() } catch (e: Exception) { read = WardrobeRead(problem = e.localizedMessage); return@LaunchedEffect }
        read = WardrobeRead(loading = true); drafts = emptyMap(); errors = emptyMap()
        val result = store.read("wardrobe_suggest", input, WardrobeSuggestQuery.serializer(), WardrobeSuggestions.serializer())
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner || currentQuery() != input) return@LaunchedEffect
        read = result
        for (option in result.value?.items.orEmpty()) {
            try {
                val draft = store.reviewSuggestion(option, input)
                currentCoroutineContext().ensureActive()
                if (!store.isCurrentOwner || currentQuery() != input) return@LaunchedEffect
                drafts = drafts + (option.fingerprint to draft)
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { if (store.isCurrentOwner && currentQuery() == input) errors = errors + (option.fingerprint to (e.localizedMessage ?: "Refresh needed")) }
        }
    }
    choosing?.let { kind ->
        WardrobeGarmentPicker(store, if (kind == "required") required else excluded, false, {
            if (kind == "required") required = it else excluded = it; reset()
        }, maximum = if (kind == "required") 10 else 100, onlyReady = kind == "required") { choosing = null }
    }
    seed?.let { WardrobeOutfitEditor(store, seed = it) { seed = null } }
    comparison?.let { WardrobeComparisonScreen(store, it, { currentQuery() }) { comparison = null } }
    WriteDialog("Suggestions", onClose, "Done", true, onClose) {
        item { Text("For $day. Suggestions are unsaved choices. Review one before saving a plan or recording wear.") }
        item { OutlinedTextField(occasion, { occasion = it; reset() }, label = { Text("Occasion or formality") }, modifier = Modifier.fillMaxWidth()) }
        item { ReviewChoice("Warmth", warmth, listOf("", "light", "mid", "warm")) { warmth = it; reset() } }
        item {
            TextButton(onClick = { choosing = "required" }) { Text("Include pieces · ${required.size}/10") }
            Text(required.joinToString(", ") { it.name })
            TextButton(onClick = { choosing = "excluded" }) { Text("Exclude pieces · ${excluded.size}") }
            Text(excluded.joinToString(", ") { it.name })
            TextButton(onClick = { seen = emptyList(); variant = 0; request++ }, enabled = !read.loading) { Text("Generate suggestions") }
            Text("Warmth and occasion prioritize saved tags. No weather is inferred.", style = MaterialTheme.typography.bodySmall)
            ReadStatus(read) { request++ }
        }
        read.value?.let { result ->
            if (result.items.isEmpty()) item { Text(result.noResultReason ?: "No eligible combinations. Compose an outfit manually.") }
            item {
                TextButton(onClick = {
                    try { comparison = WardrobeComparison(currentQuery(), result.items.filter { it.fingerprint in drafts }, drafts) }
                    catch (e: Exception) { read = read.copy(problem = e.localizedMessage) }
                }, enabled = !read.loading && drafts.size >= 2) { Text("Compare refreshed options") }
            }
            result.items.forEach { option -> item(key = option.fingerprint) {
                Panel {
                    Text(drafts[option.fingerprint]?.items?.joinToString(", ") { it.name } ?: "${option.items.size} pieces · refresh needed", style = MaterialTheme.typography.titleMedium)
                    option.reasons.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
                    if (option.missingRoles.isNotEmpty()) Text("Incomplete coverage: ${option.missingRoles.joinToString(", ") { WardrobeVocabulary.title(it) }}. You can add pieces in the editor.")
                    errors[option.fingerprint]?.let { Text(it, color = Retro.tok.rust) }
                    TextButton(onClick = {
                        val input = currentQuery(); reviewing = true
                        scope.launch {
                            try {
                                val draft = store.reviewSuggestion(option, input)
                                if (store.isCurrentOwner && currentQuery() == input) seed = draft
                            } catch (e: CancellationException) { throw e }
                            catch (e: Exception) { if (store.isCurrentOwner && currentQuery() == input) errors = errors + (option.fingerprint to (e.localizedMessage ?: "Refresh needed")) }
                            finally { reviewing = false }
                        }
                    }, enabled = !read.loading && !reviewing) { Text("Review this outfit") }
                }
            } }
            item {
                TextButton(onClick = { seen = (seen + result.items.map { it.fingerprint }).distinct().sorted(); variant++; request++ }, enabled = !read.loading && result.items.isNotEmpty() && seen.size + result.items.size <= 100 && variant < 1000) { Text("Shuffle · different combinations") }
            }
        }
    }
}

@Composable
fun WardrobeInsightsScreen(store: WardrobeStore, onClose: () -> Unit) {
    var from by rememberSaveable { mutableStateOf(LocalDate.now().minusDays(29).toString()) }
    var to by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var allTime by rememberSaveable { mutableStateOf(false) }
    var read by remember { mutableStateOf(WardrobeRead<WardrobeAnalysis>()) }
    var refresh by remember { mutableStateOf(0) }
    val query = WardrobeAnalysisQuery(if (allTime) "" else from, if (allTime) "" else to)
    LaunchedEffect(query, refresh, store.changes) {
        if (query.from.isNotEmpty() && query.from > query.to) { read = WardrobeRead(problem = "From must not be after Through."); return@LaunchedEffect }
        read = WardrobeRead(loading = true)
        read = store.read("wardrobe_analyze", query, WardrobeAnalysisQuery.serializer(), WardrobeAnalysis.serializer())
    }
    WriteDialog("Insights", onClose, "Done", true, onClose) {
        item { Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = allTime, role = Role.Checkbox, onValueChange = { allTime = it })) { Checkbox(allTime, null); Text("All time", Modifier.padding(top = 12.dp)) } }
        if (!allTime) { item { WardrobeDateButton("From", from) { from = it } }; item { WardrobeDateButton("Through", to) { to = it } } }
        item { ReadStatus(read) { refresh++ }; TextButton(onClick = { refresh++ }, enabled = !read.loading) { Text("Refresh insights") } }
        read.value?.let { value ->
            item { Panel {
                Text("Confirmed wears", style = MaterialTheme.typography.titleMedium)
                Text("Days worn: ${value.wearDays}"); Text("Outfit events: ${value.outfitEvents}")
                Text("Several outfits on one day count as one wear day. Plans, void outfits and pending saves do not count.", style = MaterialTheme.typography.bodySmall)
            } }
            item { Panel {
                Text("Wardrobe usage", style = MaterialTheme.typography.titleMedium)
                Text("Garments: ${value.garments}"); Text("Unworn in this period: ${value.unwornGarments}")
                Text("Includes archived garments. Categories reflect current inventory. Unworn means no confirmed wear in the selected period.", style = MaterialTheme.typography.bodySmall)
            } }
            value.categories.forEach { category -> item(key = category.category) { Panel {
                Text(WardrobeVocabulary.title(category.category), style = MaterialTheme.typography.titleMedium)
                Text("Garments: ${category.garments}"); Text("Worn garments: ${category.wornGarments}"); Text("Garment wear events: ${category.wearEvents}")
            } } }
        }
    }
}

@Composable
fun WardrobeAuditScreen(store: WardrobeStore, entityType: String, id: String, onClose: () -> Unit) {
    var read by remember(id) { mutableStateOf(WardrobeRead<WardrobePage<WardrobeChange>>()) }
    var revision by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    suspend fun load(more: Boolean) {
        val ticket = ++revision; val previous = read.value
        val input = WardrobeAuditQuery(entityType, id, if (more) previous?.nextCursor else null)
        read = read.copy(loading = true)
        var result = store.read("history_list", input, WardrobeAuditQuery.serializer(), WardrobePage.serializer(WardrobeChange.serializer()))
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner || ticket != revision) return
        if (more) result = result.copy(value = result.value?.let { WardrobePage((previous?.items.orEmpty() + it.items).distinctBy { c -> c.id }, it.nextCursor) } ?: previous)
        read = result
    }
    LaunchedEffect(id) { load(false) }
    WriteDialog("Record history", onClose, "Done", true, onClose) {
        item { Text("Append-only record changes. This is separate from your outfit timeline.", style = MaterialTheme.typography.bodySmall); ReadStatus(read) { scope.launch { load(false) } } }
        item { TextButton(onClick = { scope.launch { load(false) } }, enabled = !read.loading) { Text("Refresh changes") } }
        if (read.value?.items?.isEmpty() == true) item { Text("No record changes") }
        read.value?.items?.forEach { change -> item(key = change.id) { Panel {
            Text(WardrobeVocabulary.title(change.operation), style = MaterialTheme.typography.titleMedium)
            Text(change.occurredAt, style = MaterialTheme.typography.bodySmall); Text(change.details)
        } } }
        if (read.value?.nextCursor != null) item { TextButton(onClick = { scope.launch { load(true) } }, enabled = !read.loading) { Text("Load older changes") } }
    }
}

@Composable
internal fun WardrobeDateButton(label: String, value: String, onChange: (String) -> Unit) {
    val context = LocalContext.current
    TextButton(onClick = {
        val date = LocalDate.parse(value)
        DatePickerDialog(context, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d).toString()) }, date.year, date.monthValue - 1, date.dayOfMonth).show()
    }, modifier = Modifier.heightIn(min = 48.dp)) { Text("$label: $value") }
}

@Composable
private fun ReviewChoice(label: String, value: String, choices: List<String>, onChange: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }) { Text("$label: ${if (value.isEmpty()) "Any" else WardrobeVocabulary.title(value)}") }
        DropdownMenu(expanded, { expanded = false }) { choices.forEach { option ->
            DropdownMenuItem(text = { Text(if (option.isEmpty()) "Any" else WardrobeVocabulary.title(option)) }, onClick = { onChange(option); expanded = false })
        } }
    }
}
