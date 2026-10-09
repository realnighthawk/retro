import SwiftUI
import PhotosUI

struct WardrobeCareLabelScan: View {
    let store: WardrobeStore
    @Binding var values: [String: Any]
    @Environment(\.scenePhase) private var phase
    @State private var photo: PhotosPickerItem?
    @State private var review: WardrobeCareLabelReview?
    @State private var text = ""
    @State private var problem: String?
    @State private var task: Task<Void, Never>?
    @State private var timeout: Task<Void, Never>?
    @State private var ticket = UUID()
    var body: some View {
        Section("Read care-label text") {
            PhotosPicker(selection: $photo, matching: .images) { Label("Scan a care-label photo", systemImage: "text.viewfinder") }.frame(minHeight: 44).disabled(task != nil)
            Text("Text recognition stays on this device and works without Apple Intelligence. Check every word and temperature. Laundry symbols, omitted warnings and missing units need manual review; the scan never interprets them.").font(.footnote)
            if task != nil { ProgressView("Reading label text on this device"); Button("Cancel scan", action: cancel).frame(minHeight: 44) }
            if let problem { Text(problem).foregroundStyle(Tok.stamp) }
            if let review {
                TextField("Recognized text — correct errors before using", text: $text, axis: .vertical).lineLimit(3...8)
                Button("Use reviewed label text") {
                    do { values = try review.applying(text, to: values, owner: store.isCurrentOwner); cancel() }
                    catch { problem = error.localizedDescription }
                }.frame(minHeight: 44)
                Button("Discard scan", action: cancel).frame(minHeight: 44)
                Text("This replaces Label instructions, marks the source Label and clears care confirmation. Other care settings stay unchanged; draft changes below or edit them manually, then confirm before saving. The photo is not uploaded.").font(.footnote)
            }
        }
        .onChange(of: photo) { _, item in if let item { scan(item) } }
        .onChange(of: phase) { _, value in if value == .background { cancel() } }
        .onChange(of: store.changes) { _, _ in cancel() }
        .onChange(of: try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)) { _, _ in cancel() }
        .onDisappear { cancel() }
    }
    private func cancel() { ticket = UUID(); task?.cancel(); timeout?.cancel(); task = nil; review = nil; text = ""; photo = nil }
    private func scan(_ item: PhotosPickerItem) {
        // Retain the selected item for this read only; label photo bytes are never journalled or uploaded.
        cancel(); problem = nil; let id = ticket; let original = values
        timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard ticket == id, store.isCurrentOwner else { return }
            cancel(); problem = "Label reading timed out. Try a closer photo or type the instructions manually."
        }
        task = Task { @MainActor in
            defer { if ticket == id { task = nil; timeout?.cancel() } }
            do {
                guard store.isCurrentOwner else { throw CancellationError() }
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw WardrobeWriteError("This label photo could not be opened.") }
                try Task.checkCancellation()
                let normalized = try await Task.detached { try PhotoPreparation.normalize(bytes) }.value
                try Task.checkCancellation()
                let recognized = try await PhotoPreparation.labelText(normalized)
                try Task.checkCancellation()
                guard ticket == id, store.isCurrentOwner else { return }
                let value = try WardrobeCareLabelReview(text: recognized, values: original)
                review = value; text = value.text
            } catch { if !Task.isCancelled, store.isCurrentOwner, ticket == id { problem = error.localizedDescription } }
        }
    }
}
