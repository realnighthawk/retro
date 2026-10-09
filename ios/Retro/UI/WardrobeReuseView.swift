import SwiftUI

struct WardrobeOutfitSeed: Identifiable { let id = UUID(); let draft: WardrobeOutfitDraft }

struct WardrobeReuseView: View {
    let store: WardrobeStore
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var review: WardrobeReuseReview?
    @State private var replacements: [String: WardrobeSelection] = [:]
    @State private var omitted: Set<String> = []
    @State private var replacing: WardrobeReusePiece?
    @State private var seed: WardrobeOutfitSeed?
    @State private var busy = false
    @State private var problem: String?
    private var resolved: Bool {
        guard let review else { return false }
        return review.pieces.contains { !omitted.contains($0.id) } && review.pieces.allSatisfy { $0.problem == nil || omitted.contains($0.id) || replacements[$0.id] != nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Create a new plan from these pieces. Choose its date and review current garments. The original history stays intact.").font(.footnote)
                    DatePicker("New plan date", selection: $date, displayedComponents: .date)
                    if let review { Text("From \(review.outfit.day) · \(review.outfit.title)").font(.footnote) }
                    if busy { ProgressView("Refreshing pieces") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    Button("Refresh original and pieces") { Task { await load() } }.disabled(busy)
                }
                if let review {
                    ForEach(review.pieces) { piece in
                        Section(piece.name) {
                            Text(WardrobeVocabulary.title(piece.role)).font(.footnote)
                            if omitted.contains(piece.id) { Text("Removed from this new plan") }
                            else if let replacement = replacements[piece.id] { Text("Replacement: \(replacement.name)") }
                            else if let problem = piece.problem { Text("Needs review: \(problem)") }
                            else { Text("Ready · current garment") }
                            Button("Choose replacement") { replacing = piece }.frame(minHeight: 44).disabled(busy)
                            if omitted.contains(piece.id) { Button("Keep original piece") { omitted.remove(piece.id) }.frame(minHeight: 44).disabled(busy) }
                            else { Button("Remove from new plan", role: .destructive) { omitted.insert(piece.id); replacements[piece.id] = nil }.frame(minHeight: 44).disabled(busy) }
                        }
                    }
                }
            }.navigationTitle("Reuse outfit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Review plan") { Task { await compose() } }.disabled(busy || !resolved) }
                }
                .sheet(item: $replacing) { piece in
                    WardrobeGarmentPicker(store: store, items: Binding(get: { replacements[piece.id].map { [$0] } ?? [] }, set: {
                        replacements[piece.id] = $0.first
                        if !$0.isEmpty { omitted.remove(piece.id) }
                    }), historical: false, maximum: 1, onlyReady: true)
                }
                .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
                .task { await load() }
        }
    }
    private func load() async {
        busy = true; problem = nil
        defer { busy = false }
        do {
            let result = try await store.reuseOutfit(id)
            guard store.isCurrentOwner, !Task.isCancelled else { return }
            review = result; replacements = [:]; omitted = []
        } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
    }
    private func compose() async {
        guard let review else { return }
        busy = true; problem = nil
        let originalDate = date, originalReplacements = replacements, originalOmitted = omitted
        defer { busy = false }
        do {
            let draft = try review.plan(date: date, replacements: replacements, omitted: omitted)
            let fresh = try await store.refreshReusePlan(draft)
            guard store.isCurrentOwner, !Task.isCancelled, date == originalDate, replacements == originalReplacements, omitted == originalOmitted else { return }
            seed = WardrobeOutfitSeed(draft: fresh)
        } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
    }
}
