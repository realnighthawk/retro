import SwiftUI

struct WardrobePeriodReviewView: View {
    let store: WardrobeStore
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var analysis = WardrobeRead<WardrobeAnalysis>()
    @State private var records = WardrobeRead<WardrobePage<WardrobeOutfit>>()
    @State private var summary: String?
    @State private var revision = 0
    @State private var explanation: String?
    @State private var explainProblem: String?
    @State private var explaining = false
    @State private var explanationTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
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
                Text("Counts include archived garments and use current categories. Only confirmed wears count: unworn means no confirmed wear in these dates, while never worn means none at all on or before the end date. Saved choices, plans, views and pending saves are reported separately and are never wears.").font(.footnote)
                if let value = analysis.value, summary != nil {
                    ForEach(value.categories) { category in
                        Text("\(WardrobeVocabulary.title(category.category)): \(category.wornGarments) of \(category.garments) worn, \(category.wearEvents) garment wear events.").font(.subheadline)
                    }
                }
            }
            Section("On-device explanation") {
                Button("Explain this review on device", action: explain).frame(minHeight: 44).disabled(explaining || summary == nil || GarmentAssistance.unavailableReason != nil)
                if explaining { ProgressView("Explaining on this device"); Button("Cancel explanation") { explanationTask?.cancel(); explaining = false }.frame(minHeight: 44) }
                if let explainProblem { Text(explainProblem).foregroundStyle(Tok.stamp) }
                if let explanation {
                    Text(explanation)
                    Text("Written by the on-device model from the figures above. It is commentary, not a wardrobe fact, and it cannot add records or coverage.").font(.footnote)
                }
                if let reason = GarmentAssistance.unavailableReason { Text(reason).font(.footnote) }
            }
            if let value = analysis.value, summary != nil {
                usageSections(value)
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
        .onDisappear { explanationTask?.cancel() }
        .onChange(of: phase) { _, value in if value == .background { explanationTask?.cancel(); explaining = false } }
    }
    // The explanation belongs to the reviewed figures, so refreshing the review discards it.
    private func explain() {
        guard let summary, !explaining else { return }
        explanationTask?.cancel(); explaining = true; explanation = nil; explainProblem = nil
        let input = query
        explanationTask = Task {
            do {
                let value = try await WardrobeReviewAssistance.explain([summary], period: "\(input.from) to \(input.to)")
                guard store.isCurrentOwner, !Task.isCancelled, input == query else { return }
                explanation = value; explaining = false
            } catch { if store.isCurrentOwner, !Task.isCancelled { explainProblem = error.localizedDescription; explaining = false } }
        }
    }
    @ViewBuilder private func usageSections(_ value: WardrobeAnalysis) -> some View {
        if let most = value.mostWorn, !most.isEmpty {
            Section("Most worn in this period") { ranked(most) }
        }
        if let least = value.leastWorn, !least.isEmpty {
            Section("Least worn in this period") { ranked(least) }
        }
        if let unworn = value.notWornInRange, !unworn.isEmpty {
            Section("No confirmed wear in this period") {
                Text(unwornNote(value, list: unworn, total: value.notWornInRangeTotal)).font(.footnote)
                ForEach(unworn) { garment in
                    WardrobeGarmentLink(store: store, id: garment.garmentID) {
                        VStack(alignment: .leading) {
                            Text(garment.name + (garment.archived ? " · Archived" : ""))
                            Text(garment.neverWorn ? "Never worn · added \(garment.createdOn)" : "Last worn \(garment.lastWornOn ?? "") · \(garment.wearEvents) confirmed wears").font(.caption)
                        }
                    }
                }
            }
        }
        if let never = value.neverWorn, !never.isEmpty {
            Section("Never worn at all") {
                Text("These garments have no confirmed wear on or before the review end date, so they are not just unused in this period.").font(.footnote)
                ForEach(never) { garment in
                    WardrobeGarmentLink(store: store, id: garment.garmentID) {
                        VStack(alignment: .leading) {
                            Text(garment.name + (garment.archived ? " · Archived" : ""))
                            Text("Added \(garment.createdOn)").font(.caption)
                        }
                    }
                }
            }
        }
        if let colours = value.colours, !colours.isEmpty {
            Section("Recorded colours") {
                ForEach(colours) { colour in
                    Text("\(WardrobeVocabulary.title(colour.colour)): \(colour.garments) garments, \(colour.wornGarments) worn in this period, \(colour.wearEvents) wear events.").font(.subheadline)
                }
                Text(value.coloursTruncated == true ? "Only the most common colours are listed. A garment with several colours is counted under each, so these entries do not add up to the inventory." : "A garment with several colours is counted under each, so these entries do not add up to the inventory.").font(.footnote)
            }
        }
        if let weeks = value.weeks, !weeks.isEmpty {
            Section("Confirmed wears by week") {
                ForEach(weeks.suffix(8)) { week in
                    Text("Week of \(week.weekStart): \(week.wearEvents) wear events on \(week.wearDays) days").font(.subheadline)
                }
                if weeks.count > 8 { Text("Showing the 8 most recent of \(weeks.count) weeks.").font(.footnote) }
                if value.weeksTruncated == true { Text("Only the most recent weeks are available.").font(.footnote) }
            }
        }
        Section("Plans, choices and feedback") {
            if let selections = value.selections {
                Text("\(selections.selectedDays) days had a saved choice, \(selections.confirmedDays) of them later confirmed as a real wear, \(selections.clearedDays) cleared. \(selections.plannedOutfits) outfits are still only planned.").font(.subheadline)
            }
            if let feedback = value.feedback, feedback.records > 0 {
                Text("\(feedback.records) explicit feedback records: \(feedback.rated) overall, \(feedback.comfortRated) comfort, \(feedback.styleRated) style, \(feedback.comments) with comments.").font(.subheadline)
                let buckets = feedback.ratings.map { ("Overall", $0) } + feedback.comfort.map { ("Comfort", $0) } + feedback.style.map { ("Style", $0) }
                ForEach(buckets.indices, id: \.self) { index in
                    Text("\(buckets[index].0) \(buckets[index].1.rating): \(buckets[index].1.feedback)").font(.caption)
                }
            }
            Text("A plan, a saved choice or opening a record is never counted as a wear or a rating.").font(.footnote)
        }
    }
    @ViewBuilder private func ranked(_ list: [WardrobeGarmentUsage]) -> some View {
        ForEach(list) { garment in
            WardrobeGarmentLink(store: store, id: garment.garmentID) {
                VStack(alignment: .leading) {
                    Text(garment.name + (garment.archived ? " · Archived" : ""))
                    Text("\(garment.wearEvents) wear events on \(garment.wearDays) days in this period" + (garment.costPerWear.map { " · \($0.text) per wear over \($0.wearEvents) confirmed wears" } ?? "")).font(.caption)
                }
            }
        }
    }
    private func unwornNote(_ value: WardrobeAnalysis, list: [WardrobeUnwornGarment], total: Int64?) -> String {
        let counted = list.filter(\.neverWorn).count
        var note = "These garments existed but had no confirmed wear in these dates."
        if value.neverWornTotal == 0 && counted == 0 { note += " All of them have been worn at some point." }
        if let total, total > Int64(list.count) { note += " Only the \(list.count) longest-owned of \(total) are listed." }
        return note
    }
    private func load() async {
        revision += 1; let ticket = revision; let input = query
        analysis = WardrobeRead(); records = WardrobeRead(); summary = nil
        explanationTask?.cancel(); explaining = false; explanation = nil; explainProblem = nil
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

// A review lists garments by identity only, so opening one reads its current record before showing
// the ordinary garment detail. Nothing in the review is edited or saved from here.
private struct WardrobeGarmentLink<Content: View>: View {
    let store: WardrobeStore
    let id: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationLink(destination: WardrobeGarmentLoader(store: store, id: id)) { content() }
    }
}
private struct WardrobeGarmentLoader: View {
    let store: WardrobeStore
    let id: String
    @State private var read = WardrobeRead<WardrobeGarmentResult>()
    var body: some View {
        Group {
            if let garment = read.value?.garment { WardrobeGarmentDetail(store: store, initial: garment) }
            else {
                List {
                    WardrobeReadStatus(state: read) { await load() }
                    Text("Opening this garment reads its current record, including wear totals and the facts saved with it.").font(.footnote)
                }.navigationTitle("Garment").navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
    }
    private func load() async {
        if read.value == nil { read.loading = true }
        let result: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: id))
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        read = result
    }
}
