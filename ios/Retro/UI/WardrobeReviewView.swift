import SwiftUI

struct WardrobeSuggestionsView: View {
    let store: WardrobeStore
    let day: String
    @State private var occasion = ""
    @State private var warmth = ""
    @State private var swapRole: String?
    @State private var expectedPreferencesVersion: Int64?
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
    @State private var language: WardrobeLanguageContext?
    @State private var unhandled: [String] = []
    @State private var seed: WardrobeOutfitSeed?
    @State private var comparison: WardrobeComparison?
    @State private var assistance: WardrobeCandidateContext?
    @State private var assistedSwap: WardrobeSuggestQuery?
    @State private var temperature = ""
    @State private var rain = false
    @State private var assistedPieces: [WardrobeSelection] = []
    @State private var reviewTask: Task<Void, Never>?
    init(store: WardrobeStore, day: String, initialQuery: WardrobeSuggestQuery? = nil, pieces: [WardrobeSelection] = []) {
        self.store = store; self.day = day
        if let input = initialQuery {
            _occasion = State(initialValue: input.occasion); _warmth = State(initialValue: input.warmth)
            _swapRole = State(initialValue: input.swapRole)
            _expectedPreferencesVersion = State(initialValue: input.expectedPreferencesVersion)
            _seen = State(initialValue: input.excludedCombinations); _variant = State(initialValue: input.variant)
            _required = State(initialValue: input.requiredIDs.map { id in pieces.first { $0.id == id } ?? WardrobeSelection(id: id, name: "Locked piece", role: "other") })
            _excluded = State(initialValue: input.excludedIDs.map { id in pieces.first { $0.id == id } ?? WardrobeSelection(id: id, name: "Excluded piece", role: "other") })
        }
    }
    private var temperatureC: Int? { Int(temperature.trimmingCharacters(in: .whitespaces)).flatMap { (-60...60).contains($0) ? $0 : nil } }
    private var query: WardrobeSuggestQuery {
        var value = WardrobeSuggestQuery(day: day, occasion: occasion, warmth: warmth, requiredIDs: required.map(\.id), excludedIDs: excluded.map(\.id), excludedCombinations: seen, variant: variant, expectedPreferencesVersion: expectedPreferencesVersion, swapRole: swapRole)
        value.temperatureC = temperatureC
        value.precipitation = rain ? true : nil
        return value
    }
    // A reviewed forecast for this day, if the owner already retrieved one: the midpoint of the day's
    // range, or whichever end the provider gave. It is offered, never applied on its own.
    private var reviewedForecast: (low: Double?, high: Double?) {
        guard let context = store.assistant.outfitContext, context.weather?.day == day else { return (nil, nil) }
        return (context.weather?.lowC, context.weather?.highC)
    }
    private var reviewedTemperature: Int? {
        let (low, high) = reviewedForecast
        switch (low, high) {
        case let (low?, high?): return Int(((low + high) / 2).rounded())
        case let (low?, nil): return Int(low.rounded())
        case let (nil, high?): return Int(high.rounded())
        default: return nil
        }
    }
    private var reviewQuery: WardrobeSuggestQuery { (try? read.value?.reviewQuery(query, cached: read.cached)) ?? query }
    var body: some View {
        List {
            Section("Preferences") {
                Text("For \(day). Suggestions are unsaved choices. Review one before saving a plan or recording wear.").font(.footnote)
                Button("Describe an outfit") { language = WardrobeLanguageContext(suggestion: query, required: required, excluded: excluded) }.frame(minHeight: 44)
                ForEach(Array(unhandled.enumerated()), id: \.offset) { _, value in Text("Not applied: " + value).font(.footnote) }
                TextField("Occasion (empty uses saved default)", text: $occasion)
                Picker("Warmth", selection: $warmth) {
                    Text("Any warmth").tag("")
                    ForEach(["light", "mid", "warm"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                }
                HStack {
                    TextField("Weather in °C (optional)", text: $temperature).keyboardType(.numbersAndPunctuation)
                    if let reviewed = reviewedTemperature {
                        Button("Use \(reviewed)°C") { temperature = String(reviewed) }
                    }
                    if !temperature.isEmpty { Button("Clear") { temperature = "" } }
                }
                Toggle("Rain or snow expected", isOn: $rain)
                Text("A temperature is used only against each garment's recorded warmth, with your own cold/hot thresholds and sensitivity. Garments with no warmth tag stay neutral and are reported, and rain is disclosed rather than filtered, because no garment records water resistance.").font(.footnote)
                Button("Locked pieces · \(required.count)/10") { choosingRequired = true }.frame(minHeight: 44)
                Text(required.map(\.name).joined(separator: ", ")).font(.footnote)
                Button("Exclude pieces · \(excluded.count)") { choosingExcluded = true }.frame(minHeight: 44)
                Text(excluded.map(\.name).joined(separator: ", ")).font(.footnote)
                if let swapRole { Text("Replacing the \(WardrobeVocabulary.title(swapRole)) role; other pieces are locked.").font(.footnote) }
                Button("Clear locks and exclusions") { required = []; excluded = []; swapRole = nil; reset(); request += 1 }.frame(minHeight: 44).disabled(read.loading)
                Button("Generate suggestions") { expectedPreferencesVersion = nil; seen = []; variant = 0; request += 1 }.disabled(read.loading)
                Text("Uses saved preferences and explicit rated wears. Warmth and style match saved tags; weather is not inferred.").font(.footnote)
            }
            WardrobeReadStatus(state: read) { await load() }
            if let result = read.value {
                if let occasion = result.effectiveOccasion, !occasion.isEmpty { Text("Ranking occasion: " + occasion).font(.footnote) }
                ForEach(Array((result.warnings ?? []).enumerated()), id: \.offset) { _, warning in Text(warning).font(.footnote).foregroundStyle(.secondary) }
                if result.items.isEmpty { Text(result.noResultReason ?? "No eligible combinations. Compose an outfit manually.") }
                Button("Help me choose or swap on this device") {
                    do { assistance = try WardrobeCandidateContext(input: query, result: result, revision: store.changes, cached: read.cached) }
                    catch { read.problem = error.localizedDescription }
                }.frame(minHeight: 44).disabled(read.loading || read.cached)
                Button("Compare refreshed options") {
                    do { comparison = try WardrobeComparison(query: reviewQuery, options: result.items.filter { drafts[$0.id] != nil }, drafts: drafts) }
                    catch { read.problem = error.localizedDescription }
                }.frame(minHeight: 44).disabled(read.loading || drafts.count < 2)
                ForEach(result.items) { option in
                    Section("Option") {
                        if let draft = drafts[option.id] { Text(draft.items.map(\.name).joined(separator: ", ")).font(.headline) }
                        else { Text("\(option.items.count) pieces · refresh needed") }
                        ForEach(option.reasons, id: \.self) { Text($0).font(.footnote) }
                        if !option.missingRoles.isEmpty { Text("Incomplete coverage: \(option.missingRoles.map(WardrobeVocabulary.title).joined(separator: ", ")). You can add pieces in the editor.").font(.footnote) }
                        if let error = errors[option.id] { Text(error).foregroundStyle(Tok.stamp) }
                        if let draft = drafts[option.id] {
                            ForEach(draft.items) { piece in
                                HStack {
                                    Button {
                                        if required.contains(where: { $0.id == piece.id }) { required.removeAll { $0.id == piece.id } }
                                        else { if swapRole == piece.role { swapRole = nil }; required.append(piece) }
                                    } label: { Label(piece.name, systemImage: required.contains(where: { $0.id == piece.id }) ? "lock.fill" : "lock.open") }
                                    .frame(minHeight: 44).accessibilityLabel("\(required.contains(where: { $0.id == piece.id }) ? "Unlock" : "Lock") \(piece.name)")
                                    Spacer()
                                    Button("Swap") { swap(piece, option: option, pieces: draft.items) }.frame(minHeight: 44)
                                        .disabled(read.loading || required.contains(where: { $0.id == piece.id }))
                                }
                            }
                        }
                        Button("Review this outfit") {
                            let input = reviewQuery
                            reviewTask?.cancel()
                            reviewTask = Task {
                                do {
                                    let draft = try await store.reviewSuggestion(option, query: input)
                                    guard input == reviewQuery, store.isCurrentOwner, !Task.isCancelled else { return }
                                    seed = WardrobeOutfitSeed(draft: draft)
                                } catch { if input == reviewQuery, store.isCurrentOwner { errors[option.id] = error.localizedDescription } }
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
        .onChange(of: swapRole) { _, _ in reset() }
        .sheet(isPresented: $choosingRequired) { WardrobeGarmentPicker(store: store, items: $required, historical: false, maximum: 10, onlyReady: true) }
        .sheet(isPresented: $choosingExcluded) { WardrobeGarmentPicker(store: store, items: $excluded, historical: false, maximum: 100) }
        .sheet(item: $language) { context in
            WardrobeLanguageView(store: store, context: context) { draft, includes, excludes, limitations in
                guard context.suggestion == query else { throw WardrobeWriteError("The outfit constraints changed. Review a fresh interpretation.") }
                let input = try draft.outfitQuery(day: day, required: includes, excluded: excludes)
                occasion = input.occasion; warmth = input.warmth; required = includes; excluded = excludes; unhandled = limitations; reset()
            }
        }
        .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
        .sheet(item: $comparison) { value in
            WardrobeComparisonView(store: store, comparison: value, currentQuery: { reviewQuery },
                candidateContext: read.value.flatMap { try? WardrobeCandidateContext(input: query, result: $0, revision: store.changes, cached: read.cached) })
        }
        .sheet(item: $assistance) { context in
            WardrobeCandidateAssistanceView(store: store, context: context,
                current: { query == context.input && !read.loading && !read.cached && read.value?.generatedAt == context.result.generatedAt },
                onSwap: { input, pieces in assistedPieces = pieces; assistedSwap = input })
        }
        .navigationDestination(item: $assistedSwap) { input in WardrobeSuggestionsView(store: store, day: input.day, initialQuery: input, pieces: assistedPieces) }
        .onDisappear { reviewTask?.cancel() }
    }
    private func swap(_ piece: WardrobeSelection, option: WardrobeSuggestion, pieces: [WardrobeSelection]) {
        do {
            let input = try option.swapping(piece, query: reviewQuery)
            required = pieces.filter { input.requiredIDs.contains($0.id) }
            excluded.append(piece); swapRole = input.swapRole; seen = []; variant = 0; request += 1
        } catch { read.problem = error.localizedDescription }
    }
    private func reset() { reviewTask?.cancel(); expectedPreferencesVersion = nil; seen = []; variant = 0; read = WardrobeRead(); drafts = [:]; errors = [:] }
    private func load() async {
        let input = query
        do { try input.validate() } catch { read = WardrobeRead(problem: error.localizedDescription); return }
        read.loading = true; drafts = [:]; errors = [:]
        let result: WardrobeRead<WardrobeSuggestions> = await store.read("wardrobe_suggest", input: input)
        guard !Task.isCancelled, store.isCurrentOwner, input == query else { return }
        let resolved: WardrobeSuggestQuery
        do {
            guard let value = result.value else { read = result; return }
            resolved = try value.reviewQuery(input, cached: result.cached)
        } catch { read = WardrobeRead(problem: error.localizedDescription); return }
        read = result
        read.loading = true
        defer { if input == query { read.loading = false } }
        for option in result.value?.items ?? [] {
            do {
                let draft = try await store.reviewSuggestion(option, query: resolved)
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
