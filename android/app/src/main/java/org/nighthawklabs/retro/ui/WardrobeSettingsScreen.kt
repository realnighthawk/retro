package org.nighthawklabs.retro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.ApiJson
import org.nighthawklabs.retro.ui.theme.Retro
import java.util.UUID

@Composable
fun WardrobeSettingsScreen(store: WardrobeStore, kind: String = "preferences", id: String = "", onClose: () -> Unit) {
    val title = when (kind) { "care" -> "Care instructions"; "feedback" -> "Outfit feedback"; else -> "Wardrobe settings" }
    val keys = when (kind) { "care" -> WardrobeSettingFields.care; "feedback" -> WardrobeSettingFields.feedback; else -> WardrobeSettingFields.preferences }
    var values by remember { mutableStateOf(JsonObject(emptyMap())) }
    var entity by remember { mutableStateOf("") }
    var version by remember { mutableStateOf<Long?>(null) }
    var outfitVersion by remember { mutableStateOf<Long?>(null) }
    var editable by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var auditType by remember { mutableStateOf("") }
    var audit by remember { mutableStateOf(false) }
    var resetCare by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun objectOf(body: String) = ApiJson.parseToJsonElement(body).jsonObject
    suspend fun load() {
        loading = true; editable = false; version = null; problem = null
        try {
            when (kind) {
                "care" -> {
                    val read = store.read("garments_get", WardrobeID(id), WardrobeID.serializer(), WardrobeGarmentResult.serializer())
                    val g = checkNotNull(read.value) { read.problem ?: "Garment could not be loaded." }.garment
                    values = objectOf(ApiJson.encodeToString(g.care ?: WardrobeCare())); entity = g.id; version = g.version; auditType = "garment"
                    editable = !read.cached && g.archivedAt == null; problem = read.problem
                }
                "feedback" -> {
                    val read = store.read("outfits_feedback_get", WardrobeID(id), WardrobeID.serializer(), WardrobeFeedbackResult.serializer())
                    val r = checkNotNull(read.value) { read.problem ?: "Feedback could not be loaded." }
                    values = objectOf(ApiJson.encodeToString(r.feedback)); entity = r.feedback.id; version = r.feedback.version; outfitVersion = r.current_outfit_version; auditType = "feedback"
                    editable = !read.cached && r.outfit_state == "worn"; problem = read.problem
                    val outfit = store.read("outfits_get", WardrobeID(id), WardrobeID.serializer(), WardrobeOutfitResult.serializer())
                    val o = checkNotNull(outfit.value?.takeIf { !outfit.cached }) { "Load the current outfit before reviewing feedback. Try again." }.outfit
                    check(o.version == r.current_outfit_version) { "The outfit changed. Try again before reviewing feedback." }
                    notice = "Current wear: ${o.title} · ${o.day} · ${o.items.joinToString(", ") { it.snapshot?.name ?: it.garmentID }}"
                    if (r.outfit_state != "worn") notice = "Feedback can be edited after a wear is recorded. Restore void history before editing.\n$notice"
                    else if (r.feedback.version > 0 && r.feedback.outfit_version != r.current_outfit_version) notice = "This outfit has been corrected. Review the current wear before saving feedback again.\n$notice"
                }
                else -> {
                    val read = store.read("preferences_get", WardrobeEmpty(), WardrobeEmpty.serializer(), WardrobePreferencesResult.serializer())
                    val p = checkNotNull(read.value) { read.problem ?: "Settings could not be loaded." }.preferences
                    values = objectOf(ApiJson.encodeToString(p)); entity = p.id; version = p.version; auditType = "preferences"
                    editable = !read.cached; problem = read.problem
                }
            }
            currentCoroutineContext().ensureActive()
            check(store.isCurrentOwner) { "Sign in again to edit settings." }
            if (!editable && notice == null) notice = "Previously loaded settings. Reopen when connected before editing."
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { editable = false; if (store.isCurrentOwner) problem = e.localizedMessage else { values = JsonObject(emptyMap()); version = null } }
        finally { loading = false }
    }
    LaunchedEffect(kind, id) { load() }
    if (audit) WardrobeAuditScreen(store, auditType, entity) { audit = false }
    WriteDialog(title, onClose, "Save", editable && version != null && !loading && store.writes?.contains(entity) != true, {
        try {
            if (!resetCare) WardrobeSettingFields.validate(values, keys)
            val fields = WardrobeDraftValidation.edit(entity, checkNotNull(version)).toMutableMap()
            val operation = when (kind) {
                "care" -> { fields["patch"] = buildJsonObject { put("care", if (resetCare) JsonNull else WardrobeSettingFields.patch(values, keys)) }; "garments_update" }
                "feedback" -> {
                    fields["outfit_id"] = JsonPrimitive(id); fields["expected_outfit_version"] = JsonPrimitive(checkNotNull(outfitVersion))
                    fields["patch"] = WardrobeSettingFields.patch(values, keys); "outfits_feedback_update"
                }
                else -> {
                    (values["machine_presets"] as? JsonArray)?.forEach { WardrobeSettingFields.validate(it.jsonObject, WardrobeSettingFields.preset) }
                    fields["patch"] = WardrobeSettingFields.patch(values, keys + "machine_presets"); "preferences_update"
                }
            }
            store.submit(operation, entity, title, JsonObject(fields)); onClose()
        } catch (e: Exception) { problem = e.localizedMessage }
    }) {
        item {
            if (loading) CircularProgressIndicator()
            problem?.let { Text(it, color = Retro.tok.rust) }
            notice?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            if (!editable) TextButton(onClick = { scope.launch { load() } }, enabled = !loading) { Text("Try again") }
            if (store.writes?.contains(entity) == true) Text("A save is pending. Review it in Pending saves.")
        }
        if (version != null) {
            keys.forEach { key -> item(key = key) {
                SettingField(key, values, editable && !resetCare) { values = it }
            } }
            if (kind == "preferences") {
                item { Text("Machine presets", style = MaterialTheme.typography.titleMedium) }
                val presets = (values["machine_presets"] as? JsonArray)?.map { it.jsonObject } ?: emptyList()
                presets.forEachIndexed { index, preset -> item(key = preset["id"]?.jsonPrimitive?.content ?: index) {
                    Panel {
                        WardrobeSettingFields.preset.forEach { key -> SettingField(key, preset, editable, preset = true) { updated ->
                            val list = presets.toMutableList(); list[index] = updated; values = JsonObject(values + ("machine_presets" to JsonArray(list)))
                        } }
                        TextButton(onClick = { values = JsonObject(values + ("machine_presets" to JsonArray(presets.filterIndexed { i, _ -> i != index }))) }, enabled = editable) { Text("Remove ${preset["name"]?.jsonPrimitive?.content ?: "preset"}") }
                    }
                } }
                item {
                    TextButton(onClick = {
                        val preset = buildJsonObject { put("id", UUID.randomUUID().toString()); put("name", "Cold wash"); put("temperature_c", 20); put("cycle", "gentle"); put("drying", "unknown") }
                        values = JsonObject(values + ("machine_presets" to JsonArray(presets + preset)))
                    }, enabled = editable && presets.size < 10) { Text("Add machine preset") }
                    Text("Temperatures are stored in Celsius. Saved preferences do not yet change outfit suggestions.", style = MaterialTheme.typography.bodySmall)
                }
            } else if (kind == "care") item {
                Text("Read the garment label before confirming. Leave uncertain settings Unknown. Confirmation does not add the garment to a laundry load.")
                Row { Checkbox(resetCare, { resetCare = it }, enabled = editable); Text("Remove saved care instructions") }
            } else item {
                Text("Optional ratings range from 1 to 5. Feedback does not change wears or availability.")
                TextButton(onClick = { values = JsonObject(values + keys.associateWith { if (it == "warmth") JsonPrimitive("unknown") else JsonNull }) }, enabled = editable) { Text("Clear all feedback") }
            }
            if ((version ?: 0) > 0) item { TextButton(onClick = { audit = true }) { Text("Record history") } }
        }
    }
}

@Composable
private fun SettingField(key: String, values: JsonObject, enabled: Boolean, preset: Boolean = false, onChange: (JsonObject) -> Unit) {
    val label = WardrobeSettingFields.label(key)
    fun update(value: JsonElement) = onChange(JsonObject(values + (key to value)))
    val value = values[key]
    if (key in WardrobeSettingFields.booleans) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Checkbox((value as? JsonPrimitive)?.booleanOrNull == true, { update(JsonPrimitive(it)) }, enabled = enabled)
            Text(label, Modifier.padding(top = 12.dp))
        }
    } else if (key in WardrobeSettingFields.choices) {
        var expanded by remember { mutableStateOf(false) }
        val choices = WardrobeSettingFields.choices.getValue(key).filter { !preset || key != "cycle" || it != "unknown" }
        Box {
            OutlinedButton(onClick = { expanded = true }, enabled = enabled, modifier = Modifier.fillMaxWidth()) { Text("$label: ${WardrobeVocabulary.title((value as? JsonPrimitive)?.contentOrNull ?: choices.first())}") }
            DropdownMenu(expanded, { expanded = false }) { choices.forEach { choice -> DropdownMenuItem(text = { Text(WardrobeVocabulary.title(choice)) }, onClick = { update(JsonPrimitive(choice)); expanded = false }) } }
        }
    } else {
        val text = if (value is JsonArray) value.joinToString(", ") { it.jsonPrimitive.content } else (value as? JsonPrimitive)?.contentOrNull ?: ""
        OutlinedTextField(text, { input ->
            update(when {
                key in WardrobeSettingFields.lists -> JsonArray(input.split(',').map { it.trim() }.filter { it.isNotEmpty() }.map(::JsonPrimitive))
                key in WardrobeSettingFields.ranges -> if (input.isEmpty()) JsonNull else input.toIntOrNull()?.let(::JsonPrimitive) ?: JsonPrimitive(input)
                else -> JsonPrimitive(input)
            })
        }, label = { Text(label) }, enabled = enabled, singleLine = key !in listOf("comment", "evidence"), modifier = Modifier.fillMaxWidth())
    }
}
