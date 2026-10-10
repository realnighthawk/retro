import SwiftUI

// P4.6: pick several garments, review one frozen request each, and watch the durable queue report what
// actually happened per item. Photos, laundry and imports keep their own single-item queues.
struct WardrobeBatchView: View {
    let store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var action = WardrobeBatchAction.available
    @State private var query = WardrobeInventoryQuery()
    @State private var garments: [WardrobeGarment] = []
    @State private var cursor: String?
    @State private var selected: Set<String> = []
    @State private var queued: Set<String> = []
    @State private var plan: WardrobeBatchPlan?
    @State private var refused: [String] = []
    @State private var problem: String?
    @State private var loading = false
    @State private var confirming = false
    @State private var revision = 0
    private var items: [WardrobeBatchItem] { garments.map(WardrobeBatchItem.init) }

    var body: some View {
        NavigationStack {
            List {
                Section("What to do") {
                    Picker("Action", selection: $action) { ForEach(WardrobeBatchAction.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: action) { _, _ in selected = []; plan = nil; Task { await load(more: false) } }
                    Text(action.isDestructive
                         ? "Archiving hides the garments from your wardrobe until you restore them. Existing outfits and history stay intact."
                         : "Each selected garment becomes its own request, saved on this phone before it is sent. Unavailable pieces or ones with a pending save are left out.").font(.footnote)
                }
                Section(action.needsArchived ? "Archived garments" : "Garments") {
                    TextField("Filter by name", text: $query.search)
                    if loading && garments.isEmpty { ProgressView() }
                    ForEach(garments.filter(fits)) { garment in
                        let item = WardrobeBatchItem(garment)
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else if WardrobeBatchPlan.reason(action, item) == nil { selected.insert(item.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : WardrobeBatchPlan.reason(action, item) == nil ? "circle" : "slash.circle")
                                    .foregroundStyle(selected.contains(item.id) ? Tok.accent : Tok.faint)
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text(WardrobeBatchPlan.reason(action, item) ?? item.stateTitle).font(.caption).foregroundStyle(Tok.faint)
                                }
                            }.frame(minHeight: 44)
                        }.disabled(WardrobeBatchPlan.reason(action, item) != nil || store.writes.contains(item.id))
                    }
                    if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
                    if garments.isEmpty && !loading { Text("No garments to show here.").font(.footnote) }
                    HStack {
                        Button("Select all shown") { selected.formUnion(garments.filter { WardrobeBatchPlan.reason(action, WardrobeBatchItem($0)) == nil && !store.writes.contains($0.id) }.map(\.id)) }
                        Button("Clear selection") { selected = [] }
                    }.font(.subheadline)
                    Text("\(selected.count) selected of \(garments.count) loaded" + (cursor != nil ? " (more pages exist)" : "")).font(.footnote)
                }
                if let plan {
                    Section("Review") {
                        Text(plan.summary)
                        ForEach(plan.items) { item in
                            Text("\(item.name) · \(item.stateTitle) → \(action.title) at version \(item.version)").font(.subheadline)
                        }
                        ForEach(Array(plan.skipped.enumerated()), id: \.offset) { _, reason in Text("Not included — \(reason)").font(.footnote).foregroundStyle(Tok.faint) }
                        Button(action.isDestructive ? "Archive \(plan.items.count) garments…" : "Queue \(plan.items.count) changes", action: submit)
                            .frame(minHeight: 44).disabled(plan.items.isEmpty || store.writes.sending)
                    }
                } else if !selected.isEmpty {
                    Section("Review") {
                        Button("Review \(selected.count) changes", action: build).frame(minHeight: 44).disabled(loading)
                    }
                }
                if !queued.isEmpty {
                    Section("Outcomes") {
                        Text("Each garment reports its own result. Nothing is claimed saved until the engine acknowledges it, and a refused item stays in Pending saves for review.").font(.footnote)
                        ForEach(queued.sorted(), id: \.self) { id in
                            let outcome = WardrobeBatchReport.outcome(id, pending: store.writes.items, acknowledged: store.writes.acknowledgedIDs, queued: queued)
                            VStack(alignment: .leading) {
                                Text(name(id)).font(.subheadline)
                                Text(outcome.title).font(.caption).foregroundStyle(outcome.isFailure ? Tok.stamp : Tok.faint)
                            }.frame(minHeight: 44)
                        }
                        ForEach(Array(refused.enumerated()), id: \.offset) { _, reason in Text("Not queued — \(reason)").font(.footnote).foregroundStyle(Tok.stamp) }
                        Text("Retry or review the individual items in Pending saves.").font(.footnote)
                    }
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp) } }
            }
            .navigationTitle("Maintain garments").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Refresh") { Task { await load(more: false) } }.disabled(loading) }
            }
            .task(id: action) { await load(more: false) }
            .refreshable { await load(more: false) }
            .onChange(of: phase) { _, value in if value == .active { Task { await load(more: false) } } }
        }
        .confirmationDialog(action.isDestructive ? "Archive \(plan?.items.count ?? 0) garments? You can restore them later." : "Queue these changes?", isPresented: $confirming, titleVisibility: .visible) {
            Button(action.isDestructive ? "Archive" : "Queue", role: action.isDestructive ? .destructive : nil) { enqueue() }
        }
    }
    private func name(_ id: String) -> String { garments.first { $0.id == id }?.name ?? (plan?.items.first { $0.id == id }?.name ?? "Garment") }
    private func fits(_ garment: WardrobeGarment) -> Bool { (garment.archivedAt != nil) == action.needsArchived }
    private func load(more: Bool) async {
        guard store.isCurrentOwner, !loading else { return }
        revision += 1; let ticket = revision
        var input = WardrobeInventoryQuery()
        input.search = query.search; input.includeArchived = action.needsArchived; input.limit = 50
        input.cursor = more ? cursor : nil
        loading = true
        defer { loading = false }
        let result = await store.choices(input)
        guard store.isCurrentOwner, !Task.isCancelled, ticket == revision else { return }
        guard case .ok(let page) = result else { problem = result.problem; return }
        problem = nil
        cursor = page.nextCursor
        garments = more ? garments + page.items.filter { fresh in !garments.contains { $0.id == fresh.id } } : page.items
        selected = selected.intersection(Set(garments.map(\.id)))
    }
    private func build() {
        plan = WardrobeBatchPlan.build(action: action, selected: items.filter { selected.contains($0.id) },
                                       pending: Set(store.writes.items.map(\.entity)), pendingCount: store.writes.items.count)
        refused = []
    }
    private func submit() {
        if action.isDestructive { confirming = true } else { enqueue() }
    }
    private func enqueue() {
        guard let plan else { return }
        let result = store.runBatch(plan)
        queued.formUnion(result.queued); refused = result.refused
        selected = []; self.plan = nil
        Task { await load(more: false) }
    }
}
