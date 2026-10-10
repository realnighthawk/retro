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
    @State private var connected = false
    @State private var route: WardrobeLanguageRoute?
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    // Off by default, like the interpreter's: only the reviewed text is delegated, never the label photo.
    private var agentExecutor: WardrobeLanguageExecutor? {
        guard connected else { return nil }
        return WardrobeAgentLanguageExecutor(enabled: { true }, delegate: { query in try await store.assistant.delegate(query, connected: true) })
    }
    @State private var useName = true
    @State private var useCategory = true
    @State private var useSubtype = true
    @State private var useBrand = true
    @State private var useMaterial = true
    @State private var usePattern = true
    @State private var useStyle = true
    @State private var useFit = true
    @State private var useColours = true
    @State private var useSeasons = true
    @State private var useNotes = false
    var body: some View {
        NavigationStack {
            Form {
                Section("On this device") {
                    Text("Describe the garment or scan its label. Suggestions use this text only; they do not inspect garment photos.").font(.footnote)
                    TextField("Garment description", text: $description, axis: .vertical).lineLimit(3...6)
                    WardrobeVoiceInput(store: store, text: $description, byteLimit: 6000)
                    PhotosPicker(selection: $scan, matching: .images) { Label("Scan a label", systemImage: "text.viewfinder") }.disabled(busy)
                    if !label.isEmpty { TextField("Recognized label text — check for errors", text: $label, axis: .vertical).lineLimit(3...8) }
                    Text("Label photos and discarded suggestions stay local. Brand and material need readable label evidence or your own input.").font(.footnote)
                    if let reason = GarmentAssistance.unavailableReason {
                        Text(reason).font(.footnote)
                        Toggle("Read my text with the connected agent instead", isOn: $connected)
                        Text("The description and the label text above are sent to your connected agent; the label photo never is. Its answer is checked against your own words here before anything is offered.").font(.footnote)
                    }
                    if let route { Text(route.title).font(.footnote).foregroundStyle(Tok.faint) }
                    Button("Suggest details", action: suggest).disabled(busy || (GarmentAssistance.unavailableReason != nil && !connected) || (description + label).isEmpty)
                    if busy { ProgressView("Working on this device"); Button("Cancel assistance") { invalidate() } }
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp) } }
                if let suggestion {
                    Section("Review before applying") {
                        if let name = suggestion.name { Toggle("Name: \(name)", isOn: $useName) }
                        if let category = suggestion.category { Toggle("Category: \(WardrobeVocabulary.title(category))", isOn: $useCategory) }
                        if let subtype = suggestion.subtype { Toggle("Subtype: \(subtype)", isOn: $useSubtype) }
                        if let brand = suggestion.brand { Toggle("Brand: \(brand)", isOn: $useBrand) }
                        if let material = suggestion.material { Toggle("Material: \(material)", isOn: $useMaterial) }
                        if let pattern = suggestion.pattern { Toggle("Pattern: \(pattern)", isOn: $usePattern) }
                        if let style = suggestion.style { Toggle("Style: \(style)", isOn: $useStyle) }
                        if let fit = suggestion.fit { Toggle("Fit: \(fit)", isOn: $useFit) }
                        if !suggestion.colours.isEmpty { Toggle("Colours: \(suggestion.colours.joined(separator: ", "))", isOn: $useColours) }
                        if !suggestion.seasons.isEmpty { Toggle("Seasons: \(suggestion.seasons.joined(separator: ", "))", isOn: $useSeasons) }
                        if let notes = suggestion.notes { Toggle("Replace notes with: \(notes)", isOn: $useNotes) }
                        if !suggestion.dropped.isEmpty { Text("Not proposed, because your text does not state it: " + suggestion.dropped.joined(separator: ", ")).font(.footnote) }
                        Text("Selected fields replace the form's current values; anything you do not select keeps your own entry. Applying a suggestion never saves a garment.").font(.footnote)
                        Button("Apply selected suggestions") {
                            guard store.isCurrentOwner, baseline == draft else { problem = "The garment form changed. Generate a fresh suggestion before applying it."; return }
                            if useName, let value = suggestion.name { draft.name = value }
                            if useCategory, let value = suggestion.category { draft.category = value }
                            if useSubtype, let value = suggestion.subtype { draft.subtype = value }
                            if useBrand, let value = suggestion.brand { draft.brand = value }
                            if useMaterial, let value = suggestion.material { draft.material = value }
                            if usePattern, let value = suggestion.pattern { draft.patternText = value }
                            if useStyle, let value = suggestion.style { draft.styleText = value }
                            if useFit, let value = suggestion.fit { draft.fitText = value }
                            if useColours, !suggestion.colours.isEmpty { draft.colours = suggestion.colours.joined(separator: ", ") }
                            if useSeasons, !suggestion.seasons.isEmpty { draft.seasons = suggestion.seasons.joined(separator: ", ") }
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
    private func invalidate() { task?.cancel(); timeout?.cancel(); suggestion = nil; busy = false; route = nil }
    private func suggest() {
        invalidate(); busy = true; problem = nil
        let input = description; let evidence = label; let original = draft
        // A connected reading uses the delegation's own 90-second budget; on-device stays at 20.
        timeout = Task {
            do { try await Task.sleep(for: .seconds(connected ? 90 : 20)) } catch { return }
            guard busy, store.isCurrentOwner else { return }
            task?.cancel(); busy = false; suggestion = nil
            problem = "On-device suggestions took too long. Try a shorter description or enter the details manually."
        }
        task = Task {
            defer { if !Task.isCancelled { timeout?.cancel() } }
            do {
                let result = try await GarmentAssistance.suggest(description: input, label: evidence, agent: agentExecutor)
                guard store.isCurrentOwner, !Task.isCancelled, input == description, evidence == label, draft == original else { return }
                baseline = original; suggestion = result.draft; route = result.route; busy = false
            } catch { if !Task.isCancelled { problem = "Could not suggest details. \(error.localizedDescription) Manual entry is still available."; busy = false } }
        }
    }
}
