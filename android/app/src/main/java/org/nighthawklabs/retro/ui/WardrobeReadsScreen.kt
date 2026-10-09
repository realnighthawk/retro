package org.nighthawklabs.retro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.ui.theme.Retro
import java.text.DateFormat
import java.time.LocalDate
import java.util.Date

@Composable
fun WardrobeTodayScreen(store: WardrobeStore, entryToken: String? = null, onOutfit: (String) -> Unit) {
    var selectedDay by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var composing by rememberSaveable { mutableStateOf(false) }
    var suggesting by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(entryToken) { if (entryToken != null) { selectedDay = LocalDate.now().toString(); composing = false; suggesting = false } }
    if (suggesting) WardrobeSuggestionsScreen(store, selectedDay) { suggesting = false }
    if (composing) WardrobeOutfitEditor(store, day = selectedDay) { composing = false }
    val date = LocalDate.parse(selectedDay)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(selectedDay) { store.refreshDay(selectedDay) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Row {
                TextButton(onClick = {
                    DatePickerDialog(context, { _, year, month, day -> selectedDay = LocalDate.of(year, month + 1, day).toString() },
                        date.year, date.monthValue - 1, date.dayOfMonth).show()
                }, modifier = Modifier.weight(1f)) { Text("Outfits for $selectedDay") }
                TextButton(onClick = { scope.launch { store.refreshDay(selectedDay) } }, enabled = !store.day.loading) { Text("Refresh") }
            }
            TextButton(onClick = { composing = true }) { Text("Compose outfit") }
            TextButton(onClick = { suggesting = true }) { Text("Suggest an outfit") }
            ReadStatus(store.day) { scope.launch { store.refreshDay(selectedDay) } }
        }
        store.day.value?.let { day ->
            if (day.outfits.isEmpty()) item { EmptyWardrobe("No outfits for this date", "Planned and recorded outfits appear here.") }
            items(day.outfits, key = { it.id }) { outfit -> OutfitReadCard(outfit) { onOutfit(outfit.id) } }
        }
    }
}

@Composable
fun WardrobeInventoryScreen(store: WardrobeStore, entrySearch: String = "", entryToken: String? = null, onGarment: (String) -> Unit) {
    var adding by rememberSaveable { mutableStateOf(false) }
    var importing by rememberSaveable { mutableStateOf(false) }
    if (importing) WardrobeImportScreen(store) { importing = false }
    if (adding) WardrobeGarmentEditor(store) { adding = false }
    var search by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("") }
    var availability by rememberSaveable { mutableStateOf("") }
    var archived by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(entryToken) { if (entryToken != null) { search = entrySearch; category = ""; availability = ""; archived = false; adding = false; importing = false } }
    val query = WardrobeInventoryQuery(search, category, availability, archived)
    val gridWidth = if (LocalDensity.current.fontScale > 1.3f) 260.dp else 140.dp
    val scope = rememberCoroutineScope()
    LaunchedEffect(query) { store.refreshInventory(query, debounce = true) }

    LazyVerticalGrid(columns = GridCells.Adaptive(gridWidth), contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { adding = true }) { Text("Add garment") }
                TextButton(onClick = { importing = true }) { Text("Add from photos · ${store.drafts?.imports?.size ?: 0} to review") }
                OutlinedTextField(value = search, onValueChange = { search = it }, label = { Text("Search garment names") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true)
                Row {
                    ReadFilter("Category", category, WardrobeVocabulary.categories, Modifier.weight(1f)) { category = it }
                    ReadFilter("Availability", availability, WardrobeVocabulary.availability, Modifier.weight(1f)) { availability = it }
                }
                Row {
                    TextButton(onClick = { archived = !archived }) { Text(if (archived) "Hide archived" else "Include archived") }
                    TextButton(onClick = { scope.launch { store.refreshInventory(query) } }, enabled = !store.inventory.loading) { Text("Refresh") }
                }
                if (archived) Text("Including archived garments", style = MaterialTheme.typography.bodySmall, color = Retro.tok.stone)
                Text("Search checks garment names, category and availability. Colour, material, warmth and wear-date search are not supported.", style = MaterialTheme.typography.bodySmall)
                if (query != WardrobeInventoryQuery()) {
                    Text("Name: ${search.ifEmpty { "Any" }} · Category: ${if (category.isEmpty()) "Any" else WardrobeVocabulary.title(category)} · Availability: ${if (availability.isEmpty()) "Any" else WardrobeVocabulary.title(availability)}", style = MaterialTheme.typography.bodySmall)
                    TextButton(onClick = { search = ""; category = ""; availability = ""; archived = false }) { Text("Clear search filters") }
                }
                ReadStatus(store.inventory) { scope.launch { store.refreshInventory(query) } }
            }
        }
        store.inventory.value?.let { page ->
            if (page.items.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                val filtered = query != WardrobeInventoryQuery()
                EmptyWardrobe(if (filtered) "No matching garments" else "Your wardrobe is empty",
                    if (filtered) "Try a different search or filter." else "Your clothes will appear here.")
            }
            items(page.items, key = { it.id }) { garment ->
                Card(onClick = { onGarment(garment.id) }, colors = CardDefaults.cardColors(containerColor = Retro.tok.paper)) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (garment.mediaIDs.isNotEmpty()) WardrobeRemotePhoto(store, garment.mediaIDs.first(), Modifier.heightIn(min = 72.dp, max = 140.dp), label = garment.name)
                        else Icon(Icons.Filled.Checkroom, contentDescription = null, tint = Retro.tok.stone,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp))
                        Text(garment.name, style = MaterialTheme.typography.titleMedium, color = Retro.tok.ink)
                        Text(WardrobeVocabulary.title(garment.category), style = MaterialTheme.typography.bodyMedium, color = Retro.tok.stone)
                        Text(if (garment.archivedAt != null) "Archived" else WardrobeVocabulary.title(garment.availability),
                            style = MaterialTheme.typography.bodySmall, color = Retro.tok.stone)
                        Text("${garment.wearDays} days worn", style = MaterialTheme.typography.bodySmall, color = Retro.tok.stone)
                    }
                }
            }
            if (page.nextCursor != null) item(span = { GridItemSpan(maxLineSpan) }) {
                TextButton(onClick = { scope.launch { store.moreInventory() } }, enabled = !store.inventory.loading,
                    modifier = Modifier.fillMaxWidth()) { Text("Load more garments") }
            }
        }
    }
}

