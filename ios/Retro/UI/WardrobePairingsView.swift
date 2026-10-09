import SwiftUI

struct WardrobePairingsView: View {
    let store: WardrobeStore
    var garment: WardrobeGarment?
    @State private var read = WardrobeRead<WardrobePage<WardrobePairing>>()
    @State private var search = ""
    @State private var includeArchived = false
    @State private var adding = false
    @State private var revision = 0
    private var query: WardrobePairingQuery { WardrobePairingQuery(garmentID: garment?.id ?? "", search: search, includeArchived: includeArchived) }
    private var loadID: String { "\(search):\(includeArchived):\(store.changes)" }
    var body: some View {
        List {
            Section {
                Text(garment.map { "Combinations containing \($0.name)." } ?? "Reusable combinations and complete looks. Saving one does not create a plan or record a wear.").font(.footnote)
                Toggle("Include archived pairings", isOn: $includeArchived)
                WardrobeReadStatus(state: read) { await load() }
            }
            if let page = read.value {
                if page.items.isEmpty { Text("No saved pairings. Add a combination of at least two garments.") }
                ForEach(page.items) { pairing in
                    NavigationLink { WardrobePairingDetail(store: store, initial: pairing) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pairing.name).font(.headline)
                            Text(pairing.items.map { $0.snapshot?.name ?? "Garment" }.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                            if pairing.archivedAt != nil { Text("Archived").font(.caption) }
                            if store.writes.contains(pairing.id) { Text("Save pending").font(.caption) }
                        }.frame(minHeight: 44)
                    }
                }
                if page.nextCursor != nil { Button("Load more pairings") { Task { await load(more: true) } }.frame(minHeight: 44).disabled(read.loading) }
            }
        }.navigationTitle(garment == nil ? "Saved pairings" : "Goes with this")
            .searchable(text: $search, prompt: "Pairing name")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add pairing") { adding = true }.frame(minHeight: 44) } }
            .sheet(isPresented: $adding) { WardrobePairingEditor(store: store, pieces: garment.map { [WardrobeSelection(id: $0.id, name: $0.name, role: WardrobeDraftValidation.role($0.category))] } ?? []) }
            .task(id: loadID) { await load() }.refreshable { await load() }
    }
    private func load(more: Bool = false) async {
        revision += 1; let current = revision; let scope = query
        var input = scope
        if more { guard let cursor = read.value?.nextCursor else { return }; input.cursor = cursor }
        let previous = read
        if !more { read = WardrobeRead() }
        read.loading = true
        let result: WardrobeRead<WardrobePage<WardrobePairing>> = await store.read("pairings_list", input: input)
        guard current == revision, scope == query, store.isCurrentOwner, !Task.isCancelled else { return }
        do {
            for pairing in result.value?.items ?? [] { try pairing.validate() }
            if more, let page = result.value {
                let prior = previous.value?.items ?? []; let ids = Set(prior.map(\.id))
                read = result; read.value = WardrobePage(items: prior + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
            } else if more { read = previous; read.loading = false; read.problem = result.problem }
            else { read = result }
        } catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
}

struct WardrobePairingDetail: View {
    let store: WardrobeStore
    let initial: WardrobePairing
    @State private var read = WardrobeRead<WardrobePairingResult>()
    @State private var editing: WardrobePairing?
    @State private var date = Date()
    @State private var seed: WardrobeOutfitSeed?
    @State private var planning = false
    @State private var planTask: Task<Void, Never>?
    @State private var lifecycle: WardrobePairing?
    @State private var problem: String?
    var body: some View {
        let pairing = read.value?.pairing ?? initial
        List {
            Section {
                WardrobeReadStatus(state: read) { await load() }
                Text(pairing.name).font(.title2)
                if let notes = pairing.notes, !notes.isEmpty { Text(notes) }
                if pairing.archivedAt != nil { Text("Archived pairing") }
                if store.writes.contains(pairing.id) { Text("Save pending. Wait for acknowledgement before planning.").font(.footnote) }
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
            }
            Section("Current pieces") {
                ForEach(pairing.items) { item in
                    VStack(alignment: .leading) {
                        Text(item.snapshot?.name ?? "Garment")
                        Text(WardrobeVocabulary.title(item.role)).font(.footnote)
                        Text(item.snapshot?.archivedAt != nil ? "Archived garment" : WardrobeVocabulary.title(item.snapshot?.availability ?? "Unavailable")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Use as a plan") {
                DatePicker("Plan date", selection: $date, displayedComponents: .date).disabled(planning)
                Text("Refreshes the saved combination and current garments. The new plan is reviewed and saved separately.").font(.footnote)
                Button("Review new plan") { plan(pairing) }.frame(minHeight: 44).disabled(planning || read.loading || pairing.archivedAt != nil || store.writes.contains(pairing.id))
                if planning { ProgressView("Checking pairing and pieces") }
            }
            Section {
                Button("Edit pairing") { editing = pairing }.frame(minHeight: 44).disabled(read.loading || planning || pairing.archivedAt != nil || store.writes.contains(pairing.id))
                Button(pairing.archivedAt == nil ? "Archive pairing" : "Restore pairing") { lifecycle = pairing }.frame(minHeight: 44).disabled(read.loading || planning || store.writes.contains(pairing.id))
                NavigationLink("Pairing history") { WardrobeAuditView(store: store, entityType: "pairing", id: pairing.id) }.frame(minHeight: 44)
            }
        }.navigationTitle("Pairing").navigationBarTitleDisplayMode(.inline)
            .task(id: store.changes) { await load() }.refreshable { await load() }
            .sheet(item: $editing) { WardrobePairingEditor(store: store, pairing: $0) }
            .sheet(item: $seed) { WardrobeOutfitEditor(store: store, seed: $0.draft) }
            .onDisappear { planTask?.cancel() }
            .confirmationDialog("Change this pairing's archive status? Its garments and outfit history stay intact.", isPresented: Binding(get: { lifecycle != nil }, set: { if !$0 { lifecycle = nil } }), titleVisibility: .visible) {
                if let frozen = lifecycle {
                    Button(frozen.archivedAt == nil ? "Archive pairing" : "Restore pairing") {
                        do { try store.submit(frozen.archivedAt == nil ? "pairings_archive" : "pairings_restore", entity: frozen.id, title: frozen.name, fields: WardrobeDraftValidation.edit(id: frozen.id, version: frozen.version)) }
                        catch { problem = error.localizedDescription }
                        lifecycle = nil
                    }
                }
            }
    }
    private func load() async {
        read.loading = true
        let result: WardrobeRead<WardrobePairingResult> = await store.record("pairings_get", id: initial.id, fallback: WardrobePairingResult(pairing: initial))
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        do { try result.value?.pairing.validate(); read = result } catch { read = WardrobeRead(problem: error.localizedDescription) }
    }
    private func plan(_ pairing: WardrobePairing) {
        planning = true; problem = nil; let day = date
        planTask = Task {
            defer { planning = false }
            do {
                let draft = try await store.planPairing(pairing, date: day)
                guard store.isCurrentOwner, !Task.isCancelled, day == date else { return }
                seed = WardrobeOutfitSeed(draft: draft)
            } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
        }
    }
}

struct WardrobePairingEditor: View {
    let store: WardrobeStore
    let pairing: WardrobePairing?
    let pending: WardrobePending?
    private let entity: String
    private let original: WardrobePairingDraft
    private let restorationProblem: String?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WardrobePairingDraft
    @State private var picking = false
    @State private var discarding = false
    @State private var problem: String?
    @State private var saved = false
    init(store: WardrobeStore, pairing: WardrobePairing? = nil, pieces: [WardrobeSelection] = [], pending: WardrobePending? = nil) {
        self.store = store; self.pairing = pairing; self.pending = pending
        entity = pairing?.id ?? pending?.entity ?? UUID().uuidString.lowercased()
        let value = WardrobePairingDraft(pairing, items: pieces)
        original = value
        if let pending {
            do { _draft = State(initialValue: try WardrobePairingDraft(request: pending)); restorationProblem = nil }
            catch { _draft = State(initialValue: value); restorationProblem = error.localizedDescription }
        } else { _draft = State(initialValue: value); restorationProblem = nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Save a reusable combination, separately from dated plans and actual wears.").font(.footnote)
                    // shortcut: unsaved pairing edits stay in memory; extend the draft journal if cross-launch form recovery is needed.
                    Text("Unsaved edits stay in this form. Save queues a durable request before sending it.").font(.footnote)
                    if pending != nil { Text("Review the rejected create and its pieces. Save replaces that rejected request with a new request identity.").font(.footnote) }
                    if let restorationProblem { Text(restorationProblem).foregroundStyle(Tok.stamp) }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                Section("Pairing") {
                    TextField("Name", text: $draft.name)
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                    Button("Choose pieces · \(draft.items.count)/30") { picking = true }.frame(minHeight: 44)
                    ForEach($draft.items) { $piece in
                        VStack(alignment: .leading) {
                            Text(piece.name)
                            if piece.name == "Saved piece" { Text(piece.id).font(.caption).textSelection(.enabled) }
                            Picker("Role", selection: $piece.role) { ForEach(WardrobeDraftValidation.roles, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
                        }
                    }.onDelete { draft.items.remove(atOffsets: $0) }
                }
            }.navigationTitle(pairing == nil ? "Add pairing" : "Edit pairing").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != original { discarding = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(saved || restorationProblem != nil || (pending == nil && store.writes.contains(entity))) }
                }
        }.interactiveDismissDisabled(draft != original && !saved)
            .sheet(isPresented: $picking) { WardrobeGarmentPicker(store: store, items: $draft.items, historical: false, maximum: 30) }
            .confirmationDialog("Discard unsaved pairing edits?", isPresented: $discarding, titleVisibility: .visible) { Button("Discard edits", role: .destructive) { dismiss() } }
    }
    private func save() {
        guard !saved, restorationProblem == nil else { return }
        do {
            var fields = try draft.fields()
            let operation = pairing == nil ? "pairings_create" : "pairings_update"
            if let pairing {
                let patch = WardrobeDraftValidation.patch(fields, original: try original.fields())
                guard !patch.isEmpty else { dismiss(); return }
                fields = WardrobeDraftValidation.edit(id: entity, version: pairing.version); fields["patch"] = patch
            } else { fields["id"] = entity }
            if let pending {
                try store.writes.replaceRejected(pending.id, operation: operation, fields: fields)
                Task { await store.sync() }
            } else { try store.submit(operation, entity: entity, title: draft.name, fields: fields, context: draft.items.map(\.name).joined(separator: ", ")) }
            saved = true; dismiss()
        } catch { problem = error.localizedDescription }
    }
}
