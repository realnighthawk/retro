import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct WardrobeRemotePhoto: View {
    let store: WardrobeStore
    let id: String
    var variant = "thumbnail"
    var label = "Garment photo"
    @State private var image: UIImage?
    @State private var problem: String?
    @State private var retry = 0
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                VStack {
                    Image(systemName: "photo").font(.largeTitle)
                    if problem != nil { Text("Photo unavailable").font(.caption); Button("Retry photo") { retry += 1 }.frame(minWidth: 44, minHeight: 44) }
                }.foregroundStyle(Tok.faint).frame(maxWidth: .infinity, minHeight: 72)
            }
        }
        .accessibilityLabel(label)
        .task(id: id + variant + String(retry)) {
            image = nil; problem = nil
            let result = await store.photos.image(id, variant: variant, reload: retry > 0)
            guard store.isCurrentOwner, !Task.isCancelled else { return }
            if case .ok(let data) = result { image = PhotoPreparation.display(data); if image == nil { problem = "Unreadable photo" } }
            else { problem = result.problem }
        }
    }
}

struct WardrobePhotosView: View {
    let store: WardrobeStore
    let garment: WardrobeGarment
    private let draftID: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var loaded: Bool
    @State private var retained: [String]
    @State private var selected: [PhotosPickerItem] = []
    @State private var prepared: [WardrobePreparedPhoto] = []
    @State private var camera = false
    @State private var working = false
    @State private var problem: String?
    @State private var discarding = false
    @State private var submitted = false
    @State private var work: Task<Void, Never>?
    init(store: WardrobeStore, garment: WardrobeGarment) {
        let saved = store.photos.drafts.first { $0.garment.id == garment.id }
        self.store = store; self.garment = saved?.garment ?? garment
        draftID = saved?.id ?? UUID().uuidString.lowercased()
        _retained = State(initialValue: saved?.retained ?? garment.mediaIDs ?? [])
        _loaded = State(initialValue: saved == nil)
    }
    private var dirty: Bool { !prepared.isEmpty || retained != (garment.mediaIDs ?? []) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Unsaved photo edits stay on this phone and can be resumed from Pending saves. Original and chosen images are kept; cutout previews can be regenerated.").font(.footnote)
                    if !loaded { Button("Retry loading photo draft") { Task { await restore() } }.disabled(working) }
                }
                savedPhotoSection
                if !prepared.isEmpty { newPhotoSection }
                if !store.photos.contains(garment.id) {
                    Section("Add photos") {
                        PhotosPicker(selection: $selected, maxSelectionCount: max(1, 10 - retained.count - prepared.count), matching: .images) { Label("Choose photos", systemImage: "photo.on.rectangle") }
                            .disabled(!loaded || working || retained.count + prepared.count >= 10 || store.writes.contains(garment.id))
                        Button("Take photo") { openCamera() }.frame(minHeight: 44).disabled(!loaded || working || retained.count + prepared.count >= 10 || store.writes.contains(garment.id))
                        Text("Exports strip source metadata and normalize orientation. Only the chosen original or cutout is uploaded.").font(.footnote)
                    }
                }
                if working { ProgressView("Preparing photo on this device") }
                if let problem = store.photos.problem ?? problem { Text(problem).foregroundStyle(Tok.stamp) }
                WardrobePhotoJobs(store: store, garmentID: garment.id)
            }
            .navigationTitle("Garment photos").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty || !loaded { discarding = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save photos", action: save).disabled(!loaded || !dirty || working || submitted || store.photos.contains(garment.id) || store.writes.contains(garment.id)) }
                ToolbarItem(placement: .bottomBar) { EditButton().disabled(working || !loaded) }
            }
            .sheet(isPresented: $camera) { WardrobeCamera { bytes in camera = false; if let bytes { prepare([bytes]) } } }
            .onChange(of: selected) { _, items in
                guard !items.isEmpty else { return }
                working = true; problem = nil
                work?.cancel()
                work = Task {
                    do {
                        var additions: [WardrobePreparedPhoto] = []
                        for item in items {
                            guard let bytes = try await item.loadTransferable(type: Data.self) else { throw WardrobeWriteError("Selected photo could not be opened.") }
                            let image = try await Task.detached { try PhotoPreparation.normalize(bytes) }.value
                            try Task.checkCancellation()
                            additions.append(WardrobePreparedPhoto(original: image, chosen: image))
                        }
                        guard store.isCurrentOwner, !Task.isCancelled else { return }
                        guard retained.count + prepared.count + additions.count <= 10 else { throw WardrobeWriteError("A garment can have up to 10 photos.") }
                        prepared += additions
                        persist()
                    } catch { if !Task.isCancelled { problem = error.localizedDescription } }
                    if !Task.isCancelled { selected = []; working = false }
                }
            }
            .task { if !loaded { await restore() } }
            .onChange(of: retained) { _, _ in if loaded && !submitted { persist() } }
            .onChange(of: prepared) { _, _ in if loaded && !submitted { persist() } }
            .task(id: phase) {
                guard phase == .active else { return }
                for _ in 0..<15 {
                    await store.sync()
                    guard !Task.isCancelled, store.photos.contains(garment.id) else { return }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
        }
        .interactiveDismissDisabled((dirty || !loaded) && !submitted)
        .confirmationDialog("Keep or discard photo edits?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Keep draft") { if !loaded || persist() { dismiss() } }
            Button("Discard edits", role: .destructive) { do { try store.photos.discardDraft(draftID); dismiss() } catch { problem = error.localizedDescription } }
        }
        .onDisappear { work?.cancel() }
    }
    private var savedPhotoSection: some View {
        Section("Saved photos · first is primary") {
            ForEach(retained, id: \.self) { id in savedPhotoRow(id) }
                .onMove { if loaded && !working { retained.move(fromOffsets: $0, toOffset: $1) } }
                .disabled(working || !loaded)
            Text("Removing a reference keeps photos used by past outfits. It does not permanently delete stored objects.").font(.footnote)
        }
    }
    private func savedPhotoRow(_ id: String) -> some View {
        VStack(alignment: .leading) {
            WardrobeRemotePhoto(store: store, id: id, variant: "display").frame(maxHeight: 220)
            HStack {
                Button("Make primary") { makePrimary(id) }.disabled(retained.first == id)
                Button("Remove", role: .destructive) { retained.removeAll { $0 == id } }
            }.frame(minHeight: 44)
        }
    }
    private var newPhotoSection: some View {
        Section("Review new photos") {
            ForEach(prepared) { photo in newPhotoRow(photo) }
                .onMove { if loaded && !working { prepared.move(fromOffsets: $0, toOffset: $1) } }
        }
    }
    private func newPhotoRow(_ photo: WardrobePreparedPhoto) -> some View {
        VStack(alignment: .leading) {
            if let image = PhotoPreparation.display(photo.chosen) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).accessibilityLabel("New garment photo") }
            HStack {
                Button("Preview cutouts") { cutouts(photo.id) }.disabled(working)
                Button("Remove", role: .destructive) { prepared.removeAll { $0.id == photo.id } }.disabled(working)
            }.frame(minHeight: 44)
            if photo.chosen != photo.original { Button("Use original") { choose(photo.id, bytes: photo.original) }.frame(minHeight: 44).disabled(working) }
            if !photo.cutouts.isEmpty {
                Text("Choose a foreground subject. These are masks, not garment recognition. Up to six subjects are previewed.").font(.footnote)
                ForEach(photo.cutouts.indices, id: \.self) { index in
                    Button { choose(photo.id, bytes: photo.cutouts[index]) } label: {
                        if let image = PhotoPreparation.display(photo.cutouts[index]) { Image(uiImage: image).resizable().scaledToFit().frame(height: 100) }
                    }.accessibilityLabel("Use cutout subject \(index + 1)").disabled(working)
                }
            }
        }
    }
    @discardableResult private func persist() -> Bool {
        do {
            if dirty { try store.photos.saveDraft(id: draftID, garment: garment, retained: retained, photos: prepared) }
            else { try store.photos.discardDraft(draftID) }
            return true
        } catch { problem = error.localizedDescription; return false }
    }
    private func restore() async {
        working = true; problem = nil
        do {
            let photos = try await store.photos.loadDraft(draftID)
            guard store.isCurrentOwner, !Task.isCancelled else { return }
            prepared = photos; loaded = true
        } catch { if !Task.isCancelled, store.isCurrentOwner { problem = error.localizedDescription } }
        if !Task.isCancelled { working = false }
    }
    private func prepare(_ images: [Data]) {
        working = true; problem = nil
        work = Task {
            do {
                let bytes = try await Task.detached { try images.map { try PhotoPreparation.normalize($0) } }.value
                guard store.isCurrentOwner, !Task.isCancelled else { return }
                guard retained.count + prepared.count + bytes.count <= 10 else { throw WardrobeWriteError("A garment can have up to 10 photos.") }
                prepared += bytes.map { WardrobePreparedPhoto(original: $0, chosen: $0) }
                persist()
            } catch { if !Task.isCancelled { problem = error.localizedDescription } }
            if !Task.isCancelled { working = false }
        }
    }
    private func cutouts(_ id: UUID) {
        guard let photo = prepared.first(where: { $0.id == id }) else { return }
        working = true; problem = nil
        work = Task {
            do {
                let images = try await PhotoPreparation.cutouts(photo.original)
                guard store.isCurrentOwner, !Task.isCancelled, let index = prepared.firstIndex(where: { $0.id == id }) else { return }
                prepared[index].cutouts = images
            } catch { if !Task.isCancelled { problem = error.localizedDescription } }
            if !Task.isCancelled { working = false }
        }
    }
    private func makePrimary(_ id: String) { retained.removeAll { $0 == id }; retained.insert(id, at: 0) }
    private func choose(_ id: UUID, bytes: Data) { if let index = prepared.firstIndex(where: { $0.id == id }) { prepared[index].chosen = bytes } }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { problem = "Camera is not available. Choose a photo instead."; return }
        work = Task {
            let allowed: Bool
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
            else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            guard store.isCurrentOwner, !Task.isCancelled else { return }
            if allowed { camera = true } else { problem = "Camera access is off. Enable it in Settings or choose a photo." }
        }
    }
    private func save() {
        guard !submitted else { return }
        do {
            guard loaded, persist() else { return }
            try store.photos.acceptDraft(draftID)
            Task { await store.sync(force: true) }
            submitted = true; dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct WardrobePhotoJobs: View {
    let store: WardrobeStore
    var garmentID: String?
    @State private var problem: String?
    @State private var discarding: String?
    @State private var reviewing: WardrobePhotoBatch?
    var body: some View {
        ForEach(store.photos.batches.filter { garmentID == nil || $0.garmentID == garmentID }) { batch in
            Section("Photos · \(batch.title)") {
                if let issue = batch.problem { Text(issue).foregroundStyle(Tok.stamp) }
                ForEach(batch.photos) { photo in
                    VStack(alignment: .leading) {
                        Text(photo.media.map { WardrobeVocabulary.title($0.state) } ?? "Queued")
                        if let issue = photo.problem { Text(issue).foregroundStyle(Tok.stamp) }
                        if photo.media?.state == "failed" {
                            Button("Retry processing") { do { try store.photos.retryProcessing(batchID: batch.id, photoID: photo.id); Task { await store.sync(force: true) } } catch { problem = error.localizedDescription } }
                                .disabled(store.photos.running)
                        }
                    }
                }
                if batch.attachment != nil { Text("Attachment pending acknowledgement").font(.footnote) }
                if (batch.blocked || batch.problem != nil), batch.photos.allSatisfy({ $0.media?.state == "ready" }) {
                    Button("Review attachment") { reviewing = batch }.disabled(store.photos.running)
                }
                Button("Refresh and retry photos") { Task { await store.sync(force: true) } }.disabled(store.photos.running)
                Button("Stop attaching this batch", role: .destructive) { discarding = batch.id }.disabled(store.photos.running)
                Text("Uploaded objects stay private in storage. Local source bytes remain until attachment acknowledgement.").font(.footnote)
            }
        }
        if let problem { Text(problem).foregroundStyle(Tok.stamp) }
        Color.clear.frame(height: 0).sheet(item: $reviewing) { PhotoAttachmentReview(store: store, batch: $0) }.confirmationDialog("Stop attaching this photo batch?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
            Button("Stop attaching", role: .destructive) {
                guard let id = discarding else { return }
                do { try store.photos.discard(id) } catch { problem = error.localizedDescription }
                discarding = nil
            }
        }
    }
}

struct WardrobeCamera: UIViewControllerRepresentable {
    let finished: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let finished: (Data?) -> Void
        init(_ finished: @escaping (Data?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            finished((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.92))
        }
    }
}

private struct PhotoAttachmentReview: View {
    let store: WardrobeStore
    let batch: WardrobePhotoBatch
    @Environment(\.dismiss) private var dismiss
    @State private var current: WardrobeGarment?
    @State private var retained: [String] = []
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            List {
                Text("Review the current garment's photos. The \(batch.photos.count) already uploaded photos will be appended; no image is uploaded again.").font(.footnote)
                if let current {
                    Text(current.name).font(.headline)
                    if current.archivedAt != nil { Text("Restore the garment before attaching photos.") }
                    ForEach(current.mediaIDs ?? [], id: \.self) { id in
                        if !batch.photos.contains(where: { $0.id == id }) {
                            WardrobeRemotePhoto(store: store, id: id).frame(height: 120)
                            Toggle("Keep this existing photo", isOn: Binding(get: { retained.contains(id) }, set: { keep in
                                retained.removeAll { $0 == id }; if keep { retained.append(id) }
                            }))
                        }
                    }
                    ForEach(batch.photos) { photo in
                        WardrobeRemotePhoto(store: store, id: photo.id, label: "Ready photo to append").frame(height: 120)
                    }
                    Button("Use reviewed photos") {
                        do { try store.photos.review(batch.id, current: current, retained: retained); Task { await store.sync(force: true) }; dismiss() }
                        catch { problem = error.localizedDescription }
                    }.disabled(current.archivedAt != nil || retained.count + batch.photos.count > 10 || store.photos.running)
                } else { ProgressView("Loading current garment") }
                if let problem { Text(problem).foregroundStyle(Tok.stamp) }
                Button("Refresh current garment") { Task { await load() } }
            }
            .navigationTitle("Review attachment")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        let result = await store.photos.currentGarment(batch.garmentID)
        guard store.isCurrentOwner, !Task.isCancelled else { return }
        if case .ok(let result) = result {
            current = result.garment; retained = (result.garment.mediaIDs ?? []).filter { id in !batch.photos.contains { $0.id == id } }; problem = nil
        } else { problem = result.problem }
    }
}
