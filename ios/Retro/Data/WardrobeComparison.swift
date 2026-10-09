import Foundation

struct WardrobeComparison: Identifiable {
    struct Candidate: Identifiable {
        let option: WardrobeSuggestion
        let draft: WardrobeOutfitDraft
        var id: String { option.id }
    }
    let id = UUID()
    let query: WardrobeSuggestQuery
    let candidates: [Candidate]
    let sharedIDs: Set<String>
    init(query: WardrobeSuggestQuery, options: [WardrobeSuggestion], drafts: [String: WardrobeOutfitDraft]) throws {
        try query.validate()
        guard (2...3).contains(options.count), Set(options.map(\.id)).count == options.count else { throw WardrobeWriteError("Refresh at least two different options to compare.") }
        self.query = query
        candidates = try options.map { option in
            guard !option.id.isEmpty, let draft = drafts[option.id], WardrobeVocabulary.dayKey(draft.date) == query.day, draft.occasion == query.occasion,
                  draft.state == "planned", draft.source == "suggestion", draft.items.count == option.items.count,
                  Set(option.items.map(\.garmentID)).count == option.items.count, option.items.allSatisfy({ $0.version > 0 }),
                  option.items.allSatisfy({ item in draft.items.contains { $0.id == item.garmentID && $0.role == item.role } }),
                  Set(query.requiredIDs).isSubset(of: Set(draft.items.map(\.id))), Set(query.excludedIDs).isDisjoint(with: draft.items.map(\.id)),
                  !query.excludedCombinations.contains(option.id) else { throw WardrobeWriteError("An option needs a fresh garment review before comparison.") }
            _ = try draft.fields()
            return Candidate(option: option, draft: draft)
        }
        sharedIDs = candidates.dropFirst().reduce(Set(candidates[0].draft.items.map(\.id))) { $0.intersection($1.draft.items.map(\.id)) }
    }
}
