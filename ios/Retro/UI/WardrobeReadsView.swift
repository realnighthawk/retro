import SwiftUI
import UIKit

struct WardrobeTodayView: View {
    let store: WardrobeStore
    @State private var date = Date()
    @State private var composing = false
    @State private var asking = false
    @State private var choosing: WardrobeDayChoiceRequest?
    @State private var dailyRefresh = 0
    @State private var lastLocalDay = WardrobeVocabulary.dayKey(Date())
    @Environment(\.scenePhase) private var scenePhase
    private var dayKey: String { WardrobeVocabulary.dayKey(date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DatePicker("Outfits for", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact).frame(minHeight: 44)
                Button { asking = true } label: { Label("Ask Retro", systemImage: "sparkles") }.frame(minHeight: 44)
                WardrobeReadStatus(state: store.day) { await store.refreshDay(dayKey) }
                if let day = store.day.value {
                    if let selection = day.selection, let outfit = selection.outfit {
                        SectionTitle(text: "Selected for this day")
                        NavigationLink { WardrobeOutfitDetail(store: store, initial: outfit) } label: { WardrobeOutfitCard(outfit: outfit) }.buttonStyle(.plain)
                        if let problem = selection.problem { Text(problem).font(.footnote).foregroundStyle(Tok.stamp) }
                        Text(outfit.state == "worn" ? "Your selected outfit has a recorded wear." : "Your selected plan stays here when suggestions refresh. Record wear separately.").font(.footnote)
                        if outfit.state == "planned", outfit.day == day.day {
                            Button("Review daily choice again") { choosing = WardrobeDayChoiceRequest(day: day.day, outfitID: outfit.id) }.frame(minHeight: 44).disabled(store.day.loading || store.day.cached || store.writes.contains(selection.id) || store.writes.contains(outfit.id))
                        }
                        Button("Clear daily selection") { choosing = WardrobeDayChoiceRequest(day: day.day, outfitID: nil) }.frame(minHeight: 44).disabled(store.day.loading || store.day.cached || store.writes.contains(selection.id))
                    }
                    if let selection = day.selection, selection.version > 0 {
                        if store.writes.contains(selection.id) { Text("Daily choice save pending. Check Pending saves for acknowledgement.").font(.footnote) }
                        NavigationLink("Daily choice history") { WardrobeAuditView(store: store, entityType: "day_selection", id: selection.id) }.frame(minHeight: 44)
                    }
                    if day.outfits.isEmpty {
                        WardrobeEmpty(title: "No outfits for this date", message: "Planned and recorded outfits appear here.", symbol: "hanger")
                    }
                    ForEach(day.outfits.filter { $0.id != day.selection?.outfitID }) { outfit in
                        NavigationLink {
                            WardrobeOutfitDetail(store: store, initial: outfit)
                        } label: { WardrobeOutfitCard(outfit: outfit) }
                        .buttonStyle(.plain)
                        if outfit.state == "planned", let selection = day.selection {
                            Button("Choose \(outfit.title) for this day") { choosing = WardrobeDayChoiceRequest(day: day.day, outfitID: outfit.id) }.frame(minHeight: 44)
                                .disabled(store.day.loading || store.day.cached || store.writes.contains(selection.id) || store.writes.contains(outfit.id))
                        }
                    }
                }
                WardrobeDailyChoicesView(store: store, day: dayKey, refresh: dailyRefresh)
            }.padding(20)
        }
        .background(Tok.bg).navigationTitle("Today")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Compose outfit") { composing = true } } }
        .sheet(isPresented: $composing) { WardrobeOutfitEditor(store: store, date: date) }
        .sheet(isPresented: $asking) { WardrobeAssistantView(assistant: store.assistant, day: dayKey) }
        .sheet(item: $choosing) { WardrobeDaySelectionView(store: store, day: $0.day, outfitID: $0.outfitID) }
        .task(id: dayKey) { await store.refreshDay(dayKey) }
        .refreshable { dailyRefresh += 1; await store.refreshDay(dayKey) }
        .onChange(of: scenePhase) { _, value in if value == .active { rollLocalDay(); dailyRefresh += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollLocalDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in rollLocalDay(); dailyRefresh += 1 }
    }
    private func rollLocalDay() {
        let today = WardrobeVocabulary.dayKey(Date())
        if dayKey == lastLocalDay, today != lastLocalDay { date = Date() }
        lastLocalDay = today
    }
}

