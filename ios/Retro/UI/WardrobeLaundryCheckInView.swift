import SwiftUI
import UIKit

struct WardrobeLaundryCheckInView: View {
    let store: WardrobeStore
    var garmentID = ""
    @Environment(\.scenePhase) private var phase
    @State private var read = WardrobeRead<WardrobeLaundryCheckIn>()
    @State private var timeZone = TimeZone.current.identifier
    @State private var filter = "due"
    @State private var revision = 0
    @State private var care: WardrobeLaundryCheckInItem?
    @State private var reminder: WardrobeLaundryCheckInItem?
    @State private var editing: WardrobeGarment?
    @State private var fetching = false
    @State private var problem: String?
    private var query: WardrobeLaundryCheckInQuery { .init(time_zone: timeZone, garment_id: garmentID) }
    private var items: [WardrobeLaundryCheckInItem] {
        let values = read.value?.items ?? []
        if !garmentID.isEmpty || filter == "all" { return values }
        return values.filter { filter == "due" ? $0.due : $0.reminder != nil }
    }
    var body: some View {
        List {
            Section {
                Text("Optional reminders ask you to review care and availability. Thresholds count distinct wear dates definitely after the latest completed cleaning, or calendar days since completion. Same-day timing is unclear. A reminder never marks a garment dirty or starts a load.").font(.footnote)
                Text("Check-ins refresh here when connected. These are in-app reminders; no background notification is scheduled.").font(.footnote)
                TextField("Calendar interval time zone", text: $timeZone).textInputAutocapitalization(.never).autocorrectionDisabled()
                if garmentID.isEmpty {
                    Picker("Show", selection: $filter) { Text("Due for review").tag("due"); Text("Reminders enabled").tag("enabled"); Text("All active pieces").tag("all") }
                }
                WardrobeReadStatus(state: read) { await load() }
                if let result = read.value {
                    Text("\(result.inventory_count) \(garmentID.isEmpty ? "active pieces assessed" : "garment assessed") · \(result.items.filter(\.due).count) care reviews due").font(.footnote)
                    if let stamp = GatewayAgentResult.date(result.generated_at) { Text("Assessed \(stamp.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                }
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
            }
            if read.value != nil, items.isEmpty { Text("No items match this filter in the complete check-in.") }
            ForEach(items) { item in
                if garmentID.isEmpty {
                    NavigationLink { WardrobeLaundryCheckInView(store: store, garmentID: item.id) } label: { summary(item) }
                } else {
                    Section(item.name) {
                        summary(item)
                        if let cleaning = item.last_cleaning {
                            if let stamp = GatewayAgentResult.date(cleaning.completed_at) { LabeledContent("Last confirmed dry/clean return", value: stamp.formatted(date: .abbreviated, time: .shortened)) }
                            NavigationLink("Completed cleaning record") { WardrobeLaundryDetail(store: store, id: cleaning.id) }.frame(minHeight: 44)
                        } else { Text("No confirmed cleaning baseline. Counts remain unknown and reminders wait for a completed cleaning record.").font(.footnote) }
                        Text("Wear dates use each outfit's time zone. Multiple outfits on one date count as one wear day. Voided wears and cancelled/unfinished loads do not contribute a clean baseline.").font(.footnote)
                        Button("Review care instructions") { care = item }.frame(minHeight: 44)
                        Button("Review reminder thresholds") { reminder = item }.frame(minHeight: 44).disabled(item.archived_at != nil)
                        Button("Review garment and availability") { Task { await openGarment(item.id) } }.frame(minHeight: 44).disabled(fetching || item.archived_at != nil)
                        NavigationLink("Wash history and loads") { WardrobeLaundryView(store: store, garmentID: item.id) }.frame(minHeight: 44)
                        if store.writes.contains(item.id) { Text("Garment save pending. Refresh the check-in after acknowledgement.").font(.footnote) }
                    }
                }
            }
        }.navigationTitle(garmentID.isEmpty ? "Laundry check-in" : "Garment care check-in").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $care) { WardrobeSettingsView(store: store, record: .care($0.id)) }
            .sheet(item: $reminder) { WardrobeLaundryReminderView(store: store, id: $0.id) }
            .sheet(item: $editing) { WardrobeGarmentEditor(store: store, garment: $0) }
            .task(id: "\(timeZone):\(store.changes)") { await load() }.refreshable { await load() }
            .onChange(of: phase) { _, value in if value == .active { Task { await load() } } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in Task { await load() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await load() } }
    }
    @ViewBuilder private func summary(_ item: WardrobeLaundryCheckInItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.name).font(.headline)
            Text("\(WardrobeVocabulary.title(item.availability)) · \(item.status)").font(.footnote)
            if let wears = item.wears_since_cleaning {
                Text("Since cleaning: \(wears.wear_days) definite wear days · \(wears.wear_events) wear records").font(.footnote)
                Text("Same cleaning-day timing unclear: \(wears.same_day_wear_days) wear dates · \(wears.same_day_wear_events) records").font(.footnote)
            } else { Text("Wears since cleaning: unknown").font(.footnote) }
            if let days = item.days_since_cleaning { Text("\(days) calendar days since cleaning in \(timeZone)").font(.footnote) }
            if let reminder = item.reminder { Text("Review after " + reminder.summary).font(.footnote) }
            ForEach(item.due_reasons, id: \.self) { reason in Text(reason == "wear_threshold" ? "Your wear-day review threshold was reached." : "Your calendar-day review interval was reached.").font(.footnote) }
        }.frame(minHeight: 44)
    }
    private func load() async {
        revision += 1; let current = revision; let input = query
        read = WardrobeRead(loading: true)
        guard TimeZone(identifier: input.time_zone) != nil, !input.time_zone.isEmpty, input.time_zone != "Local", input.time_zone.utf8.count <= 100 else { read = WardrobeRead(problem: "Enter an explicit IANA time zone, such as America/Los_Angeles."); return }
        let result: WardrobeRead<WardrobeLaundryCheckIn> = await store.read("laundry_check_in", input: input)
        guard current == revision, input == query, store.isCurrentOwner, !Task.isCancelled else { return }
        do { try result.value?.validate(input, cached: result.cached); read = result }
        catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
    private func openGarment(_ id: String) async {
        guard !fetching else { return }; fetching = true; problem = nil
        defer { fetching = false }
        let source = revision
        let result: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: id))
        guard source == revision, store.isCurrentOwner, !Task.isCancelled else { return }
        guard !result.cached, let garment = result.value?.garment, garment.id == id else { problem = result.problem ?? "Refresh the current garment before editing availability."; return }
        editing = garment
    }
}

