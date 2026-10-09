package org.nighthawklabs.retro.data

class WardrobeComparison(val query: WardrobeSuggestQuery, options: List<WardrobeSuggestion>, drafts: Map<String, WardrobeOutfitDraft>) {
    data class Candidate(val option: WardrobeSuggestion, val draft: WardrobeOutfitDraft)
    val candidates: List<Candidate>
    val sharedIDs: Set<String>
    init {
        query.validate()
        require(options.size in 2..3 && options.map { it.fingerprint }.distinct().size == options.size) { "Refresh at least two different options to compare." }
        candidates = options.map { option ->
            val draft = drafts[option.fingerprint]
            require(option.fingerprint.isNotEmpty() && draft != null && draft.day == query.day && draft.occasion == query.occasion && draft.state == "planned" && draft.source == "suggestion" &&
                draft.items.size == option.items.size && option.items.map { it.garmentID }.distinct().size == option.items.size && option.items.all { it.version > 0 } &&
                option.items.all { item -> draft.items.any { it.id == item.garmentID && it.role == item.role } } && query.requiredIDs.all { id -> draft.items.any { it.id == id } } &&
                query.excludedIDs.none { id -> draft.items.any { it.id == id } } && option.fingerprint !in query.excludedCombinations) { "An option needs a fresh garment review before comparison." }
            draft.fields()
            Candidate(option, draft)
        }
        sharedIDs = candidates.drop(1).fold(candidates[0].draft.items.map { it.id }.toSet()) { common, candidate -> common.intersect(candidate.draft.items.map { it.id }.toSet()) }
    }
}
