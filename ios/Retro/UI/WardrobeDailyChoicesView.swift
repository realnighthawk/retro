import SwiftUI

struct WardrobeDailyChoicesView: View {
    let store: WardrobeStore
    let day: String
    let refresh: Int
    @State private var read = WardrobeRead<WardrobeSuggestions>()
    @State private var reviewing = false
    @State private var problem: String?
    @State private var seed: WardrobeOutfitSeed?
    @State private var reviewTask: Task<Void, Never>?
    @State private var swapQuery: WardrobeSuggestQuery?
    @State private var swapPieces: [WardrobeSelection] = []
    @State private var assistance: WardrobeCandidateContext?
    private var query: WardrobeSuggestQuery { WardrobeSuggestQuery(day: day) }
    private var loadID: String { "\(day):\(refresh):\(store.changes)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WardrobeScheduledChoicesView(store: store, day: day, refresh: refresh)
            Text("Outfit choices").font(.title3)
            Text("Suggestions for \(day). Your saved plans and recorded wears stay separate.").font(.footnote).foregroundStyle(.secondary)
            WardrobeReadStatus(state: read) { await load() }
            if let value = read.value {
                if let source = value.preferencesSource { Text("Wardrobe settings · version \(source.version)").font(.caption).foregroundStyle(.secondary) }
                if let occasion = value.effectiveOccasion, !occasion.isEmpty { Text("Occasion: " + occasion).font(.footnote) }
                if value.items.isEmpty { Text(value.noResultReason ?? "No choices are available. Review settings or compose manually.").font(.footnote) }
                Button("Help me choose or swap on this device") {
                    do { assistance = try WardrobeCandidateContext(input: query, result: value, revision: store.changes, cached: read.cached) }
                    catch { problem = error.localizedDescription }
                }.frame(minHeight: 44).disabled(reviewing || read.loading || read.cached)
                ForEach(Array(value.items.enumerated()), id: \.element.id) { index, option in
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Option \(index + 1)").font(.headline)
                            ForEach(option.items, id: \.garmentID) { item in
                                Text(item.name ?? WardrobeVocabulary.title(item.role))
                            }
                            if !option.missingRoles.isEmpty {
                                Text("Add missing pieces: " + option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("Why these pieces?") {
                                ForEach(Array(option.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).font(.footnote) }
                            }
                            Button("Review as a plan") { review(option, result: value) }.frame(minHeight: 44).disabled(reviewing || read.loading)
                            let pieces = option.items.map { WardrobeSelection(id: $0.garmentID, name: $0.name ?? WardrobeVocabulary.title($0.role), role: $0.role) }
                            Menu("Swap a piece") {
                                ForEach(pieces) { piece in
                                    Button("Swap \(piece.name)") {
                                        do { let input = try option.swapping(piece, query: value.reviewQuery(query, cached: read.cached)); swapPieces = pieces; swapQuery = input }
                                        catch { problem = error.localizedDescription }
                                    }
                                }
                            }.frame(minHeight: 44).disabled(reviewing || read.loading)
                        }
                    }
                }
                ForEach(Array((value.warnings ?? []).enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if let date = GatewayAgentResult.date(value.generatedAt) { Text("Generated \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            if reviewing { ProgressView("Checking current pieces and settings") }
            if let problem { Text(problem).font(.footnote).foregroundStyle(.secondary) }
            NavigationLink("More choices, locks and alternatives") { WardrobeSuggestionsView(store: store, day: day) }.frame(minHeight: 44)
        }
        .task(id: loadID) { await load() }
        .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
        .sheet(item: $assistance) { context in
            WardrobeCandidateAssistanceView(store: store, context: context,
                current: { query == context.input && !read.loading && !read.cached && read.value?.generatedAt == context.result.generatedAt },
                onSwap: { input, pieces in swapPieces = pieces; swapQuery = input })
        }
        .navigationDestination(item: $swapQuery) { input in
            WardrobeSuggestionsView(store: store, day: input.day, initialQuery: input, pieces: swapPieces)
        }
        .onChange(of: loadID) { _, _ in reviewTask?.cancel() }
        .onDisappear { reviewTask?.cancel() }
    }

    private func load() async {
        let id = loadID; let input = query
        read.loading = true; problem = nil
        let result: WardrobeRead<WardrobeSuggestions> = await store.read("wardrobe_suggest", input: input)
        guard id == loadID, !Task.isCancelled, store.isCurrentOwner else { return }
        do {
            if let value = result.value { _ = try value.reviewQuery(input, cached: result.cached) }
            read = result
        } catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
    private func review(_ option: WardrobeSuggestion, result: WardrobeSuggestions) {
        guard !reviewing else { return }
        let id = loadID
        reviewing = true; problem = nil
        reviewTask = Task {
            defer { reviewing = false }
            do {
                let input = try result.reviewQuery(query, cached: read.cached)
                let draft = try await store.reviewSuggestion(option, query: input)
                guard id == loadID, !Task.isCancelled, store.isCurrentOwner else { return }
                seed = WardrobeOutfitSeed(draft: draft)
            } catch { if id == loadID, store.isCurrentOwner { problem = error.localizedDescription } }
        }
    }
}
