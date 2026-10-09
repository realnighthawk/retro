package org.nighthawklabs.retro.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import java.util.UUID

@Serializable data class WardrobeMedia(
    val id: String, val version: Long, val checksum: String,
    @SerialName("size_bytes") val sizeBytes: Long,
    @SerialName("mime_type") val mimeType: String,
    val state: String, val width: Int? = null, val height: Int? = null, val error: String? = null,
    @SerialName("upload_path") val uploadPath: String,
    @SerialName("display_path") val displayPath: String? = null,
    @SerialName("thumbnail_path") val thumbnailPath: String? = null,
)
@Serializable data class WardrobeMediaResult(val media: WardrobeMedia)
object WardrobeMediaPath {
    // Construct known paths under the configured origin; server-supplied URLs never receive credentials.
    fun path(id: String, variant: String? = null): String? {
        if (id == "00000000-0000-0000-0000-000000000000" || runCatching { UUID.fromString(id).toString() == id.lowercase() }.getOrDefault(false).not() || (variant != null && variant !in listOf("display", "thumbnail"))) return null
        return "/media/${id.lowercase()}/content" + (variant?.let { "?variant=$it" } ?: "")
    }
}
