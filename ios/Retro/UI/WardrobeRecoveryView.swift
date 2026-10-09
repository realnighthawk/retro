import SwiftUI

struct WardrobeRecoveryView: View {
    let store: WardrobeStore
    var pending: WardrobePending?
    var draft: WardrobeSavedDraft?
    @Environment(\.dismiss) private var dismiss
    @State private var requested: [String: WardrobeJSON] = [:]
    @State private var current: [String: WardrobeJSON] = [:]
    @State private var selected: Set<String> = []
    @State private var version: Int64?
    @State private var loading = false
    @State private var problem: String?
    @State private var saved = false
    private var entity: String { pending?.entity ?? draft?.entityID ?? "" }
    private var garment: Bool { pending?.operation.hasPrefix("garments_") ?? (draft?.garmentDraft != nil) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Compare your requested fields with the latest record. Only checked fields will be reapplied. This creates a new save with the reviewed version; the original request is never changed.").font(.footnote)
                    if loading { ProgressView("Loading latest record") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    Button("Refresh latest record") { Task { await load() } }.disabled(loading || saved)
                }
                ForEach(requested.keys.sorted(), id: \.self) { key in
                    Section(WardrobeVocabulary.title(key)) {
                        Text("Current: \(current[key]?.text ?? "Empty")")
                        Text("Requested: \(requested[key]?.text ?? "Empty")")
                        Toggle("Apply \(WardrobeVocabulary.title(key))", isOn: Binding(get: { selected.contains(key) }, set: { if $0 { selected.insert(key) } else { selected.remove(key) } }))
                    }
                }
                if !loading, version != nil, requested.isEmpty { Text("No supported field changes to reapply. Resume the editor for an incomplete draft, or remove a rejected lifecycle request and review the record.") }
            }.navigationTitle("Review latest record").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save selected", action: save).disabled(loading || version == nil || selected.isEmpty || saved) }
                }
        }.task { await load() }
    }
    private func load() async {
        loading = true; version = nil; selected = []; requested = [:]; current = [:]; problem = nil
        defer { loading = false }
        do {
            let fields: [String: Any]
            if garment {
                let read: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: entity))
                guard !read.cached, let value = read.value else { throw WardrobeWriteError(read.problem ?? "A fresh record is needed before reapplying edits.") }
                guard value.garment.archivedAt == nil else { throw WardrobeWriteError("Restore this garment before editing its fields.") }
                version = value.garment.version; fields = try WardrobeGarmentDraft(value.garment).fields()
            } else {
                let read: WardrobeRead<WardrobeOutfitResult> = await store.read("outfits_get", input: WardrobeID(id: entity))
                guard !read.cached, let value = read.value else { throw WardrobeWriteError(read.problem ?? "A fresh record is needed before reapplying edits.") }
                guard value.outfit.state != "void" else { throw WardrobeWriteError("Restore this outfit before correcting it.") }
                version = value.outfit.version; fields = try WardrobeOutfitDraft(value.outfit).fields()
            }
            try Task.checkCancellation(); guard store.isCurrentOwner else { return }
            current = try JSONDecoder().decode([String: WardrobeJSON].self, from: JSONSerialization.data(withJSONObject: fields))
            var changes: [String: Any]
            if let pending, let body = try JSONSerialization.jsonObject(with: pending.body) as? [String: Any] { changes = (body["patch"] as? [String: Any]) ?? body }
            else if let draft, let edited = draft.garmentDraft, draft.garment != nil || draft.dependency != nil { changes = WardrobeDraftValidation.patch(try edited.fields(), original: try draft.originalGarment().fields()) }
            else if let draft, let edited = draft.outfitDraft, !draft.confirming, draft.outfit != nil || draft.dependency != nil { changes = WardrobeDraftValidation.patch(try edited.fields(), original: try draft.originalOutfit().fields()) }
            else { throw WardrobeWriteError("Resume this draft in its editor. Create and confirm flows need their full review.") }
            let allowed = Set(garment ? ["name", "category", "availability", "subtype", "colours", "warmth", "seasons", "formality", "material", "brand", "notes", "favourite"] : ["day", "time_zone", "label", "occasion", "notes", "items"])
            changes = changes.filter { allowed.contains($0.key) }
            requested = try JSONDecoder().decode([String: WardrobeJSON].self, from: JSONSerialization.data(withJSONObject: changes))
        } catch { version = nil; if !Task.isCancelled, store.isCurrentOwner { problem = error.localizedDescription } }
    }
    private func save() {
        guard !saved, let version else { return }
        do {
            let chosen = requested.filter { selected.contains($0.key) }
            guard !chosen.isEmpty else { return }
            let patch = try JSONSerialization.jsonObject(with: JSONEncoder().encode(chosen))
            var fields = WardrobeDraftValidation.edit(id: entity, version: version); fields["patch"] = patch
            let operation = garment ? "garments_update" : "outfits_update"
            if let pending { try store.writes.replaceRejected(pending.id, operation: operation, fields: fields); Task { await store.sync() } }
            else { try store.submit(operation, entity: entity, title: draft?.title ?? "Reviewed edits", fields: fields) }
            saved = true
            if let draft { try store.drafts.remove(draft.id) }
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}
