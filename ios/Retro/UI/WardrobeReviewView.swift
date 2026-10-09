import SwiftUI

private struct WardrobeOutfitSeed: Identifiable { let id = UUID(); let draft: WardrobeOutfitDraft }

struct WardrobeSuggestionsView: View {
    let store: WardrobeStore
    let day: String
    @State private var occasion = ""
    @State private var warmth = ""
    @State private var required: [WardrobeSelection] = []
    @State private var excluded: [WardrobeSelection] = []
    @State private var seen: [String] = []
    @State private var variant = 0
    @State private var choosingRequired = false
    @State private var choosingExcluded = false
    @State private var read = WardrobeRead<WardrobeSuggestions>()
    @State private var drafts: [String: WardrobeOutfitDraft] = [:]
    @State private var errors: [String: String] = [:]
    @State private var request = 0
    @State private var seed: WardrobeOutfitSeed?
    private var query: WardrobeSuggestQuery {
        WardrobeSuggestQuery(day: day, occasion: occasion, warmth: warmth, requiredIDs: required.map(\.id), excludedIDs: excluded.map(\.id), excludedCombinations: seen, variant: variant)
    }
    var body: some View {
        List {
            Section("Preferences") {
                Text("For \(day). Suggestions are unsaved choices. Review one before saving a plan or recording wear.").font(.footnote)
                TextField("Occasion or formality", text: $occasion)
                Picker("Warmth", selection: $warmth) {
                    Text("Any warmth").tag("")
                    ForEach(["light", "mid", "warm"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                }
                Button("Include pieces · \(required.count)/10") { choosingRequired = true }.frame(minHeight: 44)
                Text(required.map(\.name).joined(separator: ", ")).font(.footnote)
                Button("Exclude pieces · \(excluded.count)") { choosingExcluded = true }.frame(minHeight: 44)
                Text(excluded.map(\.name).joined(separator: ", ")).font(.footnote)
                Button("Generate suggestions") { seen = []; variant = 0; request += 1 }.disabled(read.loading)
                Text("Warmth and occasion prioritize saved tags. No weather is inferred.").font(.footnote)
            }
            WardrobeReadStatus(state: read) { await load() }
            if let result = read.value {
                if result.items.isEmpty { Text(result.noResultReason ?? "No eligible combinations. Compose an outfit manually.") }
                ForEach(result.items) { option in
                    Section("Option") {
                        if let draft = drafts[option.id] { Text(draft.items.map(\.name).joined(separator: ", ")).font(.headline) }
                        else { Text("\(option.items.count) pieces · refresh needed") }
                        ForEach(option.reasons, id: \.self) { Text($0).font(.footnote) }
                        if !option.missingRoles.isEmpty { Text("Incomplete coverage: \(option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")). You can add pieces in the editor.").font(.footnote) }
                        if let error = errors[option.id] { Text(error).foregroundStyle(Tok.stamp) }
                        Button("Review this outfit") {
                            let input = query
                            Task {
                                do {
                                    let draft = try await store.reviewSuggestion(option, query: input)
                                    guard input == query, store.isCurrentOwner, !Task.isCancelled else { return }
                                    seed = WardrobeOutfitSeed(draft: draft)
                                } catch { if input == query, store.isCurrentOwner { errors[option.id] = error.localizedDescription } }
                            }
                        }.frame(minHeight: 44).disabled(read.loading)
                    }
                }
                Button("Shuffle · different combinations") {
                    seen = Array(Set(seen + result.items.map(\.fingerprint))).sorted(); variant += 1; request += 1
                }.frame(minHeight: 44).disabled(read.loading || result.items.isEmpty || seen.count + result.items.count > 100 || variant >= 1000)
            }
        }
        .navigationTitle("Suggestions").navigationBarTitleDisplayMode(.inline)
        .task(id: request) { await load() }
        .onChange(of: occasion) { _, _ in reset() }
        .onChange(of: warmth) { _, _ in reset() }
        .onChange(of: required) { _, _ in reset() }
        .onChange(of: excluded) { _, _ in reset() }
        .sheet(isPresented: $choosingRequired) { WardrobeGarmentPicker(store: store, items: $required, historical: false, maximum: 10, onlyReady: true) }
        .sheet(isPresented: $choosingExcluded) { WardrobeGarmentPicker(store: store, items: $excluded, historical: false, maximum: 100) }
        .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
    }
    private func reset() { seen = []; variant = 0; read = WardrobeRead(); drafts = [:]; errors = [:] }
    private func load() async {
        let input = query
        do { try input.validate() } catch { read = WardrobeRead(problem: error.localizedDescription); return }
        read.loading = true; drafts = [:]; errors = [:]
        let result: WardrobeRead<WardrobeSuggestions> = await store.read("wardrobe_suggest", input: input)
        guard !Task.isCancelled, store.isCurrentOwner, input == query else { return }
        read = result
        for option in result.value?.items ?? [] {
            do {
                let draft = try await store.reviewSuggestion(option, query: input)
                guard !Task.isCancelled, store.isCurrentOwner, input == query else { return }
                drafts[option.id] = draft
            } catch {
                guard !Task.isCancelled, store.isCurrentOwner, input == query else { return }
                errors[option.id] = error.localizedDescription
            }
        }
    }
}

struct WardrobeInsightsView: View {
    let store: WardrobeStore
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var allTime = false
    @State private var read = WardrobeRead<WardrobeAnalysis>()
    private var query: WardrobeAnalysisQuery { WardrobeAnalysisQuery(from: allTime ? "" : WardrobeVocabulary.dayKey(from), to: allTime ? "" : WardrobeVocabulary.dayKey(to)) }
    var body: some View {
        List {
            Section("Period") {
                Toggle("All time", isOn: $allTime)
                if !allTime {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Through", selection: $to, displayedComponents: .date)
                }
            }
            WardrobeReadStatus(state: read) { await load() }
            if let value = read.value {
                Section("Confirmed wears") {
                    LabeledContent("Days worn", value: String(value.wearDays))
                    LabeledContent("Outfit events", value: String(value.outfitEvents))
                    Text("Several outfits on one day count as one wear day. Plans, void outfits and pending saves do not count.").font(.footnote)
                }
                Section("Wardrobe usage") {
                    LabeledContent("Garments", value: String(value.garments))
                    LabeledContent("Unworn in this period", value: String(value.unwornGarments))
                    Text("Includes archived garments. Categories reflect current inventory. Unworn means no confirmed wear in the selected period.").font(.footnote)
                }
                ForEach(value.categories) { category in
                    Section(WardrobeVocabulary.title(category.category)) {
                        LabeledContent("Garments", value: String(category.garments))
                        LabeledContent("Worn garments", value: String(category.wornGarments))
                        LabeledContent("Garment wear events", value: String(category.wearEvents))
                    }
                }
            }
        }.navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
            .task(id: query) { await load() }.refreshable { await load() }
    }
    private func load() async {
        let input = query
        guard input.from.isEmpty || input.from <= input.to else { read = WardrobeRead(problem: "From must not be after Through."); return }
        read = WardrobeRead(loading: true)
        let result: WardrobeRead<WardrobeAnalysis> = await store.read("wardrobe_analyze", input: input)
        if !Task.isCancelled, store.isCurrentOwner, input == query { read = result }
    }
}

struct WardrobeAuditView: View {
    let store: WardrobeStore
    let entityType: String
    let id: String
    @State private var read = WardrobeRead<WardrobePage<WardrobeChange>>()
    @State private var revision = 0
    var body: some View {
        List {
            Section { Text("Append-only record changes. This is separate from your outfit timeline.").font(.footnote) }
            WardrobeReadStatus(state: read) { await load(more: false) }
            if read.value?.items.isEmpty == true { Text("No record changes") }
            ForEach(read.value?.items ?? []) { change in
                Section(WardrobeVocabulary.title(change.operation)) {
                    Text(change.occurredAt).font(.footnote)
                    Text(change.details).textSelection(.enabled)
                }
            }
            if read.value?.nextCursor != nil { Button("Load older changes") { Task { await load(more: true) } }.disabled(read.loading) }
        }.navigationTitle("Record history").navigationBarTitleDisplayMode(.inline)
            .task { await load(more: false) }.refreshable { await load(more: false) }
    }
    private func load(more: Bool) async {
        revision += 1; let ticket = revision
        let previous = read.value
        let input = WardrobeAuditQuery(entityType: entityType, id: id, cursor: more ? previous?.nextCursor : nil)
        read.loading = true
        var result: WardrobeRead<WardrobePage<WardrobeChange>> = await store.read("history_list", input: input)
        guard !Task.isCancelled, store.isCurrentOwner, ticket == revision else { return }
        if more, let page = result.value {
            let old = previous?.items ?? []; let ids = Set(old.map(\.id))
            result.value = WardrobePage(items: old + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
        } else if more, result.value == nil { result.value = previous }
        read = result
    }
}
