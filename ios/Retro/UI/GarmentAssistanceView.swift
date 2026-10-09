import SwiftUI
import PhotosUI

struct GarmentAssistanceView: View {
    let store: WardrobeStore
    @Binding var draft: WardrobeGarmentDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var description = ""
    @State private var label = ""
    @State private var scan: PhotosPickerItem?
    @State private var suggestion: WardrobeAssistedDraft?
    @State private var baseline: WardrobeGarmentDraft?
    @State private var busy = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var useName = true
    @State private var useCategory = true
    @State private var useSubtype = true
    @State private var useColours = true
    @State private var useNotes = false
    var body: some View {
        NavigationStack {
            Form {
                Section("On this device") {
                    Text("Describe the garment or scan its label. Suggestions use this text only; they do not inspect garment photos.").font(.footnote)
                    TextField("Garment description", text: $description, axis: .vertical).lineLimit(3...6)
                    PhotosPicker(selection: $scan, matching: .images) { Label("Scan a label", systemImage: "text.viewfinder") }.disabled(busy)
                    if !label.isEmpty { TextField("Recognized label text — check for errors", text: $label, axis: .vertical).lineLimit(3...8) }
                    Text("Label photos and discarded suggestions stay local. Brand and material need readable label evidence or your own input.").font(.footnote)
                    if let reason = GarmentAssistance.unavailableReason { Text(reason).font(.footnote) }
                    Button("Suggest details", action: suggest).disabled(busy || GarmentAssistance.unavailableReason != nil || (description + label).isEmpty)
                    if busy { ProgressView("Working on this device"); Button("Cancel assistance") { invalidate() } }
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp) } }
                if let suggestion {
                    Section("Review before applying") {
                        if let name = suggestion.name { Toggle("Name: \(name)", isOn: $useName) }
                        if let category = suggestion.category { Toggle("Category: \(WardrobeVocabulary.title(category))", isOn: $useCategory) }
                        if let subtype = suggestion.subtype { Toggle("Subtype: \(subtype)", isOn: $useSubtype) }
                        if !suggestion.colours.isEmpty { Toggle("Colours: \(suggestion.colours.joined(separator: ", "))", isOn: $useColours) }
                        if let notes = suggestion.notes { Toggle("Replace notes with: \(notes)", isOn: $useNotes) }
                        Text("Selected fields replace the form's current values. You can edit them before saving; applying a suggestion never saves a garment.").font(.footnote)
                        Button("Apply selected suggestions") {
                            guard store.isCurrentOwner, baseline == draft else { problem = "The garment form changed. Generate a fresh suggestion before applying it."; return }
                            if useName, let value = suggestion.name { draft.name = value }
                            if useCategory, let value = suggestion.category { draft.category = value }
                            if useSubtype, let value = suggestion.subtype { draft.subtype = value }
                            if useColours, !suggestion.colours.isEmpty { draft.colours = suggestion.colours.joined(separator: ", ") }
                            if useNotes, let value = suggestion.notes { draft.notes = value }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Capture assistance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: description) { _, _ in invalidate() }
            .onChange(of: label) { _, _ in invalidate() }
            .onChange(of: scan) { _, item in
                guard let item else { return }
                invalidate(); busy = true; problem = nil
                task = Task {
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self) else { throw WardrobeWriteError("This label photo could not be opened.") }
                        let normalized = try await Task.detached { try PhotoPreparation.normalize(bytes) }.value
                        let text = try await PhotoPreparation.labelText(normalized)
                        guard store.isCurrentOwner, !Task.isCancelled else { return }
                        label = String(text.prefix(2000))
                        if text.isEmpty { problem = "No readable text was found. Type the details manually." }
                        busy = false
                    } catch { if !Task.isCancelled { problem = error.localizedDescription; busy = false } }
                }
            }
            .onChange(of: phase) { _, value in if value == .background { invalidate() } }
        }
        .onDisappear { invalidate() }
    }
    private func invalidate() { task?.cancel(); timeout?.cancel(); suggestion = nil; busy = false }
    private func suggest() {
        invalidate(); busy = true; problem = nil
        let input = description; let evidence = label; let original = draft
        timeout = Task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard busy, store.isCurrentOwner else { return }
            task?.cancel(); busy = false; suggestion = nil
            problem = "On-device suggestions took too long. Try a shorter description or enter the details manually."
        }
        task = Task {
            defer { if !Task.isCancelled { timeout?.cancel() } }
            do {
                let result = try await GarmentAssistance.suggest(description: input, label: evidence)
                guard store.isCurrentOwner, !Task.isCancelled, input == description, evidence == label, draft == original else { return }
                baseline = original; suggestion = result; busy = false
            } catch { if !Task.isCancelled { problem = "Could not suggest details. \(error.localizedDescription) Manual entry is still available."; busy = false } }
        }
    }
}
