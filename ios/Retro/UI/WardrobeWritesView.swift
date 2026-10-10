import SwiftUI
import UIKit

struct WardrobeGarmentEditor: View {
    let store: WardrobeStore
    let garment: WardrobeGarment?
    private let entry: WardrobeSavedDraft
    private let original: WardrobeGarmentDraft
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WardrobeGarmentDraft
    @State private var problem: String?
    @State private var saved = false
    @State private var discarding = false
    @State private var assistance = false
    @State private var receipt = false
    @State private var importImage: UIImage?

    init(store: WardrobeStore, garment: WardrobeGarment? = nil, resume: WardrobeSavedDraft? = nil) {
        let saved = resume ?? store.drafts.garment(garment?.id)
        self.store = store; self.garment = saved?.garment ?? garment
        let value = saved ?? WardrobeSavedDraft(id: UUID().uuidString.lowercased(), entityID: garment?.id ?? UUID().uuidString.lowercased(), garment: garment, outfit: nil, confirming: false, garmentDraft: WardrobeGarmentDraft(garment), outfitDraft: nil)
        entry = value
        original = (try? value.originalGarment()) ?? WardrobeGarmentDraft(garment)
        _draft = State(initialValue: saved?.garmentDraft ?? WardrobeGarmentDraft(garment))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let importImage { Image(uiImage: importImage).resizable().scaledToFit().frame(maxHeight: 280).accessibilityLabel("Selected garment photo") }
                    Text("Edits are kept on this phone and can be resumed from Pending saves. They do not change confirmed records.").font(.footnote)
                    if entry.dependency != nil { Text("These are later edits to the queued create. Keep them locally, then review selected fields after acknowledgement. A rejected create can be replaced explicitly.").font(.footnote) }
                    if store.writes.contains(entry.entityID) { Text("This record has a pending save. Keep editing here; review against the latest record after it is acknowledged.").font(.footnote) }
                    if let problem = store.drafts.problem { Text(problem).foregroundStyle(Tok.stamp) }
                    Button("Capture assistance") { assistance = true }
                    Text(entry.importPhoto == nil ? "Photos are optional. Save the garment first, then add or manage its photos from the garment detail." : "Save the garment, then return to this photo review to accept its attachment.").font(.footnote)
                }
                Section("Garment") {
                    TextField("Name", text: $draft.name)
                    choice("Category", $draft.category, WardrobeVocabulary.categories)
                    choice("Availability", $draft.availability, WardrobeVocabulary.availability)
                    Toggle("Favourite", isOn: $draft.favourite)
                }
                Section("Optional details") {
                    TextField("Subtype", text: $draft.subtype)
                    TextField("Colours, separated by commas", text: $draft.colours)
                    choice("Warmth", $draft.warmth, WardrobeDraftValidation.warmths)
                    TextField("Seasons, separated by commas", text: $draft.seasons)
                    TextField("Formality", text: $draft.formality)
                    TextField("Material", text: $draft.material)
                    TextField("Brand", text: $draft.brand)
                    TextField("Pattern", text: $draft.patternText)
                    TextField("Style", text: $draft.styleText)
                    TextField("Fit you chose", text: $draft.fitText)
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                }
                Section("Purchase · optional") {
                    TextField("Date, for example 2026-03-02", text: $draft.purchaseDraft.date)
                    HStack {
                        TextField("Amount", text: $draft.purchaseDraft.amount).keyboardType(.decimalPad)
                        TextField("Currency", text: $draft.purchaseDraft.currency).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    Button("Read a receipt or price label") { receipt = true }.frame(minHeight: 44)
                    choice("Recorded from", $draft.purchaseDraft.source, WardrobeDraftValidation.purchaseSources)
                    if draft.purchaseDraft.source != "manual" {
                        TextField("Evidence, for example the receipt total", text: $draft.purchaseDraft.evidence, axis: .vertical).lineLimit(2...5)
                    }
                    Text("Money is kept as an exact amount in one currency; Retro never converts or totals across currencies. Leave every field empty for an unknown price. Fit, pattern and style are your own description, not read from the garment.").font(.footnote)
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp).accessibilityAddTraits(.updatesFrequently) } }
                Section { Text("Save stores this request on this phone before sending it. Check Pending saves for acknowledgement.").font(.footnote) }
            }
            .navigationTitle(garment == nil ? "Add garment" : "Edit garment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != original { discarding = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button(entry.dependency == nil ? "Save" : rejectedCreate ? "Replace create" : "Keep draft", action: save).disabled(saved || (entry.dependency == nil && store.writes.contains(entry.entityID))) }
            }
        }
        .interactiveDismissDisabled(draft != original && !saved)
        .sheet(isPresented: $assistance) { GarmentAssistanceView(store: store, draft: $draft) }
        .sheet(isPresented: $receipt) { WardrobeReceiptView(store: store, draft: $draft) }
        .task(id: entry.importPhoto?.id) {
            guard entry.importPhoto != nil else { return }
            do { let bytes = try await store.drafts.importBytes(entry.id); if store.isCurrentOwner, !Task.isCancelled { importImage = PhotoPreparation.display(bytes) } }
            catch { if !Task.isCancelled { problem = error.localizedDescription } }
        }
        .onAppear { if draft != original { persist() } }
        .onChange(of: draft) { _, _ in if !saved { persist() } }
        .confirmationDialog("Keep or discard garment edits?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Keep draft") { do { try store.drafts.put(currentEntry); dismiss() } catch { problem = error.localizedDescription } }
            Button("Discard edits", role: .destructive) { do { try store.drafts.remove(entry.id); dismiss() } catch { problem = error.localizedDescription } }
        }
    }
    private var rejectedCreate: Bool { entry.dependency.map { original in store.writes.items.contains { $0.id == original.id && $0.rejected && $0.operation == original.operation } } ?? false }
    private var currentEntry: WardrobeSavedDraft { var value = entry; value.garmentDraft = draft; return value }
    private func persist() { do { if draft == original && entry.dependency == nil && entry.importPhoto == nil { try store.drafts.remove(entry.id) } else { try store.drafts.put(currentEntry) } } catch { problem = error.localizedDescription } }
    private func save() {
        guard !saved else { return }
        do {
            if entry.dependency != nil, !rejectedCreate {
                try store.drafts.put(currentEntry); dismiss(); return
            }
            var fields = try draft.fields()
            let id = entry.entityID
            if let garment {
                let patch = WardrobeDraftValidation.patch(fields, original: try WardrobeGarmentDraft(garment).fields())
                guard !patch.isEmpty else { if entry.importPhoto == nil { try store.drafts.remove(entry.id) }; dismiss(); return }
                fields = WardrobeDraftValidation.edit(id: id, version: garment.version); fields["patch"] = patch
            } else { fields["id"] = id }
            try store.drafts.put(currentEntry)
            let accepted: WardrobePending?
            if let dependency = entry.dependency {
                try store.writes.replaceRejected(dependency.id, operation: dependency.operation, fields: fields)
                accepted = store.writes.items.first { $0.entity == id }
                Task { await store.sync() }
            } else { accepted = try store.submit(garment == nil ? "garments_create" : "garments_update", entity: id, title: draft.name, fields: fields) }
            saved = true
            if entry.importPhoto != nil {
                var value = currentEntry
                if garment == nil { value.dependency = accepted }
                else { value.garmentDraft = original }
                try store.drafts.put(value)
            } else { try store.drafts.remove(entry.id) }
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct WardrobeOutfitEditor: View {
    let store: WardrobeStore
    let outfit: WardrobeOutfit?
    let confirming: Bool
    private let entry: WardrobeSavedDraft
    private let original: WardrobeOutfitDraft
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WardrobeOutfitDraft
    @State private var problem: String?
    @State private var saved = false
    @State private var discarding = false
    @State private var selecting = false

    init(store: WardrobeStore, outfit: WardrobeOutfit? = nil, date: Date = Date(), confirming: Bool = false, seed: WardrobeOutfitDraft? = nil, resume: WardrobeSavedDraft? = nil) {
        let saved = resume ?? (seed == nil ? store.drafts.outfit(outfit?.id, confirming: confirming) : nil)
        let base = saved?.outfit ?? outfit
        self.store = store; self.outfit = base; self.confirming = confirming
        var draft = saved?.outfitDraft ?? seed ?? WardrobeOutfitDraft(base, date: date)
        if confirming { draft.state = "worn" }
        var baseline = (try? saved?.originalOutfit()) ?? WardrobeOutfitDraft(base, date: draft.date)
        if confirming { baseline.state = "worn" }
        original = baseline
        entry = saved ?? WardrobeSavedDraft(id: UUID().uuidString.lowercased(), entityID: base?.id ?? UUID().uuidString.lowercased(), garment: nil, outfit: base, confirming: confirming, garmentDraft: nil, outfitDraft: draft)
        _draft = State(initialValue: draft)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Edits are kept on this phone and can be resumed from Pending saves.").font(.footnote)
                    if entry.dependency != nil { Text("Keep later edits locally, then review selected fields after acknowledgement. The queued outfit keeps its planned or worn state.").font(.footnote) }
                    if store.writes.contains(entry.entityID) { Text("Wait for the pending save, then review against the latest record before saving these edits.").font(.footnote) }
                    if let problem = store.drafts.problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                Section("When") {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date).disabled(confirming)
                    TextField("IANA time zone", text: $draft.timeZone).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(confirming)
                    if outfit == nil && entry.dependency == nil { choice("Save as", $draft.state, ["planned", "worn"]) }
                    else if entry.dependency == nil { Text(confirming ? "Review the pieces you actually wore." : "Editing a recorded outfit corrects its history.").font(.footnote) }
                    if outfit?.state == "worn" {
                        Text("Changing pieces or roles refreshes garment facts for the whole outfit. Other edits keep the saved garment facts.").font(.footnote)
                    }
                }
                Section("Pieces · \(draft.items.count)/30") {
                    ForEach($draft.items) { $selection in
                        VStack(alignment: .leading) {
                            Text(selection.name).font(.headline)
                            choice("Role", $selection.role, WardrobeDraftValidation.roles)
                            Button("Remove \(selection.name)", role: .destructive) { draft.items.removeAll { $0.id == selection.id } }.frame(minHeight: 44)
                        }
                    }
                    Button("Choose garments") { selecting = true }.frame(minHeight: 44)
                    Text("Several layers and accessories are allowed. Wearing never changes laundry availability automatically.").font(.footnote)
                }
                if !confirming {
                    Section("Optional details") {
                        TextField("Label", text: $draft.label)
                        TextField("Occasion", text: $draft.occasion)
                        TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                    }
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp) } }
                Section { Text("Pending wears do not count until Retro acknowledges them.").font(.footnote) }
            }
            .navigationTitle(confirming ? "Record wear" : outfit == nil ? "Compose outfit" : "Correct outfit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if draft != original { discarding = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button(entry.dependency != nil ? (rejectedCreate ? "Replace create" : "Keep draft") : confirming ? "Record wear" : "Save", action: save).disabled(saved || (entry.dependency == nil && store.writes.contains(entry.entityID))) }
            }
            .sheet(isPresented: $selecting) { WardrobeGarmentPicker(store: store, items: $draft.items, historical: draft.state == "worn" && !confirming) }
        }
        .interactiveDismissDisabled(draft != original && !saved)
        .onAppear { if draft != original { persist() } }
        .onChange(of: draft) { _, _ in if !saved { persist() } }
        .confirmationDialog("Keep or discard outfit edits?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Keep draft") { do { try store.drafts.put(currentEntry); dismiss() } catch { problem = error.localizedDescription } }
            Button("Discard edits", role: .destructive) { do { try store.drafts.remove(entry.id); dismiss() } catch { problem = error.localizedDescription } }
        }
    }
    private var rejectedCreate: Bool { entry.dependency.map { original in store.writes.items.contains { $0.id == original.id && $0.rejected && $0.operation == original.operation } } ?? false }
    private var currentEntry: WardrobeSavedDraft { var value = entry; value.outfitDraft = draft; return value }
    private func persist() { do { if draft == original && entry.dependency == nil { try store.drafts.remove(entry.id) } else { try store.drafts.put(currentEntry) } } catch { problem = error.localizedDescription } }
    private func save() {
        guard !saved else { return }
        do {
            if entry.dependency != nil, !rejectedCreate { try store.drafts.put(currentEntry); dismiss(); return }
            guard !draft.items.contains(where: { store.writes.contains($0.id) }) else { throw WardrobeWriteError("Wait for the selected garments' pending saves, then review this outfit.") }
            var fields = try draft.fields()
            let id = entry.entityID
            let operation: String
            if let outfit {
                if confirming {
                    fields = WardrobeDraftValidation.edit(id: id, version: outfit.version)
                    fields["items"] = draft.items.map(\.fields); operation = "outfits_confirm"
                } else {
                    let patch = WardrobeDraftValidation.patch(fields, original: try WardrobeOutfitDraft(outfit).fields())
                    guard !patch.isEmpty else { try store.drafts.remove(entry.id); dismiss(); return }
                    fields = WardrobeDraftValidation.edit(id: id, version: outfit.version); fields["patch"] = patch
                    operation = "outfits_update"
                }
            } else { fields["id"] = id; fields["state"] = draft.state; fields["source"] = draft.source; operation = "outfits_create" }
            try store.drafts.put(currentEntry)
            if let dependency = entry.dependency {
                fields["state"] = original.state; fields["source"] = original.source
                try store.writes.replaceRejected(dependency.id, operation: dependency.operation, fields: fields)
                Task { await store.sync() }
            } else {
                try store.submit(operation, entity: id, title: draft.label.isEmpty ? "Outfit · \(WardrobeVocabulary.dayKey(draft.date))" : draft.label, fields: fields,
                                 context: "Pieces: " + draft.items.map { "\($0.name) (\(WardrobeVocabulary.title($0.role)))" }.joined(separator: ", "))
            }
            saved = true
            try store.drafts.remove(entry.id)
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct WardrobeGarmentPicker: View {
    let store: WardrobeStore
    @Binding var items: [WardrobeSelection]
    let historical: Bool
    var maximum = 30
    var onlyReady = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = WardrobeInventoryQuery()
    @State private var page: WardrobePage<WardrobeGarment>?
    @State private var problem: String?
    @State private var loading = false
    @State private var revision = 0
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Loading garments") }
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                ForEach(page?.items ?? []) { garment in
                    let selected = items.contains { $0.id == garment.id }
                    Button {
                        if selected { items.removeAll { $0.id == garment.id } }
                        else if maximum == 1 { items = [WardrobeSelection(id: garment.id, name: garment.name, role: WardrobeDraftValidation.role(garment.category))] }
                        else { items.append(WardrobeSelection(id: garment.id, name: garment.name, role: WardrobeDraftValidation.role(garment.category))) }
                        assert(items.count <= maximum)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(garment.name)
                                Text(garment.archivedAt == nil ? WardrobeVocabulary.title(garment.availability) : "Archived").font(.footnote)
                            }
                            Spacer(); if selected { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }.disabled(store.writes.contains(garment.id) || (!selected && maximum != 1 && items.count >= maximum))
                    .accessibilityLabel("\(garment.name), \(selected ? "selected" : "not selected")")
                }
                if page?.nextCursor != nil { Button("Load more garments") { Task { await load(more: true) } }.disabled(loading) }
                if !loading, page?.items.isEmpty == true { Text("No matching garments") }
            }
            .navigationTitle("Choose garments").searchable(text: $query.search, prompt: "Search garment names")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query.search) { query.includeArchived = historical; query.availability = onlyReady ? "ready" : ""; await load(more: false) }
        }
    }
    private func load(more: Bool) async {
        revision += 1
        let ticket = revision
        var input = query
        if more { input.cursor = page?.nextCursor } else { page = nil }
        let search = input.search
        loading = true; problem = nil
        let result = await store.choices(input)
        guard !Task.isCancelled, store.isCurrentOwner, ticket == revision, search == query.search else { return }
        loading = false
        if case .ok(let result) = result {
            page = WardrobePage(items: ((more ? page?.items : nil) ?? []).merging(result.items), nextCursor: result.nextCursor)
        } else {
            if !more {
                let fallback = store.inventory.value?.items.filter { (historical || $0.archivedAt == nil) && (!onlyReady || $0.availability == "ready") && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } ?? []
                page = WardrobePage(items: fallback, nextCursor: nil)
            }
            problem = (result.problem ?? "Could not load garments.") + " Previously loaded choices may be incomplete."
        }
    }
}