struct WardrobeInventoryView: View {
    let store: WardrobeStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var query = WardrobeInventoryQuery()
    @State private var adding = false
    @State private var importing = false
    @State private var language: WardrobeLanguageContext?
    @State private var unhandled: [String] = []

    init(store: WardrobeStore, initialSearch: String = "") {
        self.store = store
        var query = WardrobeInventoryQuery(); query.search = initialSearch
        _query = State(initialValue: query)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink("Saved pairings and looks") { WardrobePairingsView(store: store) }.frame(minHeight: 44)
                NavigationLink("Laundry loads") { WardrobeLaundryView(store: store) }.frame(minHeight: 44)
                NavigationLink("Laundry check-in") { WardrobeLaundryCheckInView(store: store) }.frame(minHeight: 44)
                Button("Add from photos · \(store.drafts.imports.count) to review") { importing = true }.frame(minHeight: 44)
                Button("Describe a search") { language = WardrobeLanguageContext(inventory: query) }.frame(minHeight: 44)
                ForEach(Array(unhandled.enumerated()), id: \.offset) { _, value in Text("Not applied: " + value).font(.footnote) }
                if query != WardrobeInventoryQuery() || !unhandled.isEmpty {
                    Text("Name: \(query.search.isEmpty ? "Any" : query.search) · Category: \(query.category.isEmpty ? "Any" : WardrobeVocabulary.title(query.category)) · Availability: \(query.availability.isEmpty ? "Any" : WardrobeVocabulary.title(query.availability))").font(.footnote)
                    Button("Clear search and filters") { query = WardrobeInventoryQuery(); unhandled = [] }.frame(minHeight: 44)
                }
                HStack {
                    Menu {
                        Picker("Category", selection: $query.category) {
                            Text("All categories").tag("")
                            ForEach(WardrobeVocabulary.categories, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                        }
                    } label: { Label(query.category.isEmpty ? "Category" : WardrobeVocabulary.title(query.category), systemImage: "line.3.horizontal.decrease") }
                    .frame(minHeight: 44)
                    Spacer()
                    Menu {
                        Picker("Availability", selection: $query.availability) {
                            Text("Any availability").tag("")
                            ForEach(WardrobeVocabulary.availability, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                        }
                        Toggle("Include archived", isOn: $query.includeArchived)
                    } label: { Text(query.availability.isEmpty ? "Availability" : WardrobeVocabulary.title(query.availability)) }
                    .frame(minHeight: 44)
                }.font(.subheadline)
                if query.includeArchived { Text("Including archived garments").font(.footnote).foregroundStyle(Tok.faint) }
                WardrobeReadStatus(state: store.inventory) { await store.refreshInventory(query) }
                if let page = store.inventory.value {
                    if page.items.isEmpty {
                        WardrobeEmpty(title: query == WardrobeInventoryQuery() ? "Your wardrobe is empty" : "No matching garments",
                                      message: query == WardrobeInventoryQuery() ? "Your clothes will appear here." : "Try a different search or filter.", symbol: "hanger")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 280 : 140), spacing: 14)], spacing: 14) {
                        ForEach(page.items) { garment in
                            NavigationLink {
                                WardrobeGarmentDetail(store: store, initial: garment)
                            } label: { WardrobeGarmentCard(store: store, garment: garment) }
                            .buttonStyle(.plain)
                        }
                    }
                    if page.nextCursor != nil {
                        Button("Load more garments") { Task { await store.moreInventory() } }
                            .buttonStyle(QuietButtonStyle()).disabled(store.inventory.loading)
                    }
                }
            }.padding(20)
        }
        .background(Tok.bg).navigationTitle("Wardrobe")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Add garment") { adding = true } } }
        .sheet(isPresented: $adding) { WardrobeGarmentEditor(store: store) }
        .sheet(isPresented: $importing) { WardrobeImportView(store: store) }
        .sheet(item: $language) { context in
            WardrobeLanguageView(store: store, context: context) { draft, _, _, limitations in
                guard context.inventory == query else { throw WardrobeWriteError("The search filters changed. Review a fresh interpretation.") }
                query = try draft.searchQuery(); unhandled = limitations
            }
        }
        .searchable(text: $query.search, prompt: "Search garment names")
        .task(id: query) { await store.refreshInventory(query, debounce: true) }
        .refreshable { await store.refreshInventory(query) }
    }
}

