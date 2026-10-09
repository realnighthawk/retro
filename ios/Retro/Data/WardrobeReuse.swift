import Foundation

struct WardrobeReusePiece: Identifiable {
    let id: String
    let name: String
    let role: String
    let problem: String?
    var selection: WardrobeSelection { WardrobeSelection(id: id, name: name, role: role) }
}
struct WardrobeReuseReview {
    let outfit: WardrobeOutfit
    let pieces: [WardrobeReusePiece]
    func plan(date: Date, replacements: [String: WardrobeSelection], omitted: Set<String>) throws -> WardrobeOutfitDraft {
        guard Set(replacements.keys).isSubset(of: Set(pieces.map(\.id))), omitted.isSubset(of: Set(pieces.map(\.id))) else { throw WardrobeWriteError("Review the original outfit pieces first.") }
        var draft = WardrobeOutfitDraft(date: date)
        draft.label = outfit.label ?? ""; draft.occasion = outfit.occasion ?? ""
        draft.items = try pieces.compactMap { piece in
            if omitted.contains(piece.id) { return nil }
            if let replacement = replacements[piece.id] { return WardrobeSelection(id: replacement.id, name: replacement.name, role: piece.role) }
            guard piece.problem == nil else { throw WardrobeWriteError("Replace or remove \(piece.name) before reusing this outfit.") }
            return piece.selection
        }
        _ = try draft.fields()
        return draft
    }
}
