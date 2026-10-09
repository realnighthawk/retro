import SwiftUI

struct WardrobeLaundryAssistanceContext: Identifiable {
    let id = UUID()
    let draft: WardrobeLaundryDraft
    let selected: Set<String>
    let revision: Int
    let preferences: WardrobePreferences?
}

struct WardrobeLaundryAssistanceView: View {
    let store: WardrobeStore
    let context: WardrobeLaundryAssistanceContext
    let onApply: (WardrobeLaundryProgram) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var text = ""
    @State private var proposal: WardrobeLaundryRequest?
    @State private var selected: Set<String> = []
    @State private var acceptedLimitations = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var ticket = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Describe a programme") {
                    TextField("For example: machine wash at 20 °C, gentle, line dry", text: $text, axis: .vertical).lineLimit(3...6).disabled(task != nil)
                    WardrobeVoiceInput(store: store, text: $text, byteLimit: 2000)
                    Text("Interpretation stays on this device. It changes programme controls only; choose pieces, dates and progress in the laundry form.").font(.footnote)
                    if let reason = GarmentAssistance.unavailableReason { Text(reason).font(.footnote) }
                    if let preferences = context.preferences, !preferences.machine_presets.isEmpty {
                        Text("You can explicitly name a saved preset: " + preferences.machine_presets.map(\.name).joined(separator: ", ")).font(.footnote)
                    } else { Text("No fresh saved presets are supplied. Enter explicit settings or choose a preset in the laundry form.").font(.footnote) }
                    if task != nil { ProgressView("Working on this device"); Button("Cancel assistance", action: cancel).frame(minHeight: 44) }
                    else { Button("Interpret laundry request", action: interpret).frame(minHeight: 44).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || GarmentAssistance.unavailableReason != nil) }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                if let proposal {
                    Section("Review proposed changes") {
                        if proposal.patch.isEmpty { Text("No supported programme changes. Use the manual controls.") }
                        ForEach(proposal.patch.keys.sorted(), id: \.self) { key in
                            Toggle("\(WardrobeSettingFields.label(key)): \(proposal.value(key))", isOn: Binding(get: { selected.contains(key) }, set: { if $0 { selected.insert(key) } else { selected.remove(key) } })).disabled(task != nil)
                            Text("Request: \(proposal.evidence[key] ?? "")").font(.caption)
                        }
                        if let next = try? proposal.applying(selected, to: context.draft.program, acceptedLimitations: true) {
                            Text("Programme after selected changes: " + next.summary).font(.footnote)
                            if next.temperature_c == nil && next.wash_method != "dry_clean" { Text("Wash temperature is still unspecified.").font(.footnote) }
                            if (try? next.validate()) == nil { Text("This programme needs more manual choices before compatibility review.").font(.footnote) }
                        }
                        Text("Unchanged controls keep their current values. A wash-method change clears incompatible machine/professional settings; it does not invent home wash temperatures or drying choices.").font(.footnote)
                    }
                    if !proposal.unhandled.isEmpty {
                        Section("Conditions not applied") {
                            ForEach(Array(proposal.unhandled.enumerated()), id: \.offset) { _, value in Text(value) }
                            Toggle("Use only the selected settings above", isOn: $acceptedLimitations).disabled(task != nil)
                        }
                    }
                    Section {
                        Button("Apply reviewed programme changes", action: apply).frame(minHeight: 44).disabled(task != nil || selected.isEmpty || !proposal.unhandled.isEmpty && !acceptedLimitations)
                        Text("Applying returns to the form. Refresh compatible groups and review real pieces before saving. No load is saved or started here.").font(.footnote)
                    }
                }
            }.navigationTitle("Describe laundry").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onChange(of: text) { _, _ in cancel() }
        .onChange(of: store.changes) { _, _ in cancel(); problem = "Wardrobe saves changed. Reopen assistance from the current form." }
        .onChange(of: phase) { _, value in if value == .background { cancel() } }
        .onDisappear { cancel() }
    }
    private func cancel() { ticket = UUID(); task?.cancel(); timeout?.cancel(); task = nil; proposal = nil; selected = []; acceptedLimitations = false }
    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard ticket == id, store.isCurrentOwner, store.changes == context.revision else { throw WardrobeWriteError("The account or wardrobe changed. Reopen assistance before applying.") }
    }
    private func startTimeout(_ id: UUID) {
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard ticket == id, store.isCurrentOwner else { return }
            cancel(); problem = "Assistance timed out. Use the manual controls or try again."
        }
    }
    private func interpret() {
        cancel(); problem = nil; let input = text; let id = ticket
        startTimeout(id)
        task = Task { @MainActor in
            defer { if ticket == id { task = nil; timeout?.cancel() } }
            do {
                try check(id)
                let value = try await WardrobeLaundryIntelligence.interpret(input, preferences: context.preferences)
                try check(id)
                guard input == text else { return }
                proposal = value; selected = Set(value.patch.keys)
            } catch { if !Task.isCancelled, store.isCurrentOwner, ticket == id { problem = error.localizedDescription } }
        }
    }
    private func apply() {
        guard let proposal else { return }
        let keys = selected; let accepted = acceptedLimitations; let id = ticket; problem = nil
        startTimeout(id)
        task = Task { @MainActor in
            defer { if ticket == id { task = nil; timeout?.cancel() } }
            do {
                try check(id)
                let program = try proposal.applying(keys, to: context.draft.program, acceptedLimitations: accepted)
                if keys.contains("machine_preset") {
                    let fresh: WardrobeRead<WardrobePreferencesResult> = await store.read("preferences_get", input: WardrobeEmpty())
                    try check(id)
                    try proposal.checkPreset(fresh.value?.preferences, cached: fresh.cached, pending: proposal.source.map { store.writes.contains($0.id) } ?? true)
                }
                try check(id); try onApply(program); dismiss()
            } catch { if !Task.isCancelled, store.isCurrentOwner, ticket == id { problem = error.localizedDescription } }
        }
    }
}
