import SwiftUI

struct WardrobeSettingsView: View {
    let store: WardrobeStore
    let record: WardrobeSettingsRecord
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Any] = [:]
    @State private var entity = ""
    @State private var version: Int64?
    @State private var outfitVersion: Int64?
    @State private var loading = false
    @State private var editable = false
    @State private var problem: String?
    @State private var notice: String?
    @State private var auditType = ""
    @State private var resetCare = false
    private var keys: [String] { switch record { case .preferences: WardrobeSettingFields.preferences; case .care: WardrobeSettingFields.care; case .feedback: WardrobeSettingFields.feedback } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading { ProgressView("Loading current settings") }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                    if let notice { Text(notice).font(.footnote) }
                    if !editable { Button("Try again") { Task { await load() } }.disabled(loading) }
                    if !entity.isEmpty, store.writes.contains(entity) { Text("A save is pending. Review it in Pending saves.").font(.footnote) }
                }
                if version != nil {
                    Section {
                        ForEach(keys, id: \.self) { key in setting(key, values: $values) }
                    }.disabled(!editable || resetCare)
                    switch record {
                    case .preferences:
                        presets.disabled(!editable)
                        Section { Text("Temperatures are stored in Celsius. Saved preferences do not yet change outfit suggestions.").font(.footnote) }
                    case .care:
                        WardrobeCareLabelScan(store: store, values: $values).disabled(!editable || resetCare)
                        Section {
                            Text("Read the garment label before confirming. Leave uncertain settings Unknown. Confirmation does not place the garment into a laundry load.").font(.footnote)
                            Toggle("Remove saved care instructions", isOn: $resetCare).disabled(!editable)
                        }
                    case .feedback:
                        Section {
                            Text("Ratings are optional, from 1 to 5. Feedback records your experience; it does not change wears or availability.").font(.footnote)
                            Button("Clear all feedback") { for key in keys { values[key] = key == "warmth" ? "unknown" : NSNull() } }.disabled(!editable)
                        }
                    }
                    if !auditType.isEmpty, version! > 0 {
                        NavigationLink("Record history") { WardrobeAuditView(store: store, entityType: auditType, id: entity) }
                    }
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, *), editable {
                        WardrobeSettingsAssistance(store: store, record: record, values: $values)
                    }
                    #endif
                }
            }
            .navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(loading || !editable || version == nil || store.writes.contains(entity)) }
            }
        }.task { await load() }
    }

    @ViewBuilder private func setting(_ key: String, values: Binding<[String: Any]>, preset: Bool = false) -> some View {
        let label = WardrobeSettingFields.label(key)
        if WardrobeSettingFields.booleans.contains(key) {
            Toggle(label, isOn: Binding(get: { values.wrappedValue[key] as? Bool ?? false }, set: { values.wrappedValue[key] = $0 }))
        } else if let choices = WardrobeSettingFields.choices[key] {
            Picker(label, selection: Binding(get: { values.wrappedValue[key] as? String ?? choices[0] }, set: { values.wrappedValue[key] = $0 })) {
                ForEach(choices.filter { !preset || key != "cycle" || $0 != "unknown" }, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) }
            }
        } else {
            TextField(label, text: Binding(get: {
                if let list = values.wrappedValue[key] as? [String] { return list.joined(separator: ", ") }
                guard let value = values.wrappedValue[key], !(value is NSNull) else { return "" }
                return String(describing: value)
            }, set: { text in
                if WardrobeSettingFields.lists.contains(key) { values.wrappedValue[key] = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                else if WardrobeSettingFields.ranges[key] != nil { values.wrappedValue[key] = text.isEmpty ? NSNull() : (Int(text).map { $0 as Any } ?? text) }
                else { values.wrappedValue[key] = text }
            }), axis: key == "evidence" || key == "comment" ? .vertical : .horizontal)
            .keyboardType(WardrobeSettingFields.ranges[key] != nil ? .numbersAndPunctuation : .default)
        }
    }
    private var presets: some View {
        Section("Machine presets") {
            let list = values["machine_presets"] as? [[String: Any]] ?? []
            ForEach(list.indices, id: \.self) { index in
                ForEach(WardrobeSettingFields.preset, id: \.self) { key in
                    setting(key, values: Binding(get: { let list = values["machine_presets"] as? [[String: Any]] ?? []; return list.indices.contains(index) ? list[index] : [:] }, set: { updated in
                        var list = values["machine_presets"] as? [[String: Any]] ?? []; guard list.indices.contains(index) else { return }; list[index] = updated; values["machine_presets"] = list
                    }), preset: true)
                }
                Button("Remove \(list[index]["name"] as? String ?? "preset")", role: .destructive) {
                    var list = values["machine_presets"] as? [[String: Any]] ?? []; list.remove(at: index); values["machine_presets"] = list
                }
            }
            Button("Add machine preset") {
                var list = values["machine_presets"] as? [[String: Any]] ?? []
                list.append(["id": UUID().uuidString.lowercased(), "name": "Cold wash", "temperature_c": 20, "cycle": "gentle", "drying": "unknown"])
                values["machine_presets"] = list
            }.disabled(list.count >= 10)
        }
    }
    private func load() async {
        loading = true; editable = false; problem = nil; version = nil
        defer { loading = false }
        do {
            switch record {
            case .preferences:
                let read: WardrobeRead<WardrobePreferencesResult> = await store.read("preferences_get", input: WardrobeEmpty())
                guard let result = read.value else { throw WardrobeWriteError(read.problem ?? "Settings could not be loaded.") }
                values = try WardrobeSettingFields.object(result.preferences); entity = result.preferences.id; version = result.preferences.version; auditType = "preferences"
                editable = !read.cached; problem = read.problem
            case .care(let id):
                let read: WardrobeRead<WardrobeGarmentResult> = await store.read("garments_get", input: WardrobeID(id: id))
                guard let result = read.value else { throw WardrobeWriteError(read.problem ?? "Garment could not be loaded.") }
                values = try WardrobeSettingFields.object(result.garment.care ?? WardrobeCare()); entity = id; version = result.garment.version; auditType = "garment"
                values["id"] = result.garment.id; values["version"] = result.garment.version
                editable = !read.cached && result.garment.archivedAt == nil; problem = read.problem
            case .feedback(let id):
                let read: WardrobeRead<WardrobeFeedbackResult> = await store.read("outfits_feedback_get", input: WardrobeID(id: id))
                guard let result = read.value else { throw WardrobeWriteError(read.problem ?? "Feedback could not be loaded.") }
                values = try WardrobeSettingFields.object(result.feedback); entity = result.feedback.id; version = result.feedback.version; outfitVersion = result.current_outfit_version; auditType = "feedback"
                editable = !read.cached && result.outfit_state == "worn"; problem = read.problem
                let outfit: WardrobeRead<WardrobeOutfitResult> = await store.read("outfits_get", input: WardrobeID(id: id))
                guard !outfit.cached, let o = outfit.value?.outfit, o.version == result.current_outfit_version else { editable = false; throw WardrobeWriteError("Load the current outfit before reviewing feedback. Try again.") }
                values["reviewed_outfit_version"] = o.version
                notice = "Current wear: \(o.title) · \(o.day) · \(o.items.map { $0.snapshot?.name ?? $0.garmentID }.joined(separator: ", "))"
                if result.outfit_state != "worn" { notice = "Feedback can be edited after a wear is recorded. Restore void history before editing.\n" + (notice ?? "") }
                else if result.feedback.version > 0 && result.feedback.outfit_version != result.current_outfit_version { notice = "This outfit has been corrected. Review the current wear before saving feedback again.\n" + (notice ?? "") }
            }
            guard store.isCurrentOwner, !Task.isCancelled else { editable = false; values = [:]; version = nil; return }
            if !editable && notice == nil { notice = "Previously loaded settings. Reopen when connected before editing." }
        } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription } }
    }
    private func save() {
        guard let version, editable else { return }
        do {
            if !resetCare { try WardrobeSettingFields.validate(values, keys: keys) }
            var fields = WardrobeDraftValidation.edit(id: entity, version: version)
            let operation: String
            switch record {
            case .preferences:
                let presets = values["machine_presets"] as? [[String: Any]] ?? []
                for preset in presets { try WardrobeSettingFields.validate(preset, keys: WardrobeSettingFields.preset) }
                fields["patch"] = WardrobeSettingFields.patch(values, keys: keys + ["machine_presets"]); operation = "preferences_update"
            case .care:
                let care: Any = resetCare ? NSNull() : WardrobeSettingFields.patch(values, keys: keys)
                fields["patch"] = ["care": care]; operation = "garments_update"
            case .feedback(let id):
                guard let outfitVersion else { throw WardrobeWriteError("Review the current wear before saving feedback.") }
                fields["outfit_id"] = id; fields["expected_outfit_version"] = outfitVersion
                fields["patch"] = WardrobeSettingFields.patch(values, keys: keys); operation = "outfits_feedback_update"
            }
            try store.submit(operation, entity: entity, title: record.title, fields: fields)
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}
