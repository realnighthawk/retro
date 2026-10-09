package org.nighthawklabs.retro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.time.LocalDate

@Composable
fun WardrobePeriodReviewScreen(store: WardrobeStore, onClose: () -> Unit) {
    var from by rememberSaveable { mutableStateOf(LocalDate.now().minusDays(29).toString()) }
    var to by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var analysis by remember { mutableStateOf(WardrobeRead<WardrobeAnalysis>()) }
    var records by remember { mutableStateOf(WardrobeRead<WardrobePage<WardrobeOutfit>>()) }
    var summary by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableStateOf(0) }
    var selected by remember { mutableStateOf<String?>(null) }
    val query = WardrobeAnalysisQuery(from, to)
    val scope = rememberCoroutineScope()
    selected?.let { id -> Dialog(onDismissRequest = { selected = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) { Surface(Modifier.fillMaxSize(), color = Retro.tok.bone) { WardrobeOutfitScreen(store, id) { selected = null } } } }
    suspend fun loadRecords(more: Boolean) {
        val period = WardrobeAnalysisQuery(from, to); val ticket = revision
        try { period.validatePeriod() } catch (e: Exception) { records = WardrobeRead(problem = e.localizedMessage); return }
        if (records.loading) return
        val previous = records
        val input = WardrobeHistoryQuery(from = period.from, to = period.to, limit = 20, cursor = if (more) previous.value?.nextCursor else null)
        records = records.copy(loading = true)
        var result = store.read("outfits_list", input, WardrobeHistoryQuery.serializer(), WardrobePage.serializer(WardrobeOutfit.serializer()))
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner || ticket != revision || WardrobeAnalysisQuery(from, to) != period) return
        if (result.value?.items?.any { it.state != "worn" || it.day < period.from || it.day > period.to || WardrobeMediaPath.path(it.id) == null } == true) result = result.copy(value = null, problem = "Source records do not match this period. Refresh.")
        if (more) {
            val page = result.value
            result = if (page != null) result.copy(value = page.copy(items = (previous.value?.items.orEmpty() + page.items).distinctBy { it.id }), cached = result.cached || previous.cached)
            else result.copy(value = previous.value, cached = previous.cached)
        }
        records = result
    }
    suspend fun load() {
        revision++; val ticket = revision; val input = WardrobeAnalysisQuery(from, to)
        analysis = WardrobeRead(); records = WardrobeRead(); summary = null
        try { input.validatePeriod() } catch (e: Exception) { analysis = WardrobeRead(problem = e.localizedMessage); return }
        analysis = WardrobeRead(loading = true)
        var result = store.read("wardrobe_analyze", input, WardrobeAnalysisQuery.serializer(), WardrobeAnalysis.serializer())
        currentCoroutineContext().ensureActive()
        if (!store.isCurrentOwner || ticket != revision || WardrobeAnalysisQuery(from, to) != input) return
        try { result.value?.let { summary = it.periodSummary(input) } }
        catch (e: Exception) { result = result.copy(value = null, problem = e.localizedMessage) }
        analysis = result
        loadRecords(false)
    }
    LaunchedEffect(query) { load() }
    WriteDialog("Wardrobe review", onClose, "Done", true, onClose) {
        item { ReviewDate("From", from) { from = it }; ReviewDate("Through", to) { to = it } }
        item { TextButton(onClick = { scope.launch { load() } }, enabled = !analysis.loading && !records.loading) { Text("Refresh review") }; ReadStatus(analysis) { scope.launch { load() } } }
        summary?.let { item { Text(it, style = MaterialTheme.typography.titleMedium) } }
        item { Text("Counts include archived garments and current categories. Unworn means no confirmed wear in these dates. Plans and pending saves are excluded.", style = MaterialTheme.typography.bodySmall) }
        if (summary != null) items(analysis.value?.categories.orEmpty(), key = { it.category }) { category -> Text("${WardrobeVocabulary.title(category.category)}: ${category.wornGarments} of ${category.garments} worn, ${category.wearEvents} garment wear events.") }
        item { Text("Source · confirmed outfit records", style = MaterialTheme.typography.titleMedium); Text("Open a record to inspect its saved garment facts. Counts cover the whole period; records load in pages. Counts and records have separate freshness indicators.", style = MaterialTheme.typography.bodySmall); ReadStatus(records) { scope.launch { loadRecords(false) } } }
        items(records.value?.items.orEmpty(), key = { it.id }) { outfit -> TextButton(onClick = { selected = outfit.id }) { Column { Text("${outfit.day} · ${outfit.title}"); Text(outfit.items.joinToString(", ") { it.snapshot?.name ?: it.garmentID }) } } }
        if (records.value?.items?.isEmpty() == true) item { Text("No confirmed outfit records in this period.") }
        if (records.value?.nextCursor != null) item { TextButton(onClick = { scope.launch { loadRecords(true) } }, enabled = !records.loading) { Text("Load older source records") } }
    }
}
@Composable private fun ReviewDate(label: String, value: String, onChange: (String) -> Unit) {
    val context = LocalContext.current; val date = LocalDate.parse(value)
    TextButton(onClick = { DatePickerDialog(context, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d).toString()) }, date.year, date.monthValue - 1, date.dayOfMonth).show() }) { Text("$label: $value") }
}
