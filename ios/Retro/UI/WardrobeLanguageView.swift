import SwiftUI

struct WardrobeLanguageContext: Identifiable {
    let id = UUID()
    var suggestion: WardrobeSuggestQuery?
    var inventory: WardrobeInventoryQuery?
    var required: [WardrobeSelection] = []
    var excluded: [WardrobeSelection] = []
    var mode: WardrobeLanguageMode { suggestion == nil ? .search : .outfit }
}
private struct WardrobeLanguageReference: Identifiable {
    let id = UUID()
    let hint: String
    let excluded: Bool
}
struct WardrobeLanguageView: View {
    let store: WardrobeStore
    let context: WardrobeLanguageContext
    let onApply: (WardrobeLanguageDraft, [WardrobeSelection], [WardrobeSelection], [String]) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var text = ""
    @State private var parsed: WardrobeLanguageDraft?
    @State private var references: [WardrobeLanguageReference] = []
    @State private var resolved: [UUID: WardrobeSelection] = [:]
    @State private var omitted: Set<UUID> = []
    @State private var choosing: WardrobeLanguageReference?
    @State private var required: [WardrobeSelection]
    @State private var excluded: [WardrobeSelection]
    @State private var occasion: String
    @State private var warmth: String
    @State private var nameQuery = ""
    @State private var category = ""
    @State private var availability = ""
    @State private var archived = false
    @State private var acceptedLimitations = false
    @State private var busy = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    init(store: WardrobeStore, context: WardrobeLanguageContext, onApply: @escaping (WardrobeLanguageDraft, [WardrobeSelection], [WardrobeSelection], [String]) throws -> Void) {
        self.store = store; self.context = context; self.onApply = onApply
        _required = State(initialValue: context.required); _excluded = State(initialValue: context.excluded)
        _occasion = State(initialValue: context.suggestion?.occasion ?? ""); _warmth = State(initialValue: context.suggestion?.warmth ?? "")
    }
    private var unhandled: [String] { (parsed?.unhandled ?? []) + references.filter { omitted.contains($0.id) }.map { "Ignored garment description: " + $0.hint } }
    private var allResolved: Bool { references.allSatisfy { resolved[$0.id] != nil || omitted.contains($0.id) } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Describe it") {
                    TextField(context.mode == .outfit ? "Outfit request" : "Wardrobe search request", text: $text, axis: .vertical).lineLimit(3...6)
                    WardrobeVoiceInput(store: store, text: $text, byteLimit: 2000)
                    Text("Interpretation runs on this device. Review the supported fields and choose real garments before applying them.").font(.footnote)
                    if let reason = GarmentAssistance.unavailableReason { Text(reason).font(.footnote) }
                    Button("Interpret request", action: interpret).frame(minHeight: 44).disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || GarmentAssistance.unavailableReason != nil)
                    if busy { ProgressView("Interpreting on this device"); Button("Cancel interpretation") { invalidate() }.frame(minHeight: 44) }
                    if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                }
                if parsed != nil {
                    if context.mode == .outfit { outfitFields } else { searchFields }
                    if !unhandled.isEmpty {
                        Section("Conditions not applied") {
                            ForEach(Array(unhandled.enumerated()), id: \.offset) { _, value in Text(value) }
                            Toggle("Use only the supported constraints above", isOn: $acceptedLimitations)
                        }
                    }
                    Section {
                        Button(context.mode == .outfit ? "Apply outfit constraints" : "Apply search filters", action: apply).frame(minHeight: 44)
                            .disabled(!allResolved || (!unhandled.isEmpty && !acceptedLimitations))
                        Text("You can edit the applied controls. Applying never saves an outfit or garment.").font(.footnote)
                    }
                }
            }.navigationTitle(context.mode == .outfit ? "Describe an outfit" : "Describe a search").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(item: $choosing) { reference in
                    WardrobeGarmentPicker(store: store, items: Binding(get: { resolved[reference.id].map { [$0] } ?? [] }, set: { resolved[reference.id] = $0.first; omitted.remove(reference.id) }), historical: false, maximum: 1, onlyReady: !reference.excluded)
                }
        }
        .onChange(of: text) { _, _ in invalidate() }
        .onChange(of: phase) { _, value in if value == .background { invalidate() } }
        .onDisappear { invalidate() }
    }
    private var outfitFields: some View {
        Group {
            Section("Review constraints") {
                Text("For \(context.suggestion?.day ?? ""). Dates are chosen in Today; weather is not inferred.").font(.footnote)
                TextField("Occasion", text: $occasion)
                Picker("Warmth", selection: $warmth) { Text("Any warmth").tag(""); ForEach(["light", "mid", "warm"], id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
                ForEach(required) { piece in Button("Remove existing include: " + piece.name) { required.removeAll { $0.id == piece.id } }.frame(minHeight: 44) }
                ForEach(excluded) { piece in Button("Remove existing exclusion: " + piece.name) { excluded.removeAll { $0.id == piece.id } }.frame(minHeight: 44) }
            }
            ForEach(references) { reference in
                Section((reference.excluded ? "Exclude: " : "Include: ") + reference.hint) {
                    Text(omitted.contains(reference.id) ? "Ignored explicitly" : resolved[reference.id]?.name ?? "Choose the real garment this description means")
                    Button("Choose garment") { choosing = reference }.frame(minHeight: 44)
                    if omitted.contains(reference.id) { Button("Resolve this description") { omitted.remove(reference.id) }.frame(minHeight: 44) }
                    else { Button("Ignore this description") { omitted.insert(reference.id); resolved[reference.id] = nil; acceptedLimitations = false }.frame(minHeight: 44) }
                }
            }
        }
    }
    private var searchFields: some View {
        Section("Review search filters") {
            TextField("Name contains", text: $nameQuery)
            Picker("Category", selection: $category) { Text("All categories").tag(""); ForEach(WardrobeVocabulary.categories, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
            Picker("Availability", selection: $availability) { Text("Any availability").tag(""); ForEach(WardrobeVocabulary.availability, id: \.self) { Text(WardrobeVocabulary.title($0)).tag($0) } }
            Toggle("Include archived", isOn: $archived)
            Text("Search checks names and these filters. It does not search colour, material, warmth, subtype, similarity or wear dates.").font(.footnote)
        }
    }
    private func invalidate() {
        task?.cancel(); timeout?.cancel(); parsed = nil; references = []; resolved = [:]; omitted = []
        required = context.required; excluded = context.excluded; acceptedLimitations = false; busy = false
    }
    private func interpret() {
        invalidate(); busy = true; problem = nil
        let input = text
        timeout = Task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard busy, store.isCurrentOwner else { return }
            task?.cancel(); busy = false; parsed = nil
            problem = "Interpretation took too long. Try a shorter request or use the manual controls."
        }
        task = Task {
            defer { if !Task.isCancelled { timeout?.cancel() } }
            do {
                let value = try await WardrobeLanguageAssistance.interpret(input, mode: context.mode)
                guard store.isCurrentOwner, !Task.isCancelled, input == text else { return }
                parsed = value; occasion = value.occasion ?? context.suggestion?.occasion ?? ""; warmth = value.warmth ?? context.suggestion?.warmth ?? ""
                nameQuery = value.nameQuery ?? ""; category = value.category ?? ""; availability = value.availability ?? ""; archived = value.includeArchived ?? false
                references = value.requiredGarments.map { WardrobeLanguageReference(hint: $0, excluded: false) } + value.excludedGarments.map { WardrobeLanguageReference(hint: $0, excluded: true) }
                busy = false
            } catch { if store.isCurrentOwner, !Task.isCancelled { problem = error.localizedDescription; busy = false } }
        }
    }
    private func apply() {
        guard store.isCurrentOwner, var value = parsed, allResolved, unhandled.isEmpty || acceptedLimitations else { return }
        do {
            let includes = required + references.filter { !$0.excluded && !omitted.contains($0.id) }.compactMap { resolved[$0.id] }
            let excludes = excluded + references.filter { $0.excluded && !omitted.contains($0.id) }.compactMap { resolved[$0.id] }
            if context.mode == .outfit { value.occasion = occasion; value.warmth = warmth; _ = try value.outfitQuery(day: context.suggestion?.day ?? "", required: includes, excluded: excludes) }
            else { value.nameQuery = nameQuery; value.category = category.isEmpty ? nil : category; value.availability = availability.isEmpty ? nil : availability; value.includeArchived = archived; _ = try value.searchQuery() }
            try onApply(value, includes, excludes, unhandled)
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}