@Composable
fun WardrobeHistoryScreen(store: WardrobeStore, onOutfit: (String) -> Unit) {
    var state by rememberSaveable { mutableStateOf("worn") }
    var limited by rememberSaveable { mutableStateOf(false) }
    var from by rememberSaveable { mutableStateOf(LocalDate.now().minusDays(29).toString()) }
    var to by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var garmentID by rememberSaveable { mutableStateOf("") }
    var garments by remember { mutableStateOf<List<WardrobeSelection>>(emptyList()) }
    var picking by remember { mutableStateOf(false) }
    var insights by remember { mutableStateOf(false) }
    var reviewing by remember { mutableStateOf(false) }
    if (reviewing) WardrobePeriodReviewScreen(store) { reviewing = false }
    if (picking) WardrobeGarmentPicker(store, garments, true, { garments = it; garmentID = it.firstOrNull()?.id ?: "" }, maximum = 1) { picking = false }
    if (insights) WardrobeInsightsScreen(store) { insights = false }
    val query = WardrobeHistoryQuery(state = state, from = if (limited) from else "", to = if (limited) to else "", garmentID = garmentID)
    val scope = rememberCoroutineScope()
    LaunchedEffect(query) { store.refreshHistory(query) }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Row {
                ReadFilter("All outfits", state, listOf("worn", "planned", "void")) { state = it }
                TextButton(onClick = { scope.launch { store.refreshHistory(query) } }, enabled = !store.history.loading) { Text("Refresh") }
            }
            TextButton(onClick = { insights = true }) { Text("Insights") }
            TextButton(onClick = { reviewing = true }) { Text("Wardrobe review") }
            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = limited, role = Role.Checkbox, onValueChange = { limited = it })) { androidx.compose.material3.Checkbox(limited, null); Text("Limit dates", Modifier.padding(top = 12.dp)) }
            if (limited) { WardrobeDateButton("From", from) { from = it }; WardrobeDateButton("Through", to) { to = it } }
            TextButton(onClick = { picking = true }) { Text(if (garmentID.isEmpty()) "Filter by garment" else "Garment: ${garments.firstOrNull()?.name ?: "Selected garment"}") }
            if (garmentID.isNotEmpty()) TextButton(onClick = { garments = emptyList(); garmentID = "" }) { Text("Clear garment filter") }
            ReadStatus(store.history) { scope.launch { store.refreshHistory(query) } }
        }
        store.history.value?.let { page ->
            if (page.items.isEmpty()) item { EmptyWardrobe("No outfits here yet", "Your outfit history appears here.") }
            page.items.groupBy { it.day }.toSortedMap(compareByDescending { it }).forEach { (date, outfits) ->
                item(key = "date:$date") { SectionHeading(date, null) }
                items(outfits, key = { it.id }) { outfit -> OutfitReadCard(outfit) { onOutfit(outfit.id) } }
            }
            if (page.nextCursor != null) item {
                TextButton(onClick = { scope.launch { store.moreHistory() } }, enabled = !store.history.loading,
                    modifier = Modifier.fillMaxWidth()) { Text("Load more outfits") }
            }
        }
    }
}

