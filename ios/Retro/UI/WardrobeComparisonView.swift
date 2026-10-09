import SwiftUI

struct WardrobeComparisonView: View {
    let store: WardrobeStore
    let comparison: WardrobeComparison
    let currentQuery: () -> WardrobeSuggestQuery
    var candidateContext: WardrobeCandidateContext? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var problem: String?
    @State private var seed: WardrobeOutfitSeed?
    @State private var task: Task<Void, Never>?
    @State private var assisting = false
    @State private var swapQuery: WardrobeSuggestQuery?
    @State private var swapPieces: [WardrobeSelection] = []
    var body: some View {
        NavigationStack {
            List {
                Section("Your request") {
                    Text("For \(comparison.query.day)")
                    if !comparison.query.occasion.isEmpty { Text("Occasion: " + comparison.query.occasion) }
                    if !comparison.query.warmth.isEmpty { Text("Warmth: " + WardrobeVocabulary.title(comparison.query.warmth)) }
                    Text("Compare real pieces and the engine's reasons. Warmth and occasion use saved tags; weather and fit are not assessed.").font(.footnote)
                    Text("\(comparison.sharedIDs.count) pieces appear in every option.").font(.footnote)
                    if let context = candidateContext, context.result.items.map(\.id) == comparison.candidates.map(\.id) {
                        Button("Explain or adjust these choices on this device") { assisting = true }.frame(minHeight: 44).disabled(busy)
                    }
                    if busy { ProgressView("Refreshing your choice") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                ForEach(Array(comparison.candidates.enumerated()), id: \.element.id) { index, candidate in
                    Section("Option \(index + 1)") {
                        ForEach(candidate.draft.items) { piece in
                            VStack(alignment: .leading) {
                                Text(piece.name)
                                Text(WardrobeVocabulary.title(piece.role) + " · " + (comparison.sharedIDs.contains(piece.id) ? "In every option" : "Varies between options")).font(.footnote)
                            }
                        }
                        ForEach(Array(candidate.option.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.footnote) }
                        if !candidate.option.missingRoles.isEmpty { Text("Missing roles: " + candidate.option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")).font(.footnote) }
                        Button("Review option \(index + 1)") { choose(candidate.option) }.frame(minHeight: 44).disabled(busy)
                    }
                }
            }.navigationTitle("Compare outfits").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
                .sheet(isPresented: $assisting) {
                    if let context = candidateContext {
                        WardrobeCandidateAssistanceView(store: store, context: context,
                            current: { currentQuery() == context.query && context.query == comparison.query },
                            onSwap: { input, pieces in swapPieces = pieces; swapQuery = input })
                    }
                }
                .navigationDestination(item: $swapQuery) { input in WardrobeSuggestionsView(store: store, day: input.day, initialQuery: input, pieces: swapPieces) }
        }.onDisappear { task?.cancel() }
    }
    private func choose(_ option: WardrobeSuggestion) {
        guard currentQuery() == comparison.query else { problem = "Your request changed. Generate and compare fresh options."; return }
        busy = true; problem = nil
        task = Task {
            defer { busy = false }
            do {
                let draft = try await store.reviewSuggestion(option, query: comparison.query)
                guard !Task.isCancelled, store.isCurrentOwner, currentQuery() == comparison.query else { return }
                seed = WardrobeOutfitSeed(draft: draft)
            } catch { if !Task.isCancelled, store.isCurrentOwner { problem = error.localizedDescription } }
        }
    }
}
