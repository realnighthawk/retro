package org.nighthawklabs.retro.data

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable data class WardrobePhotoBytes(val id: String, val checksum: String, val size: Int)
@Serializable data class WardrobePhotoEdit(val id: String, val original: WardrobePhotoBytes, val chosen: WardrobePhotoBytes)
@Serializable data class WardrobePhotoDraft(val id: String, val garment: WardrobeGarment, val retained: List<String>, val photos: List<WardrobePhotoEdit>, val updatedAt: Long) {
    val sources: List<WardrobePhotoBytes> get() = photos.flatMap { listOf(it.original, it.chosen) }
}
@Serializable data class WardrobePhotoManifest(val version: Int, val batches: List<WardrobePhotoBatch>, val drafts: List<WardrobePhotoDraft>)
data class WardrobePreparedPhoto(val id: String = UUID.randomUUID().toString(), val original: ByteArray, val chosen: ByteArray)
