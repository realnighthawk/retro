import SwiftUI
import PhotosUI

// Reads a purchase from a receipt or price label into the garment form the owner already has open.
// Nothing here saves: the ordinary garment save (with its frozen request and review) still owns that.
struct WardrobeReceiptView: View {
    let store: WardrobeStore
    @Binding var draft: WardrobeGarmentDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var typed = ""
    @State private var text = ""
    @State private var scan: PhotosPickerItem?
    @State private var proposal: WardrobeReceiptDraft?
    @State private var baseline: WardrobeGarmentDraft?
    @State private var busy = false
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var useDate = true
    @State private var useAmount = true
    @State private var useCurrency = true
    @State private var connected = false
    @State private var route: WardrobeLanguageRoute?
    private let byteLimit = 2000
    // Off by default: only the recognized (and editable) text is delegated, never the receipt photo.
    private var agentExecutor: WardrobeLanguageExecutor? {
        guard connected else { return nil }
        return WardrobeAgentLanguageExecutor(enabled: { true }, delegate: { query in try await store.assistant.delegate(query, connected: true) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("On this device") {
                    Text("Scan a receipt or price label, or type the total. Reading sends nothing anywhere and never saves a garment.").font(.footnote)
                    PhotosPicker(selection: $scan, matching: .images) { Label("Scan a receipt or label", systemImage: "doc.text.viewfinder") }.disabled(busy)
                    if !text.isEmpty { TextField("Recognized text — check for errors", text: $text, axis: .vertical).lineLimit(3...8) }
                    TextField("Or type what it says, for example Total 49.99 EUR", text: $typed, axis: .vertical).lineLimit(2...4)
                    if let reason = GarmentAssistance.unavailableReason {
                        Text(reason).font(.footnote)
                        Toggle("Read it with the connected agent instead", isOn: $connected)
                        Text("The recognized receipt text above is sent to your connected agent; the receipt photo never is. Its answer is checked against that text here, and a total without a stated currency still cannot be applied.").font(.footnote)
                    }
                    if let route { Text(route.title).font(.footnote).foregroundStyle(Tok.faint) }
                    Button("Read the purchase", action: read).disabled(busy || (text + typed).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (GarmentAssistance.unavailableReason != nil && !connected))
                    if busy { ProgressView("Reading on this device"); Button("Cancel") { invalidate() } }
                }
                if let problem { Section { Text(problem).foregroundStyle(Tok.stamp) } }
                if let proposal {
                    Section("Review before applying") {
                        Text(proposal.summary)
                        if proposal.date != nil { Toggle("Date", isOn: $useDate) }
                        if proposal.amount != nil { Toggle("Total", isOn: $useAmount) }
                        if proposal.currency != nil { Toggle("Currency", isOn: $useCurrency) }
                        if !proposal.dropped.isEmpty { Text("Not proposed, because the text does not show it clearly: " + proposal.dropped.joined(separator: ", ")).font(.footnote) }
                        Text("The recognized text is kept as this purchase's evidence. Applying fills the form only; use Save on the garment to keep it.").font(.footnote)
                        Button("Apply to purchase details", action: apply).disabled(busy || proposal.isEmpty)
                    }
                }
            }
            .navigationTitle("Purchase from a receipt").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: text) { _, _ in invalidate() }
            .onChange(of: typed) { _, _ in invalidate() }
            .onChange(of: scan) { _, item in
                guard let item else { return }
                invalidate(); busy = true; problem = nil
                task = Task {
                    do {
                        guard let bytes = try await item.loadTransferable(type: Data.self) else { throw WardrobeWriteError("This receipt photo could not be opened.") }
                        let normalized = try await Task.detached { try PhotoPreparation.normalize(bytes) }.value
                        let recognized = try await PhotoPreparation.labelText(normalized)
                        guard store.isCurrentOwner, !Task.isCancelled else { return }
                        text = String(recognized.prefix(6000))
                        if recognized.isEmpty { problem = "No readable text was found. Type the total instead." }
                        busy = false
                    } catch { if !Task.isCancelled { problem = error.localizedDescription; busy = false } }
                }
            }
            .onChange(of: phase) { _, value in if value == .background { invalidate() } }
        }
        .onDisappear { invalidate() }
    }
    private func invalidate() { task?.cancel(); timeout?.cancel(); proposal = nil; busy = false; route = nil }
    private func read() {
        invalidate(); busy = true; problem = nil
        let evidence = (text + "\n" + typed).trimmingCharacters(in: .whitespacesAndNewlines)
        let original = draft
        // A connected reading uses the delegation's own 90-second budget; on-device stays at 20.
        timeout = Task {
            do { try await Task.sleep(for: .seconds(connected ? 90 : 20)) } catch { return }
            guard busy, store.isCurrentOwner else { return }
            task?.cancel(); busy = false; proposal = nil
            problem = "Reading took too long. Enter the purchase details yourself."
        }
        task = Task {
            defer { if !Task.isCancelled { timeout?.cancel() } }
            do {
                let result = try await WardrobeReceiptAssistance.read(evidence, agent: agentExecutor)
                guard store.isCurrentOwner, !Task.isCancelled, evidence == (text + "\n" + typed).trimmingCharacters(in: .whitespacesAndNewlines), draft == original else { return }
                baseline = original; proposal = result.draft; route = result.route; busy = false
            } catch { if !Task.isCancelled { problem = "Could not read the receipt. \(error.localizedDescription) Enter the details yourself."; busy = false } }
        }
    }
    private func apply() {
        guard let proposal, store.isCurrentOwner, baseline == draft else {
            problem = "The garment form changed. Read the receipt again."; return
        }
        if proposal.amount != nil && proposal.currency == nil {
            problem = "The text does not state a currency. Choose one in the form so the amount is unambiguous."; return
        }
        if useAmount, let amount = proposal.amount { draft.purchaseDraft.amount = amount }
        if useCurrency, let currency = proposal.currency { draft.purchaseDraft.currency = currency }
        if useDate, let date = proposal.date { draft.purchaseDraft.date = date }
        // The reviewed text is the evidence the saved record keeps, bounded like a care label's.
        draft.purchaseDraft.evidence = Self.bounded(text.isEmpty ? typed : text, bytes: byteLimit)
        draft.purchaseDraft.source = "receipt"
        dismiss()
    }
    private static func bounded(_ value: String, bytes limit: Int) -> String {
        var result = ""
        for character in value where result.utf8.count + String(character).utf8.count <= limit { result.append(character) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
