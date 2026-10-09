import SwiftUI

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct WardrobeSettingsAssistance: View {
    let store: WardrobeStore
    let record: WardrobeSettingsRecord
    @Binding var values: [String: Any]
    @State private var request = ""
    @State private var proposal: WardrobeSettingsProposal?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var requestID = UUID()
    @Environment(\.scenePhase) private var phase
    @State private var revision = 0
    @State private var original: Data?
    @State private var problem: String?
    private func signature(_ values: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) }
    var body: some View {
        Section("On-device assistance") {
            Text("Describe the settings you want, or enter label text above. Review every proposed change before applying it. Care suggestions always need confirmation.").font(.footnote)
            if let reason = GarmentAssistance.unavailableReason { Text(reason).font(.footnote) }
            TextField("Describe a change", text: $request, axis: .vertical).disabled(task != nil)
            if task != nil {
                ProgressView("Reading and drafting on device")
                Button("Cancel assistance", action: cancel)
            } else {
                Button("Draft changes on device", action: propose).disabled(GarmentAssistance.unavailableReason != nil || request.isEmpty)
            }
            if let problem { Text(problem).foregroundStyle(Tok.stamp) }
            if let proposal {
                ForEach(proposal.patch.keys.sorted(), id: \.self) { key in Text("\(WardrobeSettingFields.label(key)): \(String(describing: proposal.patch[key]!))") }
                ForEach(Array(proposal.unhandled.enumerated()), id: \.offset) { _, text in Text(text).font(.footnote) }
                Button("Apply reviewed changes") {
                    guard store.isCurrentOwner, store.changes == revision, signature(values) == original else { problem = "Settings changed. Draft again before applying."; self.proposal = nil; return }
                    for (key, value) in proposal.patch { values[key] = value }
                    if case .care = record { values["confirmed"] = false }
                    self.proposal = nil
                }.disabled(task != nil || proposal.patch.isEmpty)
            }
        }.onDisappear { cancel() }
        .onChange(of: request) { _, _ in cancel() }
        .onChange(of: signature(values)) { _, _ in cancel() }
        .onChange(of: phase) { _, value in if value == .background { cancel() } }
    }
    private func cancel() { requestID = UUID(); task?.cancel(); timeout?.cancel(); task = nil; proposal = nil }
    private func propose() {
        cancel(); problem = nil; original = signature(values); revision = store.changes
        let text = request, frozen = values
        let id = requestID
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard requestID == id, store.isCurrentOwner else { return }
            cancel(); problem = "Assistance timed out. Use manual editing or try again."
        }
        task = Task { @MainActor in
            defer { if requestID == id { task = nil; timeout?.cancel() } }
            do {
                let value = try await WardrobeSettingsIntelligence.propose(text, record: record, values: frozen, store: store)
                try Task.checkCancellation()
                guard requestID == id, store.isCurrentOwner else { return }
                proposal = value
            } catch { if !Task.isCancelled, store.isCurrentOwner, requestID == id { problem = error.localizedDescription; proposal = nil } }
        }
    }
}
#endif
