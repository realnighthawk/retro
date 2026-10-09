package org.nighthawklabs.retro.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable data class WardrobeCare(
    val wash_method: String = "unknown", val max_temp_c: Int? = null, val cycle: String = "unknown",
    val colour_group: String = "unknown", val drying: String = "unknown", val source: String = "manual",
    val evidence: String? = null, val confirmed: Boolean = false,
)
@Serializable data class WardrobeMachinePreset(val id: String, val name: String, val temperature_c: Int, val cycle: String, val drying: String)
@Serializable data class WardrobePreferences(
    val id: String, val version: Long, val updated_at: String,
    val preferred_colours: List<String>, val avoided_colours: List<String>, val preferred_styles: List<String>,
    val default_occasion: String, val temperature_unit: String, val temperature_sensitivity: String,
    val cold_threshold_c: Int, val hot_threshold_c: Int, val layering_preference: String,
    val avoid_repeat_days: Int, val prefer_underused_items: Boolean, val variety: String,
    val machine_presets: List<WardrobeMachinePreset> = emptyList(),
)
@Serializable data class WardrobePreferencesResult(val preferences: WardrobePreferences)
@Serializable data class WardrobeFeedback(
    val id: String, val outfit_id: String, val outfit_version: Long, val version: Long,
    val rating: Int? = null, val comfort_rating: Int? = null, val style_rating: Int? = null,
    val warmth: String, val comment: String? = null, val updated_at: String? = null,
)
@Serializable data class WardrobeFeedbackResult(val feedback: WardrobeFeedback, val current_outfit_version: Long, val outfit_state: String)
@Serializable class WardrobeEmpty
@Serializable data class WardrobeContextInput(val request_id: String, val garment_ids: List<String> = emptyList(), val outfit_ids: List<String> = emptyList())
@Serializable data class WardrobeContextSource(val entity_type: String, val id: String, val version: Long, val updated_at: String? = null)
@Serializable data class WardrobeContext(
    val schema_version: Int, val request_id: String, val retrieved_at: String, val coverage: String,
    val capabilities: List<String>, val preferences: WardrobePreferences, val garments: List<WardrobeGarment>,
    val outfits: List<WardrobeOutfit>, val feedback: List<WardrobeFeedbackResult>, val sources: List<WardrobeContextSource>,
)

object WardrobeSettingFields {
    fun label(key: String) = mapOf("cold_threshold_c" to "Cold threshold (°C)", "hot_threshold_c" to "Hot threshold (°C)", "max_temp_c" to "Maximum wash temperature (°C)", "temperature_c" to "Wash temperature (°C)", "avoid_repeat_days" to "Days before repeating", "evidence" to "Label instructions", "confirmed" to "I reviewed these care instructions")[key] ?: WardrobeVocabulary.title(key)
    val preferences = listOf("preferred_colours", "avoided_colours", "preferred_styles", "default_occasion", "temperature_unit", "temperature_sensitivity", "cold_threshold_c", "hot_threshold_c", "layering_preference", "avoid_repeat_days", "prefer_underused_items", "variety")
    val care = listOf("wash_method", "max_temp_c", "cycle", "colour_group", "drying", "source", "evidence", "confirmed")
    val feedback = listOf("rating", "comfort_rating", "style_rating", "warmth", "comment")
    val preset = listOf("name", "temperature_c", "cycle", "drying")
    val lists = setOf("preferred_colours", "avoided_colours", "preferred_styles")
    val booleans = setOf("prefer_underused_items", "confirmed")
    val ranges = mapOf("cold_threshold_c" to -20..30, "hot_threshold_c" to 10..45, "avoid_repeat_days" to 0..30, "max_temp_c" to 0..95, "temperature_c" to 0..95, "rating" to 1..5, "comfort_rating" to 1..5, "style_rating" to 1..5)
    val choices = mapOf(
        "temperature_unit" to listOf("celsius", "fahrenheit"), "temperature_sensitivity" to listOf("low", "normal", "high"),
        "layering_preference" to listOf("minimal", "moderate", "heavy"), "variety" to listOf("low", "moderate", "high"),
        "wash_method" to listOf("unknown", "machine", "hand", "dry_clean", "do_not_wash"), "cycle" to listOf("unknown", "normal", "gentle", "delicate"),
        "colour_group" to listOf("unknown", "white", "light", "dark", "separate"), "drying" to listOf("unknown", "line", "flat", "tumble_low", "tumble_normal", "do_not_tumble", "professional"),
        "source" to listOf("manual", "label"), "warmth" to listOf("unknown", "too_cold", "comfortable", "too_warm"),
    )
    fun patch(values: JsonObject, keys: List<String>) = JsonObject(keys.associateWith { values[it] ?: JsonNull })
    fun validate(values: JsonObject, keys: List<String>) {
        keys.forEach { key -> ranges[key]?.let { range ->
            val v = values[key]
            if (v == null || v == JsonNull) check(key in listOf("max_temp_c", "rating", "comfort_rating", "style_rating")) { "Enter ${WardrobeVocabulary.title(key)}." }
            else check((v as? JsonPrimitive)?.intOrNull?.let { it in range } == true) { "${WardrobeVocabulary.title(key)} must be between ${range.first} and ${range.last}." }
        } }
        val cold = (values["cold_threshold_c"] as? JsonPrimitive)?.intOrNull
        val hot = (values["hot_threshold_c"] as? JsonPrimitive)?.intOrNull
        if (cold != null && hot != null) check(cold < hot) { "Cold threshold must be lower than hot threshold." }
        lists.filter { it in keys }.forEach { key ->
            val list = (values[key] as? JsonArray)?.map { it.jsonPrimitive.content } ?: error("Use a list for ${label(key)}.")
            check(list.size <= 10 && list.all { it.isNotEmpty() && it.toByteArray(Charsets.UTF_8).size <= 100 } && list.map { it.lowercase() }.toSet().size == list.size) { "Use up to ten unique, short values for ${label(key)}." }
        }
        if ("wash_method" in keys) {
            val method = values["wash_method"]?.jsonPrimitive?.content ?: "unknown"
            val cycle = values["cycle"]?.jsonPrimitive?.content ?: "unknown"
            val temp = (values["max_temp_c"] as? JsonPrimitive)?.intOrNull
            if (method in listOf("dry_clean", "do_not_wash")) check(temp == null && cycle == "unknown") { "Clear wash temperature and cycle for non-wash care." }
            if ((values["confirmed"] as? JsonPrimitive)?.booleanOrNull == true) check(method != "unknown" && (method !in listOf("machine", "hand") || temp != null) && (method != "machine" || cycle != "unknown")) { "Review wash method, temperature and cycle before confirming care." }
            if ((values["source"] as? JsonPrimitive)?.content == "label") check((values["evidence"] as? JsonPrimitive)?.contentOrNull?.isNotBlank() == true) { "Enter readable label instructions." }
        }
    }
}