struct WardrobePendingView: View {
    let store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var resumingPhotos: WardrobePhotoDraft?
    @State private var discardingPhotos: WardrobePhotoDraft?
    @State private var resuming: WardrobeSavedDraft?
    @State private var reviewingDraft: WardrobeSavedDraft?
    @State private var reviewing: WardrobePending?
    @State private var discardingDraft: WardrobeSavedDraft?
    @State private var current: [String: String] = [:]
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Saved on this phone. Confirmed history and counts change only after acknowledgement.")
                    Button(store.writes.sending ? "Sending…" : "Retry pending saves") { Task { await store.sync(force: true) } }.disabled(store.writes.sending)
                    if let problem = store.writes.problem ?? problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                if let problem = store.drafts.problem { Text(problem).foregroundStyle(Tok.stamp) }
                ForEach(store.drafts.items) { draft in
                    Section("Draft · " + draft.title) {
                        Text(draft.importPhoto == nil ? "Local draft · not sent" : "Photo import · resume to check save and attachment progress").font(.footnote)
                        Button("Resume editing") { resuming = draft }.frame(minHeight: 44)
                        if draft.dependency != nil || draft.garment != nil || (draft.outfit != nil && !draft.confirming) {
                            Button("Review against latest record") { reviewingDraft = draft }.frame(minHeight: 44).disabled(store.writes.contains(draft.entityID))
                        }
                        if let dependency = draft.dependency {
                            Text("The original create keeps its request identity. After acknowledgement, review only these later edits against the current record.").font(.footnote)
                            Button("Retry original create") {
                                do { try store.writes.restoreCreate(dependency); Task { await store.sync(force: true) } } catch { problem = error.localizedDescription }
                            }.frame(minHeight: 44).disabled(store.writes.sending || (store.writes.contains(draft.entityID) && !store.writes.items.contains { $0.id == dependency.id }))
                        }
                        Button("Discard draft", role: .destructive) { discardingDraft = draft }.frame(minHeight: 44)
                    }
                }
                ForEach(store.photos.drafts) { draft in
                    Section("Photo draft · " + draft.garment.name) {
                        Text("Local photo edits · not sent").font(.footnote)
                        Button("Resume photo edits") { resumingPhotos = draft }.frame(minHeight: 44)
                        Button("Discard photo draft", role: .destructive) { discardingPhotos = draft }.frame(minHeight: 44)
                    }
                }
                WardrobePhotoJobs(store: store)
                if store.writes.items.isEmpty && store.photos.batches.isEmpty && store.drafts.items.isEmpty && store.photos.drafts.isEmpty { Text("No pending saves or drafts") }
                ForEach(store.writes.items) { item in
                    Section(item.title) {
                        Text(item.rejected ? "Needs review · server rejected this save" : item.dispatched ? "Awaiting acknowledgement" : "Queued")
                        if let problem = item.problem { Text(problem).foregroundStyle(Tok.stamp) }
                        Text(item.createdAt.formatted()).font(.footnote)
                        if ["garments_create", "outfits_create"].contains(item.operation) {
                            Button("Continue editing locally") { do { resuming = try store.drafts.follow(item, names: Dictionary((store.inventory.value?.items ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { _, latest in latest })) } catch { problem = error.localizedDescription } }.frame(minHeight: 44)
                        }
                        if item.rejected {
                            Text("Compare requested changes with the latest record. Reapply selected fields with a new save, or remove this rejected request before editing manually.").font(.footnote)
                            if item.operation.hasPrefix("laundry_") {
                                Button(["laundry_create", "laundry_update"].contains(item.operation) ? "Review laundry programme and current pieces" : "Inspect current laundry progress") { reviewing = item }.frame(minHeight: 44)
                            }
                            if ["garments_update", "garments_create", "outfits_update", "outfits_create", "preferences_update", "outfits_feedback_update", "pairings_create", "pairings_update", "wardrobe_day_selection_update", "wardrobe_daily_settings_update"].contains(item.operation), !store.photos.batches.contains(where: { $0.attachmentKey == item.id }) {
                                Button(item.operation == "wardrobe_day_selection_update" || item.operation == "pairings_create" ? "Review requested save" : "Review and reapply selected fields") { reviewing = item }.frame(minHeight: 44)
                            }
                            Text(item.requestedSummary).font(.footnote).textSelection(.enabled)
                            Button("Load current record") { Task { current[item.id] = await store.currentSummary(item) } }
                            if let summary = current[item.id] { Text(summary).font(.footnote) }
                        }
                        if !item.dispatched || item.rejected {
                            Button(item.rejected ? "Remove rejected request" : "Remove unsent request", role: .destructive) {
                                do { try store.writes.remove(item) } catch { problem = error.localizedDescription }
                            }.disabled(store.writes.sending)
                        } else { Text("Retry to reconcile this request before removing it.").font(.footnote) }
                    }
                }
            }
            .task {
                for _ in 0..<15 {
                    await store.sync()
                    guard !Task.isCancelled, !store.photos.batches.isEmpty else { return }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
            .sheet(item: $resumingPhotos) { WardrobePhotosView(store: store, garment: $0.garment) }
            .confirmationDialog("Discard this local photo draft?", isPresented: Binding(get: { discardingPhotos != nil }, set: { if !$0 { discardingPhotos = nil } }), titleVisibility: .visible) {
                Button("Discard photo draft", role: .destructive) { if let draft = discardingPhotos { do { try store.photos.discardDraft(draft.id) } catch { problem = error.localizedDescription } }; discardingPhotos = nil }
            }
            .sheet(item: $resuming) { entry in
                if entry.importPhoto != nil { NavigationStack { WardrobeImportItemView(store: store, id: entry.id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { resuming = nil } } } } }
                else if entry.garmentDraft != nil { WardrobeGarmentEditor(store: store, garment: entry.garment, resume: entry) }
                else { WardrobeOutfitEditor(store: store, outfit: entry.outfit, confirming: entry.confirming, resume: entry) }
            }
            .sheet(item: $reviewing) { item in
                if ["laundry_create", "laundry_update"].contains(item.operation) { WardrobeLaundryEditor(store: store, pending: item) }
                else if item.operation.hasPrefix("laundry_") { NavigationStack { WardrobeLaundryDetail(store: store, id: item.entity).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reviewing = nil } } } } }
                else if item.operation == "pairings_create" { WardrobePairingEditor(store: store, pending: item) }
                else if item.operation == "wardrobe_day_selection_update" {
                    if let request = try? WardrobeDayChoiceRequest(request: item) {
                        WardrobeDaySelectionView(store: store, day: request.day, outfitID: request.outfitID, pending: item)
                    } else { Text("The original daily selection could not be opened. Keep the request and review its stored fields.") }
                } else { WardrobeRecoveryView(store: store, pending: item) }
            }
            .sheet(item: $reviewingDraft) { WardrobeRecoveryView(store: store, draft: $0) }
            .confirmationDialog("Discard this local draft?", isPresented: Binding(get: { discardingDraft != nil }, set: { if !$0 { discardingDraft = nil } }), titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { if let draft = discardingDraft { do { try store.drafts.remove(draft.id) } catch { problem = error.localizedDescription } }; discardingDraft = nil }
            }
            .navigationTitle("Pending saves")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

@ViewBuilder private func choice(_ title: String, _ selection: Binding<String>, _ values: [String]) -> some View {
    Picker(title, selection: selection) { ForEach(values, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
}

private extension Array where Element == WardrobeGarment {
    func merging(_ other: [WardrobeGarment]) -> [WardrobeGarment] {
        let ids = Set(map(\.id)); return self + other.filter { !ids.contains($0.id) }
    }
}