struct WardrobeLaundryReminderView: View {
    let store: WardrobeStore
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WardrobeLaundryReminderDraft()
    @State private var original = WardrobeLaundryReminderDraft()
    @State private var garment: WardrobeGarment?
    @State private var loading = false
    @State private var ready = false
    @State private var problem: String?
    @State private var saved = false
    @State private var discarding = false
    private var dirty: Bool { draft != original }
    private var editable: Bool { ready && !loading && !saved && store.isCurrentOwner && !store.writes.contains(id) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let garment { Text(garment.name).font(.headline) }
                    Text("Opt in to an in-app care review after either threshold is reached. These are your preferences, not label instructions. Counts begin at the latest confirmed dry/clean return; no baseline means the reminder waits. Same-day wears have unclear timing and do not advance the wear threshold.").font(.footnote)
                    Text("Saving does not change availability or schedule a notification. Active laundry must finish/cancel before changing garment settings.").font(.footnote)
                    // shortcut: unsaved reminder forms stay in memory; add draft-journal recovery if cross-launch editing is needed.
                    Text("Unsaved changes stay in this form. Accepted saves use Pending saves for durable acknowledgement and recovery.").font(.footnote)
                    if loading { ProgressView("Loading current garment") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    if !ready { Button("Load current garment") { Task { await load() } }.frame(minHeight: 44).disabled(loading || dirty) }
                }
                Section("Care reminder") {
                    Toggle("Show in-app review reminders", isOn: $draft.enabled)
                    if draft.enabled {
                        Toggle("Use a wear-day threshold", isOn: $draft.wearEnabled)
                        if draft.wearEnabled { Stepper("Review after \(draft.wearDays) distinct wear days", value: $draft.wearDays, in: 1...100) }
                        Toggle("Use a calendar-day interval", isOn: $draft.intervalEnabled)
                        if draft.intervalEnabled { Stepper("Review after \(draft.intervalDays) calendar days", value: $draft.intervalDays, in: 1...365) }
                        Text("Enable at least one threshold. With both enabled, the first one reached prompts review. Completed cleaning starts a new interval.").font(.footnote)
                    }
                }.disabled(!editable)
            }.navigationTitle("Laundry reminder").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { discarding = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!editable) }
                }
                .interactiveDismissDisabled(!saved && dirty)
                .confirmationDialog("Discard unsaved reminder changes?", isPresented: $discarding, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
        }.task { await load() }
    }
    private func load() async {
        guard !dirty, !loading else { return }; loading = true; ready = false; problem = nil
        defer { loading = false }
        let result: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: id))
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        do {
            guard !result.cached, let value = result.value?.garment, value.id == id, value.archivedAt == nil else { throw WardrobeWriteError(result.problem ?? "Refresh or restore this garment before editing reminders.") }
            try value.laundryReminder?.validate(); garment = value; draft = WardrobeLaundryReminderDraft(value.laundryReminder); original = draft; ready = true
        } catch { problem = error.localizedDescription }
    }
    private func save() {
        guard editable, let garment else { return }
        do {
            if !dirty { dismiss(); return }
            var fields = WardrobeDraftValidation.edit(id: id, version: garment.version); fields["patch"] = try draft.patch()
            try store.submit("garments_update", entity: id, title: "\(garment.name) laundry reminder", fields: fields)
            saved = true; dismiss()
        } catch { problem = error.localizedDescription }
    }
}
