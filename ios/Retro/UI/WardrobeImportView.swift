import SwiftUI
import PhotosUI

struct WardrobeImportView: View {
    let store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [PhotosPickerItem] = []
    @State private var working = false
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose one photo per garment. Review and save each item, then accept its photo. You can close this screen and resume here later.")
                    Text("Photos stay on this phone until you accept an attachment. Each completed item is independent.").font(.footnote)
                    PhotosPicker(selection: $selected, maxSelectionCount: min(10, max(1, 20 - store.drafts.imports.count)), matching: .images) { Label("Choose garment photos", systemImage: "photo.on.rectangle") }.disabled(working || store.drafts.imports.count >= 20)
                    if working { ProgressView("Keeping photos on this phone") }
                    if let problem = problem ?? store.drafts.problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                Section("To review · \(store.drafts.imports.count)/20") {
                    if store.drafts.imports.isEmpty { Text("No import photos waiting.").foregroundStyle(Tok.faint) }
                    ForEach(store.drafts.imports.sorted { $0.updatedAt < $1.updatedAt }) { entry in
                        NavigationLink {
                            WardrobeImportItemView(store: store, id: entry.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.title)
                                Text(store.writes.contains(entry.entityID) ? "Garment save pending" : store.photos.contains(entry.entityID) ? "Photo attachment pending" : entry.importMediaID != nil ? "Check photo acknowledgement" : entry.dependency != nil || entry.garment != nil ? "Accept photo next" : "Review garment next").font(.caption).foregroundStyle(Tok.faint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add from photos")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(working) } }
        }
        .interactiveDismissDisabled(working)
        .task(id: selected) {
            guard !selected.isEmpty else { return }
            working = true; problem = nil
            let picks = selected
            defer { working = false; selected = [] }
            for (index, pick) in picks.enumerated() {
                do {
                    try Task.checkCancellation()
                    guard let data = try await pick.loadTransferable(type: Data.self) else { throw WardrobeWriteError("Photo could not be opened.") }
                    let bytes = try await Task.detached { try PhotoPreparation.normalize(data) }.value
                    try Task.checkCancellation()
                    try store.drafts.addImport(bytes)
                } catch { problem = "Photo \(index + 1) was not kept: \(error.localizedDescription) Earlier photos can still be reviewed."; break }
            }
        }
    }
}

struct WardrobeImportItemView: View {
    let store: WardrobeStore
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var bytes: Data?
    @State private var editor = false
    @State private var choosing = false
    @State private var candidate: WardrobeGarment?
    @State private var removing = false
    @State private var problem: String?
    @State private var work: Task<Void, Never>?
    @State private var busy = false
    @State private var scan: WardrobeDuplicateScan?
    private var entry: WardrobeSavedDraft? { store.drafts.items.first { $0.id == id } }
    var body: some View {
        List {
            if let entry {
                Section {
                    if let bytes, let image = PhotoPreparation.display(bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320).accessibilityLabel("Selected garment photo") }
                    Text(entry.title).font(.headline)
                    Text("1. Review garment details. 2. Wait for its save. 3. Accept this photo. 4. Finish after acknowledgement.").font(.footnote)
                    Button("Review garment details") { editor = true }.disabled(busy || entry.importMediaID != nil)
                    if entry.garment == nil && entry.dependency == nil && !store.writes.contains(entry.entityID) {
                        Button("Choose an existing garment") { choosing = true }.disabled(busy)
                        Button("Check the whole wardrobe for similar items", action: compare).disabled(bytes == nil || busy)
                        if let scan { Text(scan.summary).font(.footnote) }
                        ForEach(scan?.hints ?? []) { hint in
                            Button {
                                run {
                                    // The hint belongs to one scan of one photo: the same bytes must
                                    // still be this draft's photo, and the record must still match.
                                    guard let scan, let bytes, scan.matches(source: bytes) else {
                                        throw WardrobeWriteError("This photo changed since the check. Check again.")
                                    }
                                    let fresh = try await store.importGarment(hint.id)
                                    guard fresh.version == hint.photo.version, (fresh.mediaIDs ?? []).contains(hint.photo.mediaID) else { throw WardrobeWriteError("That item or its photo changed. Check again.") }
                                    candidate = fresh
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    if let image = PhotoPreparation.display(hint.photo.bytes) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).accessibilityLabel("Existing garment photo") }
                                    Text("Review existing: \(hint.photo.name)")
                                }.frame(minHeight: 44)
                            }.disabled(busy)
                        }
                    }
                    if store.writes.contains(entry.entityID) { Text("Garment save pending. Check Pending saves for errors or retry.") }
                    if store.photos.contains(entry.entityID) { Text("Photo work is pending. Its saved request and bytes are kept for retry.") }
                    Button(entry.importMediaID == nil ? "Accept photo attachment" : "Resume photo attachment") { run { try await store.attachImport(id) } }.disabled(busy || store.writes.contains(entry.entityID))
                    Button("Check acknowledgement and finish") { run { try await store.finishImport(id); dismiss() } }.disabled(busy || entry.importMediaID == nil)
                    Button("Remove from import…", role: .destructive) { removing = true }.disabled(busy)
                }
            } else { Text("This import item is finished.") }
            if busy { ProgressView(); Button("Cancel current check") { work?.cancel() } }
            if let problem { Text(problem).foregroundStyle(Tok.stamp) }
        }
        .navigationTitle("Review photo").navigationBarTitleDisplayMode(.inline)
        .task(id: id) { do { bytes = try await store.drafts.importBytes(id) } catch { problem = error.localizedDescription } }
        .sheet(isPresented: $editor) { if let entry { WardrobeGarmentEditor(store: store, resume: entry) } }
        .sheet(isPresented: $choosing) {
            WardrobeImportPicker(store: store) { garment in choosing = false; candidate = garment }
        }
        .confirmationDialog("Use \(candidate?.name ?? "this garment")? This replaces the unsaved new garment details.", isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }), titleVisibility: .visible) {
            if let candidate { Button("Use existing garment") { self.candidate = nil; run { try await store.useExistingImport(id, garment: candidate); scan = nil } } }
        }
        .confirmationDialog("Remove this local import item? Queued garment saves and accepted photo work continue. An unaccepted photo draft stays in Pending saves.", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove local import", role: .destructive) { do { try store.drafts.remove(id); dismiss() } catch { problem = error.localizedDescription } }
        }
        .onDisappear { work?.cancel() }
        .onChange(of: phase) { _, value in if value != .active { work?.cancel() } }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; problem = nil
        work = Task {
            defer { busy = false }
            do { try await action() } catch { if !Task.isCancelled { problem = error.localizedDescription } }
        }
    }
    private func compare() {
        guard let bytes, let source = entry?.importPhoto else { return }
        scan = nil
        run {
            // The scan is bound to these exact bytes; a finished or replaced draft never keeps a scan.
            let result = try await Self.scan(store: store, bytes: bytes)
            guard store.isCurrentOwner, !Task.isCancelled, entry?.importPhoto?.id == source.id else { return }
            scan = result
        }
    }
    private static func scan(store: WardrobeStore, bytes: Data) async throws -> WardrobeDuplicateScan? {
        try await withThrowingTaskGroup(of: WardrobeDuplicateScan?.self) { group in
            group.addTask { await store.duplicateScan(source: bytes) }
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw WardrobeWriteError("The wardrobe check took too long. It stopped without changing anything.")
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

private struct WardrobeImportPicker: View {
    let store: WardrobeStore
    let choose: (WardrobeGarment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = WardrobeInventoryQuery()
    @State private var values: [WardrobeGarment] = []
    @State private var cursor: String?
    @State private var problem: String?
    @State private var loading = false
    @State private var revision = 0
    var body: some View {
        NavigationStack {
            List {
                Text("Review a current garment before accepting a photo. This does not merge or delete garments.").font(.footnote)
                ForEach(values) { value in Button(value.name) { choose(value) }.disabled(loading) }
                if loading { ProgressView() }
                if let problem { Text(problem).foregroundStyle(Tok.stamp); Button("Retry") { Task { await load(more: false) } }.disabled(loading) }
                if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
                if values.isEmpty && !loading && problem == nil { Text("No matching garments") }
            }
            .navigationTitle("Existing garment").searchable(text: $query.search)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query.search) { await load(more: false) }
        }
    }
    private func load(more: Bool) async {
        revision += 1; let ticket = revision
        let search = query.search
        var input = query; input.cursor = more ? cursor : nil
        if !more { values = []; cursor = nil }
        loading = true; problem = nil
        let result = await store.choices(input)
        guard store.isCurrentOwner, !Task.isCancelled, query.search == search, ticket == revision else { return }
        loading = false
        if case .ok(let page) = result {
            let active = page.items.filter { $0.archivedAt == nil }
            values = more ? values + active.filter { value in !values.contains { $0.id == value.id } } : active
            cursor = page.nextCursor
        } else { problem = result.problem }
    }
}
