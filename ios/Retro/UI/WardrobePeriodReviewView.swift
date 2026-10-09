import SwiftUI

struct WardrobePeriodReviewView: View {
    let store: WardrobeStore
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var analysis = WardrobeRead<WardrobeAnalysis>()
    @State private var records = WardrobeRead<WardrobePage<WardrobeOutfit>>()
    @State private var summary: String?
    @State private var revision = 0
    private var query: WardrobeAnalysisQuery { WardrobeAnalysisQuery(from: WardrobeVocabulary.dayKey(from), to: WardrobeVocabulary.dayKey(to)) }
    var body: some View {
        List {
            Section("Period") {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("Through", selection: $to, displayedComponents: .date)
                Button("Refresh review") { Task { await load() } }.disabled(analysis.loading || records.loading)
            }
            Section("Review") {
                WardrobeReadStatus(state: analysis) { await load() }
                if let summary { Text(summary) }
                Text("Counts include archived garments and use current categories. Unworn means no confirmed wear in these dates. Plans and pending saves are excluded.").font(.footnote)
                if let value = analysis.value, summary != nil {
                    ForEach(value.categories) { category in
                        Text("\(WardrobeVocabulary.title(category.category)): \(category.wornGarments) of \(category.garments) worn, \(category.wearEvents) garment wear events.").font(.subheadline)
                    }
                }
            }
            Section("Source · confirmed outfit records") {
                Text("Open a record to inspect its saved garment facts. Counts come from the server for the whole period; this list loads in pages. Counts and records have separate freshness indicators.").font(.footnote)
                WardrobeReadStatus(state: records) { await loadRecords(more: false) }
                ForEach(records.value?.items ?? []) { outfit in
                    NavigationLink { WardrobeOutfitDetail(store: store, initial: outfit) } label: {
                        VStack(alignment: .leading) {
                            Text(outfit.day + " · " + (outfit.label ?? "Outfit"))
                            Text(outfit.items.map { $0.snapshot?.name ?? $0.garmentID }.joined(separator: ", ")).font(.caption)
                        }
                    }
                }
                if records.value?.items.isEmpty == true { Text("No confirmed outfit records in this period.") }
                if records.value?.nextCursor != nil { Button("Load older source records") { Task { await loadRecords(more: true) } }.disabled(records.loading) }
            }
        }
        .navigationTitle("Wardrobe review").navigationBarTitleDisplayMode(.inline)
        .task(id: query) { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        revision += 1; let ticket = revision; let input = query
        analysis = WardrobeRead(); records = WardrobeRead(); summary = nil
        do { try input.validatePeriod() } catch { analysis.problem = error.localizedDescription; return }
        analysis.loading = true
        var result: WardrobeRead<WardrobeAnalysis> = await store.read("wardrobe_analyze", input: input)
        guard store.isCurrentOwner, !Task.isCancelled, ticket == revision, input == query else { return }
        do { if let value = result.value { summary = try value.periodSummary(input) } }
        catch { result.value = nil; result.problem = error.localizedDescription }
        analysis = result
        await loadRecords(more: false)
    }
    private func loadRecords(more: Bool) async {
        let period = query; let ticket = revision
        do { try period.validatePeriod() } catch { records = WardrobeRead(problem: error.localizedDescription); return }
        guard !records.loading else { return }
        let previous = records
        var input = WardrobeHistoryQuery(); input.from = period.from; input.to = period.to; input.limit = 20
        input.cursor = more ? previous.value?.nextCursor : nil
        records.loading = true
        var result: WardrobeRead<WardrobePage<WardrobeOutfit>> = await store.read("outfits_list", input: input)
        guard store.isCurrentOwner, !Task.isCancelled, ticket == revision, period == query else { return }
        if let page = result.value, page.items.contains(where: { $0.state != "worn" || $0.day < period.from || $0.day > period.to || WardrobeMediaPath.path(id: $0.id) == nil }) { result.value = nil; result.problem = "Source records do not match this period. Refresh." }
        if more, let page = result.value {
            let old = previous.value?.items ?? []; let ids = Set(old.map(\.id))
            result.value = WardrobePage(items: old + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
            result.cached = result.cached || previous.cached
        } else if more, result.value == nil { result.value = previous.value; result.cached = previous.cached }
        records = result
    }
}
