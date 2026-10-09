package org.nighthawklabs.retro.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.json.*
import java.time.LocalDate

@Serializable data class WardrobeSuggestQuery(
    val day: String, val occasion: String = "", val warmth: String = "",
    @SerialName("required_ids") val requiredIDs: List<String> = emptyList(),
    @SerialName("excluded_ids") val excludedIDs: List<String> = emptyList(),
    @SerialName("excluded_combinations") val excludedCombinations: List<String> = emptyList(), val variant: Int = 0,
) {
    fun validate() {
        require(runCatching { LocalDate.parse(day).toString() == day }.getOrDefault(false) && day.length == 10 && occasion.toByteArray().size <= 100 && warmth in listOf("", "light", "mid", "warm") &&
            requiredIDs.size <= 10 && excludedIDs.size <= 100 && requiredIDs.none { it in excludedIDs } &&
            (requiredIDs + excludedIDs).all { WardrobeMediaPath.path(it) != null } && variant in 0..1000 && excludedCombinations.size <= 100) { "Review the date and suggestion constraints." }
    }
}
@Serializable data class WardrobeSuggestedItem(@SerialName("garment_id") val garmentID: String, val role: String, val version: Long)
@Serializable data class WardrobeSuggestion(val items: List<WardrobeSuggestedItem>, val fingerprint: String, val reasons: List<String>, @SerialName("missing_roles") val missingRoles: List<String>)
@Serializable data class WardrobeSuggestions(val day: String, val algorithm: String, @SerialName("generated_at") val generatedAt: String, val items: List<WardrobeSuggestion>, @SerialName("no_result_reason") val noResultReason: String? = null)
@Serializable data class WardrobeAnalysisQuery(val from: String = "", val to: String = "")
@Serializable data class WardrobeCategoryUsage(val category: String, val garments: Long, @SerialName("worn_garments") val wornGarments: Long, @SerialName("wear_events") val wearEvents: Long)
@Serializable data class WardrobeAnalysis(val from: String? = null, val to: String? = null, @SerialName("outfit_events") val outfitEvents: Long, @SerialName("wear_days") val wearDays: Long, val garments: Long, @SerialName("unworn_garments") val unwornGarments: Long, val categories: List<WardrobeCategoryUsage>)
@Serializable data class WardrobeAuditQuery(@SerialName("entity_type") val entityType: String, val id: String, val cursor: String? = null, val limit: Int = 50)
@Serializable data class WardrobeChange(val id: Long, val actor: String, val operation: String, val before: JsonElement, val after: JsonElement, @SerialName("occurred_at") val occurredAt: String) {
    val details: String get() {
        val old = before as? JsonObject; val new = after as? JsonObject
        return if (old == null || new == null) "Before: ${before.auditText}\nAfter: ${after.auditText}"
        else (old.keys + new.keys).sorted().filter { old[it] != new[it] }.joinToString("\n") { "${WardrobeVocabulary.title(it)}: ${old[it]?.auditText ?: "Empty"} → ${new[it]?.auditText ?: "Empty"}" }
    }
}
private val JsonElement.auditText: String get() = when (this) {
    JsonNull -> "Empty"
    is JsonPrimitive -> content
    is JsonArray -> joinToString(", ") { it.auditText }
    is JsonObject -> keys.sorted().joinToString("; ") { "${WardrobeVocabulary.title(it)}: ${getValue(it).auditText}" }
}