struct WardrobeHistoryView: View {
    let store: WardrobeStore
    @State private var query: WardrobeHistoryQuery
    @State private var limited = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var garments: [WardrobeSelection] = []
    @State private var picking = false
    init(store: WardrobeStore, garmentID: String = "") {
        self.store = store
        _query = State(initialValue: WardrobeHistoryQuery(garmentID: garmentID))
    }
    private var input: WardrobeHistoryQuery {
        var value = query
        value.from = limited ? WardrobeVocabulary.dayKey(from) : ""
        value.to = limited ? WardrobeVocabulary.dayKey(to) : ""
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Outfit state", selection: $query.state) {
                    Text("Worn").tag("worn")
                    Text("Planned").tag("planned")
                    Text("Void").tag("void")
                    Text("All").tag("")
                }.pickerStyle(.menu).frame(minHeight: 44)
                NavigationLink("Insights") { WardrobeInsightsView(store: store) }.frame(minHeight: 44)
                NavigationLink("Wardrobe review") { WardrobePeriodReviewView(store: store) }.frame(minHeight: 44)
                DisclosureGroup("Timeline filters") {
                    Toggle("Limit dates", isOn: $limited)
                    if limited {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("Through", selection: $to, displayedComponents: .date)
                    }
                    Button(query.garmentID.isEmpty ? "Filter by garment" : "Change garment filter") { picking = true }.frame(minHeight: 44)
                    if !query.garmentID.isEmpty {
                        Text(garments.first?.name ?? "Selected garment").font(.footnote)
                        Button("Clear garment filter") { garments = []; query.garmentID = "" }.frame(minHeight: 44)
                    }
                }
                WardrobeReadStatus(state: store.history) { await store.refreshHistory(input) }
                if let page = store.history.value {
                    if page.items.isEmpty {
                        WardrobeEmpty(title: "No outfits here yet", message: "Your outfit history appears here.", symbol: "clock")
                    }
                    let dates = Array(Set(page.items.map(\.day))).sorted(by: >)
                    ForEach(dates, id: \.self) { date in
                        SectionTitle(text: date)
                        ForEach(page.items.filter { $0.day == date }) { outfit in
                            NavigationLink { WardrobeOutfitDetail(store: store, initial: outfit) } label: {
                                WardrobeOutfitCard(outfit: outfit)
                            }.buttonStyle(.plain)
                        }
                    }
                    if page.nextCursor != nil {
                        Button("Load more outfits") { Task { await store.moreHistory() } }
                            .buttonStyle(QuietButtonStyle()).disabled(store.history.loading)
                    }
                }
            }.padding(20)
        }
        .background(Tok.bg).navigationTitle("History")
        .task(id: input) { await store.refreshHistory(input) }
        .refreshable { await store.refreshHistory(input) }
        .sheet(isPresented: $picking) { WardrobeGarmentPicker(store: store, items: $garments, historical: true, maximum: 1) }
        .onChange(of: garments) { _, value in query.garmentID = value.first?.id ?? "" }
    }
}

