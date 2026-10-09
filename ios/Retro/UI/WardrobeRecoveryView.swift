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
    @State private var outfitVersion: Int64?
    @State private var outfitSummary: String?
    @State private var loading = false
    @State private var problem: String?
    @State private var saved = false
    private var entity: String { pending?.entity ?? draft?.entityID ?? "" }
    private var garment: Bool { pending?.operation.hasPrefix("garments_") ?? (draft?.garmentDraft != nil) }
    private var preferences: Bool { pending?.operation == "preferences_update" }
    private var dailySettings: Bool { pending?.operation == "wardrobe_daily_settings_update" }
    private var feedback: Bool { pending?.operation == "outfits_feedback_update" }
    private var pairing: Bool { pending?.operation.hasPrefix("pairings_") == true }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Compare your requested fields with the latest record. Only checked fields will be reapplied. This creates a new save with the reviewed version; the original request is never changed.").font(.footnote)
                    if loading { ProgressView("Loading latest record") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    if let outfitSummary { Text(outfitSummary) }
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
            if dailySettings {
                let read: WardrobeRead<WardrobeDailySettingsResult> = await store.read("wardrobe_daily_settings_get", input: WardrobeEmpty())
                guard !read.cached, let value = read.value, value.settings.id == entity else { throw WardrobeWriteError(read.problem ?? "Fresh daily settings are needed.") }
                try value.settings.validate()
                version = value.settings.version; fields = try WardrobeSettingFields.object(value.settings)
            } else if preferences {
                let read: WardrobeRead<WardrobePreferencesResult> = await store.read("preferences_get", input: WardrobeEmpty())
                guard !read.cached, let value = read.value, value.preferences.id == entity else { throw WardrobeWriteError(read.problem ?? "A fresh settings record is needed.") }
                version = value.preferences.version; fields = try WardrobeSettingFields.object(value.preferences)
            } else if feedback {
                guard let pending, let body = try JSONSerialization.jsonObject(with: pending.body) as? [String: Any], let id = body["outfit_id"] as? String else { throw WardrobeWriteError("Missing outfit identity.") }
                let read: WardrobeRead<WardrobeFeedbackResult> = await store.read("outfits_feedback_get", input: WardrobeID(id: id))
                guard !read.cached, let value = read.value, value.feedback.id == entity, value.outfit_state == "worn" else { throw WardrobeWriteError(read.problem ?? "Restore or record this wear before editing feedback.") }
                let outfit: WardrobeRead<WardrobeOutfitResult> = await store.read("outfits_get", input: WardrobeID(id: id))
                guard !outfit.cached, let o = outfit.value?.outfit, o.version == value.current_outfit_version else { throw WardrobeWriteError("The outfit changed while loading. Refresh before reviewing feedback.") }
                outfitSummary = "Review current wear: \(o.title) · \(o.day) · \(o.items.map { $0.snapshot?.name ?? $0.garmentID }.joined(separator: ", "))"
                version = value.feedback.version; outfitVersion = o.version; fields = try WardrobeSettingFields.object(value.feedback)
            } else if pairing {
                let read: WardrobeRead<WardrobePairingResult> = await store.read("pairings_get", input: WardrobeID(id: entity))
                guard !read.cached, let value = read.value, value.pairing.id == entity, value.pairing.archivedAt == nil else { throw WardrobeWriteError(read.problem ?? "Restore or refresh the pairing before editing it.") }
                try value.pairing.validate()
                version = value.pairing.version; fields = try WardrobePairingDraft(value.pairing).fields()
            } else if garment {
                let read: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: entity))
                guard !read.cached, let value = read.value else { throw WardrobeWriteError(read.problem ?? "A fresh record is needed before reapplying edits.") }
                guard value.garment.archivedAt == nil else { throw WardrobeWriteError("Restore this garment before editing its fields.") }
                version = value.garment.version
                var garmentFields = try WardrobeGarmentDraft(value.garment).fields()
                if let care = value.garment.care { garmentFields["care"] = try WardrobeSettingFields.object(care) }
                else { garmentFields["care"] = NSNull() }
                if let reminder = value.garment.laundryReminder { garmentFields["laundry_reminder"] = try WardrobeSettingFields.object(reminder) }
                else { garmentFields["laundry_reminder"] = NSNull() }
                fields = garmentFields
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
            let allowed = Set(dailySettings ? WardrobeDailySettings.keys : preferences ? WardrobeSettingFields.preferences + ["machine_presets"] : feedback ? WardrobeSettingFields.feedback : pairing ? ["name", "notes", "items"] : garment ? ["name", "category", "availability", "subtype", "colours", "warmth", "seasons", "formality", "material", "brand", "notes", "favourite", "care", "laundry_reminder"] : ["day", "time_zone", "label", "occasion", "notes", "items"])
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
            let operation = dailySettings ? "wardrobe_daily_settings_update" : preferences ? "preferences_update" : feedback ? "outfits_feedback_update" : pairing ? "pairings_update" : garment ? "garments_update" : "outfits_update"
            if feedback, let pending, let body = try JSONSerialization.jsonObject(with: pending.body) as? [String: Any] {
                guard let outfitVersion else { throw WardrobeWriteError("Review the current wear before saving feedback.") }
                fields["outfit_id"] = body["outfit_id"]; fields["expected_outfit_version"] = outfitVersion
            }
            if let pending { try store.writes.replaceRejected(pending.id, operation: operation, fields: fields); Task { await store.sync() } }
            else { try store.submit(operation, entity: entity, title: draft?.title ?? "Reviewed edits", fields: fields) }
            saved = true
            if var draft {
                if draft.importPhoto != nil { draft.garmentDraft = try draft.originalGarment(); try store.drafts.put(draft) }
                else { try store.drafts.remove(draft.id) }
            }
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}
