package org.nighthawklabs.retro.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class WardrobeGarment(
    val id: String,
    val version: Long,
    val name: String,
    val category: String,
    val availability: String,
    val subtype: String? = null,
    val colours: List<String> = emptyList(),
    val warmth: String? = null,
    val seasons: List<String> = emptyList(),
    val formality: String? = null,
    val material: String? = null,
    val brand: String? = null,
    val notes: String? = null,
    val favourite: Boolean = false,
    @SerialName("media_ids") val mediaIDs: List<String> = emptyList(),
    @SerialName("archived_at") val archivedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("wear_days") val wearDays: Long,
    @SerialName("wear_events") val wearEvents: Long,
    @SerialName("last_worn_on") val lastWornOn: String? = null,
    val care: WardrobeCare? = null,
)

@Serializable
data class WardrobeOutfit(
    val id: String,
    val version: Long,
    val day: String,
    @SerialName("time_zone") val timeZone: String,
    val state: String,
    val label: String? = null,
    val occasion: String? = null,
    val notes: String? = null,
    val source: String? = null,
    @SerialName("previous_state") val previousState: String? = null,
    @SerialName("confirmed_at") val confirmedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    val items: List<WardrobeOutfitItem>,
) {
    val title: String get() = label?.takeIf { it.isNotEmpty() } ?: "Outfit"
}

@Serializable
data class WardrobeOutfitItem(
    @SerialName("garment_id") val garmentID: String,
    val role: String,
    val snapshot: WardrobeGarment? = null,
)

@Serializable
data class WardrobePage<T>(val items: List<T>, @SerialName("next_cursor") val nextCursor: String? = null)
@Serializable data class WardrobeDay(val day: String, val outfits: List<WardrobeOutfit>)
@Serializable data class WardrobeGarmentResult(val garment: WardrobeGarment)
@Serializable data class WardrobeOutfitResult(val outfit: WardrobeOutfit)
@Serializable data class WardrobeID(val id: String)
@Serializable data class WardrobeDayQuery(val day: String)

@Serializable
data class WardrobeInventoryQuery(
    val search: String = "",
    val category: String = "",
    val availability: String = "",
    @SerialName("include_archived") val includeArchived: Boolean = false,
    val limit: Int = 50,
    val cursor: String? = null,
)
@Serializable data class WardrobeHistoryQuery(val state: String = "worn", val limit: Int = 50, val cursor: String? = null, val from: String = "", val to: String = "", @SerialName("garment_id") val garmentID: String = "")

object WardrobeVocabulary {
    val categories = listOf("top", "bottom", "one_piece", "outerwear", "footwear", "accessory", "other")
    val availability = listOf("ready", "needs_wash", "washing", "unavailable")
    fun title(value: String): String = value.replace('_', ' ').replaceFirstChar { it.titlecase() }
}