private struct WardrobeGarmentCard: View {
    let store: WardrobeStore
    let garment: WardrobeGarment
    var body: some View {
        Panel {
            if let id = garment.mediaIDs?.first {
                WardrobeRemotePhoto(store: store, id: id, label: garment.name).frame(height: 140)
            } else {
                Image(systemName: "hanger").font(.largeTitle).foregroundStyle(Tok.faint).frame(maxWidth: .infinity, minHeight: 72)
            }
            Text(garment.name).font(.headline).foregroundStyle(Tok.ink)
            Text(WardrobeVocabulary.title(garment.category)).font(.subheadline).foregroundStyle(Tok.faint)
            Text(garment.archivedAt == nil ? WardrobeVocabulary.title(garment.availability) : "Archived")
                .font(.footnote).foregroundStyle(Tok.faint)
            Text("\(garment.wearDays) days worn").font(.footnote).foregroundStyle(Tok.faint)
        }.accessibilityElement(children: .combine)
    }
}

private struct WardrobeOutfitCard: View {
    let outfit: WardrobeOutfit
    var body: some View {
        Panel {
            HStack(alignment: .firstTextBaseline) {
                Text(outfit.title).font(.headline).foregroundStyle(Tok.ink)
                Spacer()
                Text(WardrobeVocabulary.title(outfit.state)).font(.subheadline)
                    .foregroundStyle(outfit.state == "worn" ? Tok.good : outfit.state == "void" ? Tok.stamp : Tok.faint)
            }
            Text(outfit.items.map { $0.snapshot?.name ?? "Garment" }.joined(separator: ", "))
                .font(.body).foregroundStyle(Tok.faint)
            if let occasion = outfit.occasion { Text(occasion).font(.footnote).foregroundStyle(Tok.faint) }
        }.accessibilityElement(children: .combine)
    }
}

private struct WardrobeGarmentDetail: View {
    let store: WardrobeStore
    let initial: WardrobeGarment
    @State private var read = WardrobeRead<WardrobeGarmentResult>()
    @State private var photoEditor: WardrobeGarment?
    @State private var showingCare = false
    @State private var editing: WardrobeGarment?
    @State private var lifecycle = false
    @State private var lifecycleRecord: WardrobeGarment?
    @State private var problem: String?

    private func refresh() async {
        read.loading = true
        read = await store.record("garments_get", id: initial.id, fallback: WardrobeGarmentResult(garment: initial))
    }