@Composable
private fun ReadFilter(title: String, selected: String, values: List<String>, modifier: Modifier = Modifier, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column(modifier) {
        TextButton(onClick = { expanded = true }) { Text(if (selected.isEmpty()) title else WardrobeVocabulary.title(selected)) }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(title) }, onClick = { onSelect(""); expanded = false })
            values.forEach { value -> DropdownMenuItem(text = { Text(WardrobeVocabulary.title(value)) }, onClick = { onSelect(value); expanded = false }) }
        }
    }
}

@Composable
private fun OutfitReadCard(outfit: WardrobeOutfit, onClick: () -> Unit) {
    Card(onClick = onClick, colors = CardDefaults.cardColors(containerColor = Retro.tok.paper)) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(outfit.title, style = MaterialTheme.typography.titleMedium, color = Retro.tok.ink)
            Text(WardrobeVocabulary.title(outfit.state), color = when (outfit.state) {
                "worn" -> Retro.tok.sage
                "void" -> Retro.tok.rust
                else -> Retro.tok.stone
            })
            Text(outfit.items.joinToString(", ") { it.snapshot?.name ?: "Garment" }, color = Retro.tok.stone)
            outfit.occasion?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = Retro.tok.stone) }
        }
    }
}

@Composable
fun WardrobeGarmentScreen(store: WardrobeStore, id: String, onBack: () -> Unit) {
    var care by remember(id) { mutableStateOf(false) }
    if (care) WardrobeSettingsScreen(store, "care", id) { care = false }
    var audit by remember { mutableStateOf(false) }
    if (audit) WardrobeAuditScreen(store, "garment", id) { audit = false }
    val fallback = store.inventory.value?.items?.find { it.id == id }?.let { WardrobeGarmentResult(it) }
    var read by remember(id) { mutableStateOf(WardrobeRead(value = fallback, cached = fallback != null)) }
    var refresh by remember { mutableStateOf(0) }
    LaunchedEffect(id, refresh, store.changes) {
        read = read.copy(loading = true)
        read = store.record("garments_get", id, fallback, WardrobeGarmentResult.serializer())
    }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            TextButton(onClick = onBack) { Text("Back") }
            ReadStatus(read) { refresh++ }
            TextButton(onClick = { refresh++ }, enabled = !read.loading) { Text("Refresh garment") }
            TextButton(onClick = { audit = true }) { Text("Record history") }
        }
        read.value?.garment?.let { garment ->
            item { WardrobeGarmentActions(store, garment, !read.loading)
                TextButton(onClick = { care = true }, enabled = !read.loading) { Text("Care instructions · ${if (garment.care?.confirmed == true) "Reviewed" else "Needs review"}") }
            }
            item {
            Panel {
                garment.mediaIDs.forEach { mediaID -> WardrobeRemotePhoto(store, mediaID, Modifier.heightIn(max = 280.dp), variant = "display", label = garment.name) }
                Text(garment.name, style = MaterialTheme.typography.headlineSmall, color = Retro.tok.ink)
                ReadField("Category", WardrobeVocabulary.title(garment.category))
                ReadField("Availability", WardrobeVocabulary.title(garment.availability))
                if (garment.archivedAt != null) ReadField("Status", "Archived")
                ReadField("Colours", garment.colours.joinToString(", "))
                ReadField("Subtype", garment.subtype)
                ReadField("Warmth", garment.warmth?.let { WardrobeVocabulary.title(it) })
                ReadField("Seasons", garment.seasons.joinToString(", "))
                ReadField("Formality", garment.formality)
                ReadField("Material", garment.material)
                ReadField("Brand", garment.brand)
                if (garment.favourite) ReadField("Favourite", "Yes")
                ReadField("Days worn", garment.wearDays.toString())
                ReadField("Outfit events", garment.wearEvents.toString())
                ReadField("Last worn", garment.lastWornOn ?: "Not recorded")
                garment.notes?.let { Text(it, color = Retro.tok.ink) }
            }
        } }
    }
}

