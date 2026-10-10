import SwiftUI

struct WardrobeLaundryView: View {
    let store: WardrobeStore
    var garmentID = ""
    @State private var read = WardrobeRead<WardrobePage<WardrobeLaundryLoad>>()
    @State private var state = ""
    @State private var adding = false
    @State private var revision = 0
    private var query: WardrobeLaundryQuery { .init(state: state, garment_id: garmentID) }
    var body: some View {
        List {
            Section {
                Text("Plan compatible loads from garments marked Needs wash. Progress records your confirmations; wearing alone never marks a garment dirty.").font(.footnote)
                Picker("Load state", selection: $state) { Text("All").tag(""); ForEach(WardrobeLaundryLoad.states, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
                WardrobeReadStatus(state: read) { await load() }
                NavigationLink("Wears since cleaning and reminders") { WardrobeLaundryCheckInView(store: store, garmentID: garmentID) }.frame(minHeight: 44)
            }
            if let page = read.value {
                if page.items.isEmpty { Text("No laundry loads for this filter.") }
                ForEach(page.items) { load in
                    NavigationLink { WardrobeLaundryDetail(store: store, id: load.id, initial: load) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(load.name).font(.headline)
                            Text("\(load.day) · \(load.stateTitle) · \(load.items.count) pieces").font(.footnote)
                            Text(load.program.summary).font(.footnote).foregroundStyle(.secondary)
                            if store.writes.contains(load.id) { Text("Save pending").font(.caption) }
                        }.frame(minHeight: 44)
                    }
                }
                if page.nextCursor != nil { Button("Load more laundry records") { Task { await load(more: true) } }.frame(minHeight: 44).disabled(read.loading) }
            }
        }.navigationTitle(garmentID.isEmpty ? "Laundry" : "Garment laundry")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Plan a load") { adding = true }.frame(minHeight: 44) } }
            .sheet(isPresented: $adding) { WardrobeLaundryEditor(store: store) }
            .task(id: "\(state):\(store.changes)") { await load() }.refreshable { await load() }
    }
    private func load(more: Bool = false) async {
        revision += 1; let current = revision; let scope = query
        var input = scope
        if more { guard let cursor = read.value?.nextCursor else { return }; input.cursor = cursor }
        let previous = read
        if !more { read = WardrobeRead() }
        read.loading = true
        let result: WardrobeRead<WardrobePage<WardrobeLaundryLoad>> = await store.read("laundry_list", input: input)
        guard current == revision, scope == query, store.isCurrentOwner, !Task.isCancelled else { return }
        do {
            for load in result.value?.items ?? [] { try load.validate() }
            if more, let page = result.value {
                let prior = previous.value?.items ?? []; let ids = Set(prior.map(\.id))
                read = result; read.value = WardrobePage(items: prior + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
            } else if more { read = previous; read.loading = false; read.problem = result.problem }
            else { read = result }
        } catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
}

struct WardrobeLaundryDetail: View {
    let store: WardrobeStore
    let id: String
    var initial: WardrobeLaundryLoad?
    @State private var read = WardrobeRead<WardrobeLaundryResult>()
    @State private var editing: WardrobeLaundryLoad?
    @State private var frozen: WardrobeLaundryLoad?
    @State private var cancelling = false
    @State private var problem: String?
    private var current: WardrobeLaundryLoad? { read.value?.load ?? initial }
    private var editable: Bool { !read.loading && !read.cached && read.value != nil && store.isCurrentOwner && !store.writes.contains(id) }
    private var piecesPending: Bool { current?.items.contains(where: { store.writes.contains($0.id) }) ?? true }
    var body: some View {
        List {
            Section { WardrobeReadStatus(state: read) { await load() }; if let problem { Text(problem).foregroundStyle(Tok.stamp) } }
            if let record = current {
                Section {
                    Text(record.name).font(.title2)
                    Text("\(record.day) · \(record.time_zone) · \(record.stateTitle)").font(.footnote)
                    Text(record.program.summary)
                    Text("Saved care snapshots stay in this record. Starting checks current care, garment versions and availability. Washing and drying both keep garments unavailable for outfits.").font(.footnote)
                    if store.writes.contains(id) { Text("Load save pending. Reconcile it in Pending saves before another step.").font(.footnote) }
                    if record.state == "planned", piecesPending { Text("Resolve pending garment saves before starting this load.").font(.footnote) }
                }
                Section("Reviewed pieces") {
                    ForEach(record.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.snapshot.name)
                            Text("Care: \(WardrobeVocabulary.title(item.snapshot.care?.colour_group ?? "unknown")) · \(WardrobeVocabulary.title(item.snapshot.care?.drying ?? "unknown"))").font(.footnote)
                            Text("Reviewed garment version \(item.snapshot.version)").font(.caption)
                        }
                    }
                }
                Section("Progress") {
                    stamp("Started", record.started_at); stamp(record.program.wash_method == "dry_clean" ? "Returned clean from cleaner" : "Wash finished", record.washed_at)
                    stamp("Completed dry and ready", record.completed_at); stamp("Cancelled", record.cancelled_at)
                    if ["planned", "washing", "drying"].contains(record.state) {
                        Button(record.progressTitle) { cancelling = false; frozen = record }.frame(minHeight: 44).disabled(!editable || record.state == "planned" && piecesPending)
                        Button("Cancel load", role: .destructive) { cancelling = true; frozen = record }.frame(minHeight: 44).disabled(!editable)
                        Text("Cancel keeps the record. Active pieces return to Needs wash; cancellation never claims they are clean or dry.").font(.footnote)
                    }
                }
                Section {
                    if record.state == "planned" { Button("Edit planned load") { editing = record }.frame(minHeight: 44).disabled(!editable) }
                    NavigationLink("Load change history") { WardrobeAuditView(store: store, entityType: "laundry_load", id: id) }.frame(minHeight: 44)
                }
            }
        }.navigationTitle("Laundry load").navigationBarTitleDisplayMode(.inline)
            .task(id: store.changes) { await load() }.refreshable { await load() }
            .sheet(item: $editing) { WardrobeLaundryEditor(store: store, load: $0) }
            .confirmationDialog(cancelling ? "Cancel this load? Active pieces return to Needs wash." : frozen?.progressTitle ?? "Confirm progress", isPresented: Binding(get: { frozen != nil }, set: { if !$0 { frozen = nil } }), titleVisibility: .visible) {
                if let record = frozen {
                    Button(cancelling ? "Cancel load" : record.progressTitle, role: cancelling ? .destructive : nil) {
                        do {
                            guard editable, record.version == read.value?.load.version else { throw WardrobeWriteError("The load changed. Refresh and review the intended step again.") }
                            guard cancelling || record.state != "planned" || !piecesPending else { throw WardrobeWriteError("Resolve pending garment saves before starting this load.") }
                            try store.submit(cancelling ? "laundry_cancel" : "laundry_progress", entity: id, title: record.name, fields: WardrobeDraftValidation.edit(id: id, version: record.version))
                        } catch { problem = error.localizedDescription }
                        frozen = nil
                    }
                }
            }
    }
    @ViewBuilder private func stamp(_ title: String, _ value: String?) -> some View {
        if let date = value.flatMap(GatewayAgentResult.date) { LabeledContent(title, value: date.formatted(date: .abbreviated, time: .shortened)) }
    }
    private func load() async {
        read.loading = true
        let result: WardrobeRead<WardrobeLaundryResult> = await store.read("laundry_get", input: WardrobeID(id: id))
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        do { if let load = result.value?.load { guard load.id == id else { throw WardrobeWriteError("The load identity changed.") }; try load.validate() }; read = result }
        catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
}

struct WardrobeLaundryEditor: View {
    let store: WardrobeStore
    let load: WardrobeLaundryLoad?
    let pending: WardrobePending?
    private let entity: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WardrobeLaundryDraft
    @State private var original: WardrobeLaundryDraft
    @State private var selected: Set<String>
    @State private var expectedVersion: Int64?
    @State private var latest: WardrobeLaundryLoad?
    @State private var preferences = WardrobeRead<WardrobePreferencesResult>()
    @State private var assistance: WardrobeLaundryAssistanceContext?
    @State private var planning: WardrobeLaundryAssistanceContext?
    @State private var preview = WardrobeRead<WardrobeLaundryPreview>()
    @State private var ready = false
    @State private var saved = false
    @State private var discarding = false
    @State private var problem: String?
    @State private var revision = 0
    @State private var care: WardrobeLaundryCandidate?
    @State private var editingPresets = false
    init(store: WardrobeStore, load: WardrobeLaundryLoad? = nil, pending: WardrobePending? = nil) {
        self.store = store; self.load = load; self.pending = pending; entity = load?.id ?? pending?.entity ?? UUID().uuidString.lowercased()
        let value = WardrobeLaundryDraft(load)
        _draft = State(initialValue: value); _original = State(initialValue: value)
        _selected = State(initialValue: Set(value.items.map(\.garment_id))); _expectedVersion = State(initialValue: load?.version)
    }
    private var editable: Bool { ready && !saved && store.isCurrentOwner && !store.writes.sending && (!store.writes.contains(entity) || pending?.rejected == true && store.writes.items.contains { $0.id == pending?.id && $0.rejected }) }
    private var candidates: [WardrobeLaundryCandidate] { preview.value?.groups.flatMap(\.items) ?? [] }
    private var presets: [WardrobeMachinePreset] { preferences.value?.preferences.machine_presets ?? [] }
    private var unavailable: Set<String> { selected.subtracting(Set(candidates.map(\.id))) }
    private var dirty: Bool { draft != original || selected != Set(original.items.map(\.garment_id)) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Review the actual programme and care groups. One load contains one colour group; Wash separately means one garment. These checks cover recorded care, not machine capacity or unrecorded label warnings.").font(.footnote)
                    // shortcut: unsaved laundry forms stay in memory; extend the draft journal if cross-launch form recovery is needed.
                    Text("Unsaved edits stay in this form. Saving queues a durable request; starting is a separate confirmation.").font(.footnote)
                    if !ready { ProgressView("Loading saved settings and load"); Button("Retry loading") { Task { await bootstrap() } }.frame(minHeight: 44) }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    if pending != nil { Text("Review the rejected intent against the latest load, then refresh groups and choose current pieces. Saving replaces only this rejected request with a new identity.").font(.footnote) }
                    if let latest, pending != nil { DisclosureGroup("Current saved load") { Text("\(latest.name) · \(latest.day) · version \(latest.version)"); Text(latest.program.summary); Text(latest.items.map { $0.snapshot.name }.joined(separator: ", ")) } }
                }
                Section("Plan") {
                    TextField("Load name", text: $draft.name)
                    DatePicker("Plan date", selection: Binding(get: { WardrobeDraftValidation.date(draft.day) ?? Date() }, set: { draft.day = WardrobeVocabulary.dayKey($0) }), displayedComponents: .date)
                    TextField("IANA time zone", text: $draft.time_zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("The date is a plan. Actual wash/dry confirmations get server timestamps. Future loads cannot start early.").font(.footnote)
                }.disabled(!editable)
                Section {
                    Button("Describe a laundry programme", systemImage: "text.bubble") {
                        let source = preferences.value?.preferences
                        assistance = .init(draft: draft, selected: selected, revision: store.changes, preferences: !preferences.cached && !(source.map { store.writes.contains($0.id) } ?? true) ? source : nil)
                    }.frame(minHeight: 44).disabled(!editable)
                    Text("Optional on-device interpretation. Review changes, then refresh compatibility and choose real pieces.").font(.footnote)
                }
                Section("Programme") {
                    Picker("Wash method", selection: Binding(get: { draft.program.wash_method }, set: { draft.program.method($0) })) {
                        Text("Machine wash").tag("machine"); Text("Hand wash").tag("hand"); Text("Dry clean").tag("dry_clean")
                    }
                    if draft.program.wash_method != "dry_clean" {
                        Stepper(draft.program.temperature_c.map { "Wash temperature: \($0) °C" } ?? "Wash temperature: unspecified", value: Binding(get: { draft.program.temperature_c ?? 20 }, set: { draft.program.temperature_c = $0 }), in: 0...95)
                        if draft.program.temperature_c == nil { Button("Use 20 °C") { draft.program.temperature_c = 20 }.frame(minHeight: 44) }
                        if draft.program.wash_method == "machine" { Picker("Cycle", selection: $draft.program.cycle) { Text("Choose a cycle").tag("unknown"); ForEach(["normal", "gentle", "delicate"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } } }
                        Picker("Drying", selection: $draft.program.drying) {
                            ForEach(["unknown", "line", "flat", "tumble_low", "tumble_normal"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
                            Text("Do not tumble — choose line or flat").tag("do_not_tumble")
                            Text("Professional — choose a home drying method").tag("professional")
                        }
                    } else { Text("Professional cleaning and return confirmation. No home wash temperature or machine cycle.").font(.footnote) }
                    if !presets.isEmpty { Menu("Use a saved machine preset") { ForEach(presets) { preset in Button(preset.name) { draft.program = .init(wash_method: "machine", temperature_c: preset.temperature_c, cycle: preset.cycle, drying: preset.drying); draft.name = preset.name } } } }
                    Text("Presets copy settings into this reviewed programme. Unknown drying needs a concrete choice. Cycles match confirmed care exactly; no gentler-cycle equivalence is assumed.").font(.footnote)
                    Button("Edit machine presets") { editingPresets = true }.frame(minHeight: 44)
                }.disabled(!editable)
                Section {
                    Button("Review compatible groups") { Task { await reviewGroups() } }.frame(minHeight: 44).disabled(!editable || preview.loading)
                    WardrobeReadStatus(state: preview) { await reviewGroups() }
                    if let result = preview.value { Text("\(result.inventory_count) active Needs wash garments assessed. Other availability states and archived pieces are outside this preview.").font(.footnote) }
                    Button("Plan batches around upcoming outfits", systemImage: "calendar") {
                        planning = .init(draft: draft, selected: selected, revision: store.changes, preferences: nil)
                    }.frame(minHeight: 44).disabled(!editable || preview.loading || preview.cached || preview.value == nil)
                }
                if let result = preview.value {
                    ForEach(result.groups) { group in
                        Section(WardrobeVocabulary.title(group.colour_group)) {
                            Button("Use this group") { selected = Set(group.items.map(\.id)) }.frame(minHeight: 44).disabled(!editable || group.items.count > 30 || preview.cached)
                            ForEach(group.items) { item in
                                Toggle(item.name, isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).disabled(!editable || preview.cached)
                                Text("Garment version \(item.version)").font(.caption)
                            }
                        }
                    }
                    Section("Needs review or a different programme") {
                        if result.blocked.isEmpty { Text("No blocked garments in this preview.").font(.footnote) }
                        ForEach(result.blocked) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name); Text(item.reason).font(.footnote)
                                Button("Review care instructions") { care = .init(garment_id: item.id, version: item.version, name: item.name) }.frame(minHeight: 44)
                            }
                        }
                    }
                }
                if !unavailable.isEmpty {
                    Section("Selected pieces needing fresh review") {
                        ForEach(unavailable.sorted(), id: \.self) { id in
                            Text(load?.items.first(where: { $0.id == id })?.snapshot.name ?? id).font(.footnote)
                            Button("Remove this selection") { selected.remove(id) }.frame(minHeight: 44).disabled(!editable)
                        }
                    }
                }
                Section { Text("\(selected.count) pieces selected · maximum 30").font(.footnote) }
            }.navigationTitle(load == nil && pending == nil ? "Plan laundry" : "Review laundry")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { discarding = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save plan", action: save).disabled(!editable || preview.loading || preview.cached || preview.value == nil || selected.isEmpty || selected.count > 30 || !unavailable.isEmpty) }
                }
                .interactiveDismissDisabled(!saved && dirty)
                .confirmationDialog("Discard these unsaved load edits?", isPresented: $discarding, titleVisibility: .visible) { Button("Discard edits", role: .destructive) { dismiss() } }
                .sheet(item: $care) { WardrobeSettingsView(store: store, record: .care($0.id)) }
                .sheet(isPresented: $editingPresets, onDismiss: { Task { await refreshPresets() } }) { WardrobeSettingsView(store: store, record: .preferences) }
                .sheet(item: $assistance) { context in
                    WardrobeLaundryAssistanceView(store: store, context: context) { program in
                        guard editable, store.changes == context.revision, draft == context.draft, selected == context.selected else { throw WardrobeWriteError("The laundry form changed. Interpret again before applying.") }
                        draft.program = program; revision += 1; preview = WardrobeRead()
                    }
                }
                .sheet(item: $planning) { context in
                    WardrobeLaundryPlanningView(store: store, context: context, current: {
                        editable && store.changes == context.revision && draft == context.draft && selected == context.selected
                    }) { planned, fresh in
                        guard editable, store.changes == context.revision, draft == context.draft, selected == context.selected,
                              planned.program == draft.program else { throw WardrobeWriteError("The load form changed. Reopen planning before applying a batch.") }
                        draft = planned; selected = Set(planned.items.map(\.garment_id)); revision += 1
                        preview = WardrobeRead(value: fresh, savedAt: GatewayAgentResult.date(fresh.generated_at))
                    }
                }
                .task { await bootstrap() }
                .onChange(of: draft.program) { _, _ in revision += 1; preview = WardrobeRead() }
                .onChange(of: store.changes) { _, _ in revision += 1; preview = WardrobeRead(); Task { await refreshPresets() } }
        }
    }
    private func bootstrap() async {
        ready = false; problem = nil
        await refreshPresets()
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        do {
            if load != nil || pending?.operation == "laundry_update" {
                let read: WardrobeRead<WardrobeLaundryResult> = await store.read("laundry_get", input: WardrobeID(id: entity))
                guard !read.cached, let value = read.value?.load, value.id == entity, value.state == "planned" else { throw WardrobeWriteError(read.problem ?? "Refresh the planned load before editing. Active loads cannot be changed.") }
                try value.validate()
                if let load { guard value.version == load.version else { throw WardrobeWriteError("The planned load changed. Reopen it before editing.") } }
                latest = value; expectedVersion = value.version
                if let pending { draft = try WardrobeLaundryDraft(request: pending, current: value) }
            } else if let pending { draft = try WardrobeLaundryDraft(request: pending) }
            guard store.isCurrentOwner, !Task.isCancelled else { return }
            selected = Set(draft.items.map(\.garment_id)); original = draft; ready = true
        } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
    }
    private func refreshPresets() async {
        let settings: WardrobeRead<WardrobePreferencesResult> = await store.read("preferences_get", input: WardrobeEmpty())
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        preferences = settings
    }
    private func reviewGroups() async {
        guard editable else { return }
        revision += 1; let current = revision; let program = draft.program; problem = nil
        do {
            try program.validate(); preview.loading = true
            let read: WardrobeRead<WardrobeLaundryPreview> = await store.read("laundry_preview", input: WardrobeLaundryPreviewInput(program: program))
            guard current == revision, program == draft.program, store.isCurrentOwner, !Task.isCancelled else { return }
            try read.value?.validate(program, cached: read.cached); preview = read
        } catch { if current == revision, store.isCurrentOwner, !Task.isCancelled { preview = WardrobeRead(problem: error.localizedDescription) } }
    }
    private func save() {
        guard editable, !preview.cached, let result = preview.value else { return }
        do {
            try result.validate(draft.program); draft.items = try result.selections(selected)
            guard !draft.items.contains(where: { store.writes.contains($0.garment_id) }) else { throw WardrobeWriteError("Wait for selected garment saves, then refresh groups.") }
            let values = try draft.fields(); let operation = expectedVersion == nil ? "laundry_create" : "laundry_update"
            var fields: [String: Any]
            if let expectedVersion { fields = WardrobeDraftValidation.edit(id: entity, version: expectedVersion); fields["patch"] = values }
            else { fields = values; fields["id"] = entity }
            if let pending { try store.writes.replaceRejected(pending.id, operation: operation, fields: fields); Task { await store.sync() } }
            else { try store.submit(operation, entity: entity, title: draft.name, fields: fields) }
            saved = true; dismiss()
        } catch { problem = error.localizedDescription }
    }
}
