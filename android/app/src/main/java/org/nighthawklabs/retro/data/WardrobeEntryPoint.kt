package org.nighthawklabs.retro.data

import java.util.UUID

data class WardrobeEntryRequest(val action: String, val query: String = "", val id: String = UUID.randomUUID().toString()) {
    companion object {
        const val ADD = "org.nighthawklabs.retro.ADD_GARMENT"
        const val SEARCH = "org.nighthawklabs.retro.SEARCH_WARDROBE"
        const val TODAY = "org.nighthawklabs.retro.TODAY_OUTFITS"
        fun parse(action: String?, query: String?): WardrobeEntryRequest? {
            if (action !in listOf(ADD, SEARCH, TODAY)) return null
            val text = query ?: ""
            if (text.toByteArray(Charsets.UTF_8).size > 100 || text.any { it.isISOControl() } || (action != SEARCH && text.isNotEmpty())) return null
            return WardrobeEntryRequest(action!!, text)
        }
    }
}
