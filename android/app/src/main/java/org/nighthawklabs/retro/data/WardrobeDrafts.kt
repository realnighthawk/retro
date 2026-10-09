package org.nighthawklabs.retro.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.util.UUID
import java.time.LocalDate
import java.time.ZoneId

@Serializable data class WardrobeGarmentDraft(
    val name: String = "", val category: String = "top", val availability: String = "ready",
    val subtype: String = "", val colours: String = "", val warmth: String = "unknown", val seasons: String = "",
    val formality: String = "", val material: String = "", val brand: String = "", val notes: String = "", val favourite: Boolean = false,
) {
    constructor(g: WardrobeGarment) : this(g.name, g.category, g.availability, g.subtype ?: "", g.colours.joinToString(", "),
        g.warmth ?: "unknown", g.seasons.joinToString(", "), g.formality ?: "", g.material ?: "", g.brand ?: "", g.notes ?: "", g.favourite)
    constructor(fields: JsonObject) : this(
        name = WardrobeDraftValidation.text(fields, "name", required = true), category = WardrobeDraftValidation.text(fields, "category", required = true),
        availability = WardrobeDraftValidation.text(fields, "availability", "ready"), subtype = WardrobeDraftValidation.text(fields, "subtype"),
        colours = WardrobeDraftValidation.values(fields, "colours").joinToString(", "), warmth = WardrobeDraftValidation.text(fields, "warmth", "unknown"),
        seasons = WardrobeDraftValidation.values(fields, "seasons").joinToString(", "), formality = WardrobeDraftValidation.text(fields, "formality"),
        material = WardrobeDraftValidation.text(fields, "material"), brand = WardrobeDraftValidation.text(fields, "brand"), notes = WardrobeDraftValidation.text(fields, "notes"),
        favourite = fields["favourite"]?.let { checkNotNull((it as? JsonPrimitive)?.booleanOrNull) { "Invalid favourite value." } } ?: false,
    )
    fun fields(): JsonObject {
        require(name.trim().isNotEmpty()) { "Give this garment a name." }
        val strings = mapOf("name" to name.trim(), "subtype" to subtype, "formality" to formality, "material" to material, "brand" to brand, "notes" to notes)
        WardrobeDraftValidation.strings(strings)
        require(category in WardrobeVocabulary.categories && availability in WardrobeVocabulary.availability && warmth in WardrobeDraftValidation.warmths) { "Choose valid garment details." }
        return buildJsonObject {
            strings.forEach { (key, value) -> put(key, value) }
            put("category", category); put("availability", availability); put("warmth", warmth); put("favourite", favourite)
            put("colours", JsonArray(WardrobeDraftValidation.list(colours).map(::JsonPrimitive)))
            put("seasons", JsonArray(WardrobeDraftValidation.list(seasons).map(::JsonPrimitive)))
        }
    }
}
@Serializable data class WardrobeSelection(val id: String, val name: String, val role: String) {
    fun fields() = buildJsonObject { put("garment_id", id); put("role", role) }
}
@Serializable data class WardrobeOutfitDraft(
    val day: String = LocalDate.now().toString(), val timeZone: String = ZoneId.systemDefault().id,
    val state: String = "planned", val label: String = "", val occasion: String = "", val notes: String = "",
    val items: List<WardrobeSelection> = emptyList(),
    val source: String = "manual",
) {
    constructor(o: WardrobeOutfit) : this(o.day, o.timeZone, o.state, o.label ?: "", o.occasion ?: "", o.notes ?: "",
        o.items.map { WardrobeSelection(it.garmentID, it.snapshot?.name ?: "Garment", it.role) })
    constructor(fields: JsonObject) : this(
        day = WardrobeDraftValidation.text(fields, "day", required = true).also { require(it.length == 10 && LocalDate.parse(it).toString() == it) { "Invalid queued outfit date." } },
        timeZone = WardrobeDraftValidation.text(fields, "time_zone", required = true), state = WardrobeDraftValidation.text(fields, "state", "planned"),
        label = WardrobeDraftValidation.text(fields, "label"), occasion = WardrobeDraftValidation.text(fields, "occasion"), notes = WardrobeDraftValidation.text(fields, "notes"),
        items = checkNotNull(fields["items"] as? JsonArray) { "Invalid queued outfit pieces." }.map {
            val piece = checkNotNull(it as? JsonObject) { "Invalid queued outfit piece." }
            val id = WardrobeDraftValidation.text(piece, "garment_id", required = true).also { require(WardrobeMediaPath.path(it) != null) { "Invalid queued outfit piece." } }
            WardrobeSelection(id, "Garment · ${id.take(8)}", WardrobeDraftValidation.text(piece, "role", required = true))
        }.also { require(it.size <= 30 && it.map { piece -> piece.id }.distinct().size == it.size) { "Invalid queued outfit pieces." } }, source = WardrobeDraftValidation.text(fields, "source", "manual"),
    )
    fun fields(): JsonObject {
        WardrobeDraftValidation.strings(mapOf("label" to label, "occasion" to occasion, "notes" to notes))
        val zone = runCatching { ZoneId.of(timeZone) }.getOrNull()
        require(zone != null && (timeZone == "UTC" || timeZone in ZoneId.getAvailableZoneIds())) { "Use an IANA time zone such as America/Los_Angeles." }
        require(state in listOf("planned", "worn")) { "Choose a planned or worn outfit." }
        val date = runCatching { LocalDate.parse(day) }.getOrNull()
        require(date != null && day.length == 10 && date.year in 1..9999 && date.toString() == day) { "Use a date in YYYY-MM-DD format, between years 1 and 9999." }
        require(state != "worn" || date <= LocalDate.now(zone)) { "Future outfits can be planned, but cannot be recorded worn." }
        require(items.size in 1..30 && items.map { it.id }.distinct().size == items.size && items.all { it.role in WardrobeDraftValidation.roles && it.id != "00000000-0000-0000-0000-000000000000" && runCatching { UUID.fromString(it.id).toString() == it.id.lowercase() }.getOrDefault(false) }) { "Choose 1–30 different garments and a role for each." }
        return buildJsonObject {
            put("day", day); put("time_zone", timeZone); put("label", label); put("occasion", occasion); put("notes", notes)
            put("items", JsonArray(items.map { it.fields() }))
        }
    }
}
object WardrobeDraftValidation {
    val roles = listOf("base", "mid", "bottom", "one_piece", "outer", "feet", "accessory", "other")
    val warmths = listOf("unknown", "light", "mid", "warm")
    fun text(fields: JsonObject, key: String, fallback: String = "", required: Boolean = false): String {
        val value = fields[key] ?: return fallback.also { check(!required) { "Missing queued $key value." } }
        check(value is JsonPrimitive && value.isString) { "Invalid queued $key value." }
        return value.content
    }
    fun values(fields: JsonObject, key: String): List<String> {
        val value = fields[key] ?: return emptyList()
        check(value is JsonArray) { "Invalid queued $key values." }
        return value.map { check(it is JsonPrimitive && it.isString) { "Invalid queued $key value." }; it.content }
    }
    fun strings(fields: Map<String, String>) = fields.forEach { (key, value) ->
        val limit = if (key == "notes") 4000 else 100
        require(value.toByteArray(Charsets.UTF_8).size <= limit) { "${WardrobeVocabulary.title(key)} is too long (maximum $limit UTF-8 bytes)." }
    }
    fun list(value: String): List<String> {
        val items = value.split(',').map { it.trim() }.filter { it.isNotEmpty() }
        require(items.size <= 10 && items.distinct().size == items.size && items.all { it.toByteArray(Charsets.UTF_8).size <= 100 }) { "Use up to 10 different comma-separated values, each at most 100 UTF-8 bytes." }
        return items
    }
    fun patch(fields: JsonObject, original: JsonObject) = JsonObject(fields.filter { (key, value) -> original[key] != value })
    fun edit(id: String, version: Long) = buildJsonObject { put("id", id); put("expected_version", version) }
    fun role(category: String) = mapOf("top" to "base", "bottom" to "bottom", "one_piece" to "one_piece", "outerwear" to "outer", "footwear" to "feet", "accessory" to "accessory")[category] ?: "other"
}