    var body: some View {
        let garment = read.value?.garment ?? initial
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WardrobeReadStatus(state: read, retry: refresh)
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                if store.writes.contains(garment.id) { Text("This garment has a pending save. Open Pending saves to review it.").font(.footnote) }
                if store.photos.contains(garment.id) { Text("Photo upload or attachment pending. Open Photos or Pending saves to review it.").font(.footnote) }
                HStack {
                    if garment.archivedAt == nil { Button("Edit") { editing = garment }.frame(minWidth: 44, minHeight: 44).disabled(read.loading) }
                    Button(garment.archivedAt == nil ? "Archive" : "Restore") { lifecycleRecord = garment; lifecycle = true }.frame(minWidth: 44, minHeight: 44).disabled(store.writes.contains(garment.id) || read.loading)
                }.frame(minHeight: 44)
                if garment.archivedAt == nil { Button("Manage photos") { photoEditor = garment }.frame(minHeight: 44).disabled(read.loading) }
                Button("Care instructions\(garment.care?.confirmed == true ? " · Reviewed" : " · Needs review")") { showingCare = true }.frame(minHeight: 44).disabled(read.loading)
                NavigationLink("Record history") { WardrobeAuditView(store: store, entityType: "garment", id: garment.id) }.frame(minHeight: 44)
                NavigationLink("Wash history and loads") { WardrobeLaundryView(store: store, garmentID: garment.id) }.frame(minHeight: 44)
                NavigationLink("Wears since cleaning and reminders") { WardrobeLaundryCheckInView(store: store, garmentID: garment.id) }.frame(minHeight: 44)
                NavigationLink("What goes with this?") { WardrobePairingsView(store: store, garment: garment) }.frame(minHeight: 44)
                ForEach(garment.mediaIDs ?? [], id: \.self) { id in
                    WardrobeRemotePhoto(store: store, id: id, variant: "display", label: garment.name).frame(maxHeight: 280)
                }
                Panel {
                    Text(garment.name).font(.title2.bold()).foregroundStyle(Tok.ink)
                    detail("Category", WardrobeVocabulary.title(garment.category))
                    detail("Availability", WardrobeVocabulary.title(garment.availability))
                    if garment.archivedAt != nil { detail("Status", "Archived") }
                    detail("Colours", garment.colours?.joined(separator: ", "))
                    detail("Subtype", garment.subtype)
                    detail("Warmth", garment.warmth.map(WardrobeVocabulary.title))
                    detail("Seasons", garment.seasons?.joined(separator: ", "))
                    detail("Formality", garment.formality)
                    detail("Material", garment.material)
                    detail("Brand", garment.brand)
                    if garment.favourite == true { detail("Favourite", "Yes") }
                    detail("Days worn", "\(garment.wearDays)")
                    detail("Outfit events", "\(garment.wearEvents)")
                    detail("Last worn", garment.lastWornOn ?? "Not recorded")
                    if let notes = garment.notes { Text(notes).font(.body).foregroundStyle(Tok.ink) }
                }
            }.padding(20)
        }
        .background(Tok.bg).navigationTitle("Garment").navigationBarTitleDisplayMode(.inline)
        .task(id: store.changes) { await refresh() }.refreshable { await refresh() }
        .sheet(item: $photoEditor) { frozen in WardrobePhotosView(store: store, garment: frozen) }
        .sheet(isPresented: $showingCare) { WardrobeSettingsView(store: store, record: .care(garment.id)) }
        .sheet(item: $editing) { frozen in WardrobeGarmentEditor(store: store, garment: frozen) }
        .confirmationDialog(garment.archivedAt == nil ? "Archive this garment? Existing history stays intact." : "Restore this garment?", isPresented: $lifecycle, titleVisibility: .visible) {
            let frozen = lifecycleRecord ?? garment
            Button(frozen.archivedAt == nil ? "Archive" : "Restore") {
                do { try store.submit(frozen.archivedAt == nil ? "garments_archive" : "garments_restore", entity: frozen.id, title: frozen.name,
                                      fields: WardrobeDraftValidation.edit(id: frozen.id, version: frozen.version)) }
                catch { problem = error.localizedDescription }
            }
        }
    }
}

struct WardrobeOutfitDetail: View {
    let store: WardrobeStore
    let initial: WardrobeOutfit
    @State private var read = WardrobeRead<WardrobeOutfitResult>()
    @State private var reusing = false
    @State private var showingFeedback = false
    @State private var savingPairing = false
    @State private var editing: WardrobeOutfit?
    @State private var confirming: WardrobeOutfit?
    @State private var lifecycle = false
    @State private var lifecycleRecord: WardrobeOutfit?
    @State private var problem: String?

    private func refresh() async {
        read.loading = true
        read = await store.record("outfits_get", id: initial.id, fallback: WardrobeOutfitResult(outfit: initial))
    }