@Composable
fun WardrobeOutfitScreen(store: WardrobeStore, id: String, onBack: () -> Unit) {
    var feedback by remember(id) { mutableStateOf(false) }
    if (feedback) WardrobeSettingsScreen(store, "feedback", id) { feedback = false }
    var audit by remember { mutableStateOf(false) }
    if (audit) WardrobeAuditScreen(store, "outfit", id) { audit = false }
    val fallback = (store.day.value?.outfits?.find { it.id == id } ?: store.history.value?.items?.find { it.id == id })?.let { WardrobeOutfitResult(it) }
    var read by remember(id) { mutableStateOf(WardrobeRead(value = fallback, cached = fallback != null)) }
    var refresh by remember { mutableStateOf(0) }
    LaunchedEffect(id, refresh, store.changes) {
        read = read.copy(loading = true)
        read = store.record("outfits_get", id, fallback, WardrobeOutfitResult.serializer())
    }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            TextButton(onClick = onBack) { Text("Back") }
            ReadStatus(read) { refresh++ }
            TextButton(onClick = { refresh++ }, enabled = !read.loading) { Text("Refresh outfit") }
            TextButton(onClick = { audit = true }) { Text("Record history") }
        }
        read.value?.outfit?.let { outfit ->
            item { WardrobeOutfitActions(store, outfit, !read.loading)
                TextButton(onClick = { feedback = true }, enabled = !read.loading) { Text("Outfit feedback") }
            }
            item {
                Panel {
                    Text(outfit.title, style = MaterialTheme.typography.headlineSmall, color = Retro.tok.ink)
                    ReadField("Date", outfit.day)
                    ReadField("Time zone", outfit.timeZone)
                    ReadField("State", WardrobeVocabulary.title(outfit.state))
                    ReadField("Occasion", outfit.occasion)
                    outfit.notes?.let { Text(it, color = Retro.tok.ink) }
                }
            }
            items(outfit.items, key = { it.garmentID }) { selection ->
                Panel {
                    selection.snapshot?.mediaIDs?.firstOrNull()?.let { mediaID -> WardrobeRemotePhoto(store, mediaID, Modifier.heightIn(max = 220.dp), variant = "display", label = selection.snapshot?.name ?: "Garment photo") }
                    Text(selection.snapshot?.name ?: "Garment", style = MaterialTheme.typography.titleMedium, color = Retro.tok.ink)
                    ReadField("Role", WardrobeVocabulary.title(selection.role))
                    ReadField("Colours", selection.snapshot?.colours?.joinToString(", "))
                }
            }
        }
    }
}

@Composable
private fun ReadField(label: String, value: String?) {
    if (!value.isNullOrEmpty()) Text("$label: $value", color = Retro.tok.ink, style = MaterialTheme.typography.bodyLarge)
}

@Composable
internal fun <T> ReadStatus(state: WardrobeRead<T>, retry: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
        if (state.loading) {
            CircularProgressIndicator(color = Retro.tok.clay)
            Text("Refreshing", color = Retro.tok.stone)
        }
        if (state.cached) Text("Previously loaded" + (state.savedAt?.let { " · ${DateFormat.getDateTimeInstance().format(Date(it))}" } ?: ""),
            style = MaterialTheme.typography.bodySmall, color = Retro.tok.stone)
        state.problem?.let {
            Text(it, color = Retro.tok.stone)
            TextButton(onClick = retry, enabled = !state.loading) { Text("Try again") }
        }
    }
}

@Composable
private fun EmptyWardrobe(title: String, description: String) {
    Panel {
        Text(title, style = MaterialTheme.typography.titleMedium, color = Retro.tok.ink)
        Text(description, style = MaterialTheme.typography.bodyMedium, color = Retro.tok.stone)
    }
}
