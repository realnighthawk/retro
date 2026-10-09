package org.nighthawklabs.retro.data

data class WardrobeReusePiece(val id: String, val name: String, val role: String, val problem: String? = null) {
    val selection: WardrobeSelection get() = WardrobeSelection(id, name, role)
}
data class WardrobeReuseReview(val outfit: WardrobeOutfit, val pieces: List<WardrobeReusePiece>) {
    fun plan(day: String, replacements: Map<String, WardrobeSelection>, omitted: Set<String>): WardrobeOutfitDraft {
        val ids = pieces.map { it.id }.toSet()
        require(replacements.keys.all { it in ids } && omitted.all { it in ids }) { "Review the original outfit pieces first." }
        return WardrobeOutfitDraft(day = day, label = outfit.label.orEmpty(), occasion = outfit.occasion.orEmpty(), items = pieces.mapNotNull { piece ->
            if (piece.id in omitted) null
            else replacements[piece.id]?.copy(role = piece.role) ?: piece.selection.also { check(piece.problem == null) { "Replace or remove ${piece.name} before reusing this outfit." } }
        }).also { it.fields() }
    }
}