    var body: some View {
        let outfit = read.value?.outfit ?? initial
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WardrobeReadStatus(state: read, retry: refresh)
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                if store.writes.contains(outfit.id) { Text("This outfit has a pending save. It is not confirmed until acknowledged.").font(.footnote) }
                VStack(alignment: .leading) {
                    Button("Reuse as a new plan") { reusing = true }.frame(minHeight: 44).disabled(read.loading || store.writes.contains(outfit.id))
                    Button("Save pieces as a pairing") { savingPairing = true }.frame(minHeight: 44).disabled(read.loading || outfit.items.count < 2 || store.writes.contains(outfit.id))
                    if outfit.state != "void" { Button("Correct outfit") { editing = outfit }.frame(minHeight: 44).disabled(read.loading) }
                    if outfit.state == "planned" { Button("Record wear") { confirming = outfit }.frame(minHeight: 44).disabled(store.writes.contains(outfit.id) || read.loading) }
                    Button(outfit.state == "void" ? "Restore outfit" : "Void outfit") { lifecycleRecord = outfit; lifecycle = true }.frame(minHeight: 44).disabled(store.writes.contains(outfit.id) || read.loading)
                }
                Panel {
                    Text(outfit.title).font(.title2.bold()).foregroundStyle(Tok.ink)
                    detail("Date", outfit.day)
                    detail("Time zone", outfit.timeZone)
                    detail("State", WardrobeVocabulary.title(outfit.state))
                    detail("Occasion", outfit.occasion)
                    if let notes = outfit.notes { Text(notes).font(.body).foregroundStyle(Tok.ink) }
                }
                NavigationLink("Record history") { WardrobeAuditView(store: store, entityType: "outfit", id: outfit.id) }.frame(minHeight: 44)
                Button("Outfit feedback") { showingFeedback = true }.frame(minHeight: 44).disabled(read.loading)
                ForEach(outfit.items) { item in
                    Panel {
                        if let id = item.snapshot?.mediaIDs?.first { WardrobeRemotePhoto(store: store, id: id, variant: "display", label: item.snapshot?.name ?? "Garment photo").frame(maxHeight: 220) }
                        Text(item.snapshot?.name ?? "Garment").font(.headline).foregroundStyle(Tok.ink)
                        detail("Role", WardrobeVocabulary.title(item.role))
                        detail("Colours", item.snapshot?.colours?.joined(separator: ", "))
                    }
                }
            }.padding(20)
        }
        .background(Tok.bg).navigationTitle("Outfit").navigationBarTitleDisplayMode(.inline)
        .task(id: store.changes) { await refresh() }.refreshable { await refresh() }
        .sheet(isPresented: $reusing) { WardrobeReuseView(store: store, id: outfit.id) }
        .sheet(isPresented: $savingPairing) { WardrobePairingEditor(store: store, pieces: outfit.items.map { WardrobeSelection(id: $0.garmentID, name: $0.snapshot?.name ?? "Garment", role: $0.role) }) }
        .sheet(isPresented: $showingFeedback) { WardrobeSettingsView(store: store, record: .feedback(outfit.id)) }
        .sheet(item: $editing) { frozen in WardrobeOutfitEditor(store: store, outfit: frozen) }
        .sheet(item: $confirming) { frozen in WardrobeOutfitEditor(store: store, outfit: frozen, confirming: true) }
        .confirmationDialog(outfit.state == "void" ? "Restore this outfit and its previous state?" : "Void this outfit? Its wears will stop counting after acknowledgement.", isPresented: $lifecycle, titleVisibility: .visible) {
            let frozen = lifecycleRecord ?? outfit
            Button(frozen.state == "void" ? "Restore outfit" : "Void outfit") {
                do { try store.submit(frozen.state == "void" ? "outfits_restore" : "outfits_void", entity: frozen.id, title: frozen.title,
                                      fields: WardrobeDraftValidation.edit(id: frozen.id, version: frozen.version)) }
                catch { problem = error.localizedDescription }
            }
        }
    }
}

@ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
        LabeledContent(title, value: value).font(.body).foregroundStyle(Tok.ink)
    }
}

struct WardrobeReadStatus<Value>: View {
    let state: WardrobeRead<Value>
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.loading { ProgressView("Refreshing").tint(Tok.accent) }
            if state.cached {
                if let date = state.savedAt {
                    Text("Previously loaded · \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(Tok.faint)
                } else { Text("Previously loaded").font(.footnote).foregroundStyle(Tok.faint) }
            }
            if let problem = state.problem {
                Text(problem).font(.body).foregroundStyle(Tok.faint)
                Button("Try again") { Task { await retry() } }.frame(minHeight: 44).disabled(state.loading)
            }
        }.accessibilityElement(children: .contain)
    }
}

private struct WardrobeEmpty: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
