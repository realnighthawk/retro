import CryptoKit
import Foundation
import Observation

struct WardrobeLocalPhoto: Codable, Identifiable {
    let id: String
    let checksum: String
    let size: Int
    let prepareKey: String
    var media: WardrobeMedia?
    var retryBody: Data?
    var problem: String?
}
struct WardrobePhotoBatch: Codable, Identifiable {
    let id: String
    let garmentID: String
    let title: String
    var baseline: [String]
    var retained: [String]
    var photos: [WardrobeLocalPhoto]
    var attachment: Data?
    var attachmentKey: String?
    var blocked = false
    var problem: String?
    var target: [String] { retained + photos.map(\.id) }
}

@MainActor @Observable final class WardrobePhotos {
    private(set) var batches: [WardrobePhotoBatch] = []
    private(set) var drafts: [WardrobePhotoDraft] = []
    private(set) var problem: String?
    private(set) var running = false
    var foreground = true
    private var canRun: Bool { engine.isCurrentOwner && foreground }
    private let folder: URL
    private let cache: URL
    private let engine: Engine
    private let writes: WardrobeWrites

    init(engine: Engine, writes: WardrobeWrites, directory: URL? = nil, cacheDirectory: URL? = nil) {
        self.engine = engine; self.writes = writes
        let scope = SHA256.hash(data: Data(engine.cacheScope.utf8)).map { String(format: "%02x", $0) }.joined()
        folder = directory ?? DiskCache(owner: engine.owner).durableURL("wardrobe-photos-\(scope)").deletingPathExtension()
        cache = cacheDirectory ?? DiskCache(owner: engine.owner).cacheDirectory("photos-\(scope)")
        do {
            let file = folder.appending(path: "jobs.json")
            if FileManager.default.fileExists(atPath: file.path) {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1024 * 1024 else { throw WardrobeWriteError("Photo manifest exceeds its limit.") }
                let data = try Data(contentsOf: file)
                let manifest: WardrobePhotoManifest
                if let legacy = try? JSONDecoder().decode([WardrobePhotoBatch].self, from: data) { manifest = WardrobePhotoManifest(version: 1, batches: legacy, drafts: []) }
                else { manifest = try JSONDecoder().decode(WardrobePhotoManifest.self, from: data) }
                let loaded = manifest.batches
                guard manifest.version == 1, manifest.drafts.count <= 20, Set(manifest.drafts.map(\.id)).count == manifest.drafts.count,
                      Set(manifest.drafts.map { $0.garment.id }).count == manifest.drafts.count,
                      manifest.drafts.allSatisfy({ Self.validDraft($0) }), Self.draftSize(manifest.drafts) <= 256 * 1024 * 1024 else { throw WardrobeWriteError("Invalid photo drafts.") }
                guard loaded.count <= 20, Set(loaded.map(\.id)).count == loaded.count, Set(loaded.map(\.garmentID)).isDisjoint(with: manifest.drafts.map { $0.garment.id }), loaded.allSatisfy({ batch in
                    guard UUID(uuidString: batch.id) != nil, UUID(uuidString: batch.garmentID) != nil,
                          batch.photos.allSatisfy({ WardrobeMediaPath.path(id: $0.id) != nil }),
                          (batch.attachment == nil) == (batch.attachmentKey == nil) else { return false }
                    if let body = batch.attachment, let key = batch.attachmentKey {
                        guard let input = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                              input["id"] as? String == batch.garmentID, input["idempotency_key"] as? String == key,
                              let patch = input["patch"] as? [String: Any], patch.count == 1,
                              patch["media_ids"] as? [String] == batch.target else { return false }
                    }
                    return true
                }) else { throw WardrobeWriteError("Invalid photo jobs.") }
                batches = loaded
                drafts = manifest.drafts
            }
            pruneUnqueuedSources()
        } catch { problem = "Pending photos could not be opened. Keep this app's data and reopen Retro. \(error.localizedDescription)" }
    }

    func contains(_ garmentID: String) -> Bool { batches.contains { $0.garmentID == garmentID } }

    func currentGarment(_ id: String) async -> Api<WardrobeGarmentResult> { await engine.call("garments_get", WardrobeID(id: id)) }

    func review(_ id: String, current: WardrobeGarment, retained: [String]) throws {
        guard engine.isCurrentOwner, problem == nil, !running, let batch = batches.first(where: { $0.id == id }),
              batch.garmentID == current.id, current.archivedAt == nil, batch.photos.allSatisfy({ $0.media?.state == "ready" }),
              retained.count + batch.photos.count <= 10, Set(retained).count == retained.count, retained.allSatisfy({ id in (current.mediaIDs ?? []).contains(id) && !batch.photos.contains(where: { $0.id == id }) }) else { throw WardrobeWriteError("Review an active garment and up to 10 ready photos first.") }
        if let pending = writes.items.first(where: { $0.entity == batch.garmentID }) {
            guard pending.id == batch.attachmentKey, pending.rejected else { throw WardrobeWriteError("Reconcile this garment's pending save before replacing an attachment.") }
            try writes.remove(pending)
        } else if batch.attachmentKey != nil, !batch.blocked { throw WardrobeWriteError("Retry to reconcile this attachment before replacing it.") }
        var updated = batch
        updated.baseline = current.mediaIDs ?? []; updated.retained = retained
        updated.attachment = nil; updated.attachmentKey = nil; updated.blocked = false; updated.problem = nil
        try commit(batches.map { $0.id == id ? updated : $0 })
    }

    func stage(garment: WardrobeGarment, retained: [String], images: [Data]) throws {
        guard engine.isCurrentOwner, garment.archivedAt == nil, problem == nil, !contains(garment.id), !drafts.contains(where: { $0.garment.id == garment.id }), !writes.contains(garment.id) else { throw WardrobeWriteError(problem ?? "Resolve this garment's pending saves/photos first.") }
        guard !images.isEmpty, retained.count + images.count <= 10, Set(retained).count == retained.count,
              retained.allSatisfy({ (garment.mediaIDs ?? []).contains($0) }), batches.count < 20 else { throw WardrobeWriteError("Choose up to 10 photos per garment and resolve older photo jobs first.") }
        try createFolder()
        var photos: [WardrobeLocalPhoto] = []
        for bytes in images {
            guard !bytes.isEmpty, bytes.count <= 12 * 1024 * 1024 else { throw WardrobeWriteError("Each photo must be at most 12 MiB.") }
            let id = UUID().uuidString.lowercased()
            let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try bytes.write(to: source(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            photos.append(WardrobeLocalPhoto(id: id, checksum: checksum, size: bytes.count, prepareKey: UUID().uuidString.lowercased()))
        }
        // Files precede durable intent. An interrupted staging write can leave an orphan, never a queued missing photo.
        try commit(batches + [WardrobePhotoBatch(id: UUID().uuidString.lowercased(), garmentID: garment.id, title: garment.name,
                                               baseline: garment.mediaIDs ?? [], retained: retained, photos: photos)])
    }

    func saveDraft(id: String, garment: WardrobeGarment, retained: [String], photos: [WardrobePreparedPhoto]) throws {
        guard engine.isCurrentOwner, problem == nil, !contains(garment.id) else { throw WardrobeWriteError(problem ?? "Resolve the accepted photo batch first.") }
        guard UUID(uuidString: id) != nil, garment.archivedAt == nil, retained.count + photos.count <= 10,
              Set(retained).count == retained.count, retained.allSatisfy({ (garment.mediaIDs ?? []).contains($0) }),
              Set(photos.map(\.id)).count == photos.count else { throw WardrobeWriteError("Review up to 10 different photos first.") }
        if let existing = drafts.first(where: { $0.garment.id == garment.id }), existing.id != id { throw WardrobeWriteError("Resume this garment's existing photo draft first.") }
        let newSize = photos.reduce(Int64(0)) { $0 + Int64($1.original.count) + ($1.original == $1.chosen ? 0 : Int64($1.chosen.count)) }
        guard drafts.filter({ $0.id != id }).count < 20, Self.draftSize(drafts.filter { $0.id != id }) + newSize <= 256 * 1024 * 1024,
              photos.allSatisfy({ !$0.original.isEmpty && !$0.chosen.isEmpty && $0.original.count <= 12 * 1024 * 1024 && $0.chosen.count <= 12 * 1024 * 1024 }) else { throw WardrobeWriteError("Photo draft storage is full or a photo is too large. Resolve older drafts first.") }
        let before = sourceIDs
        let previous = drafts.first { $0.id == id }
        guard previous == nil || (previous?.garment.id == garment.id && previous?.garment.mediaIDs == garment.mediaIDs) else { throw WardrobeWriteError("The photo draft baseline changed. Resume the stored draft first.") }
        try createFolder()
        func store(_ bytes: Data, old: WardrobePhotoBytes?) throws -> WardrobePhotoBytes {
            guard !bytes.isEmpty, bytes.count <= 12 * 1024 * 1024 else { throw WardrobeWriteError("Each normalized photo must be at most 12 MiB.") }
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if let old, old.checksum == hash, old.size == bytes.count { return old }
            let file = WardrobePhotoBytes(id: UUID().uuidString.lowercased(), checksum: hash, size: bytes.count)
            try bytes.write(to: source(file.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return file
        }
        let saved = try photos.map { photo in
            let old = previous?.photos.first { $0.id == photo.id }
            let original = try store(photo.original, old: old?.original)
            let chosen = try store(photo.chosen, old: photo.chosen == photo.original ? original : old?.chosen)
            return WardrobePhotoEdit(id: photo.id, original: original, chosen: chosen)
        }
        let value = WardrobePhotoDraft(id: id, garment: garment, retained: retained, photos: saved, updatedAt: Date())
        let next = drafts.filter { $0.id != id } + [value]
        guard Self.validDraft(value), next.count <= 20, Self.draftSize(next) <= 256 * 1024 * 1024 else { throw WardrobeWriteError("Photo drafts are full (20 drafts / 256 MiB). Resolve older drafts first.") }
        try commitState(batches, drafts: next)
        release(before)
    }
    func loadDraft(_ id: String) async throws -> [WardrobePreparedPhoto] {
        guard engine.isCurrentOwner, problem == nil, let value = drafts.first(where: { $0.id == id }) else { throw WardrobeWriteError(problem ?? "Photo draft is unavailable.") }
        let root = folder
        let edits = value.photos
        let loaded = try await Task.detached {
            try edits.map { photo in
                try Task.checkCancellation()
                let original = try Self.readBytes(photo.original, root: root)
                let chosen = photo.original.id == photo.chosen.id ? original : try Self.readBytes(photo.chosen, root: root)
                return WardrobePreparedPhoto(id: photo.id, original: original, chosen: chosen)
            }
        }.value
        try Task.checkCancellation()
        guard engine.isCurrentOwner, let current = drafts.first(where: { $0.id == id }), current.updatedAt == value.updatedAt, current.photos == value.photos, current.retained == value.retained else { throw WardrobeWriteError("Photo draft changed. Reopen it to continue.") }
        return loaded
    }
    private nonisolated static func readBytes(_ file: WardrobePhotoBytes, root: URL) throws -> Data {
        let path = root.appending(path: "\(file.id).jpg")
        guard WardrobeMediaPath.path(id: file.id) != nil, (1...12 * 1024 * 1024).contains(file.size),
              (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize) == file.size else { throw WardrobeWriteError("A draft photo is missing or damaged. Keep app data and restore the file, or discard this draft.") }
        let bytes = try Data(contentsOf: path)
        guard bytes.count == file.size, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == file.checksum else { throw WardrobeWriteError("A draft photo has changed. It will not be uploaded.") }
        return bytes
    }
    func acceptDraft(_ id: String) throws {
        guard engine.isCurrentOwner, problem == nil, !running, let value = drafts.first(where: { $0.id == id }),
              !contains(value.garment.id), !writes.contains(value.garment.id), batches.count < 20 else { throw WardrobeWriteError(problem ?? "Wait for this garment's pending work before saving photos.") }
        guard Self.validDraft(value) else { throw WardrobeWriteError("Invalid photo draft.") }
        for photo in value.photos { _ = try Self.readBytes(photo.chosen, root: folder) }
        let batch = WardrobePhotoBatch(id: value.id, garmentID: value.garment.id, title: value.garment.name, baseline: value.garment.mediaIDs ?? [], retained: value.retained,
            photos: value.photos.map { WardrobeLocalPhoto(id: $0.chosen.id, checksum: $0.chosen.checksum, size: $0.chosen.size, prepareKey: UUID().uuidString.lowercased()) })
        let before = sourceIDs
        try commitState(batches + [batch], drafts: drafts.filter { $0.id != id })
        release(before)
    }
    func discardDraft(_ id: String) throws {
        guard engine.isCurrentOwner, problem == nil else { throw WardrobeWriteError(problem ?? "Sign in before discarding a photo draft.") }
        guard drafts.contains(where: { $0.id == id }) else { return }
        let before = sourceIDs
        try commitState(batches, drafts: drafts.filter { $0.id != id })
        release(before)
    }

    func step() async {
        guard canRun, problem == nil, !running else { return }
        running = true
        defer { running = false }
        for batchID in batches.map(\.id) {
            guard canRun, !Task.isCancelled, let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
            var batch = batches[index]
            if let key = batch.attachmentKey {
                if writes.acknowledgedIDs.contains(key) { finish(batch); continue }
                if let pending = writes.items.first(where: { $0.id == key }), pending.rejected {
                    batch.blocked = true; batch.problem = pending.problem; update(batch); continue
                }
                if !batch.blocked, !writes.contains(batch.garmentID), let body = batch.attachment {
                    do { try writes.enqueuePrepared(id: key, operation: "garments_update", entity: batch.garmentID, title: "Photos · \(batch.title)", body: body) }
                    catch { batch.problem = error.localizedDescription; update(batch) }
                }
                continue
            }
            for photoIndex in batch.photos.indices {
                guard canRun, !Task.isCancelled else { return }
                var photo = batch.photos[photoIndex]
                photo.problem = nil
                var pause = false
                do {
                    guard photo.size > 0, photo.size <= 12 * 1024 * 1024,
                          (try source(photo.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.size else { throw WardrobeWriteError("Stored photo size has changed. It will not be uploaded.") }
                    let bytes = try Data(contentsOf: source(photo.id))
                    guard bytes.count == photo.size, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == photo.checksum else { throw WardrobeWriteError("Stored photo has changed. It will not be uploaded.") }
                    if photo.media == nil {
                        let fields: [String: Any] = ["id": photo.id, "idempotency_key": photo.prepareKey, "checksum": photo.checksum, "size_bytes": photo.size, "mime_type": "image/jpeg"]
                        let result: Api<WardrobeMediaResult> = await engine.callFrozen("media_prepare", body: try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys))
                        guard canRun, !Task.isCancelled else { return }
                        guard case .ok(let prepared) = result else { pause = result.pausesPhotoDelivery; throw WardrobeWriteError(result.problem ?? "Could not reserve photo.") }
                        try validate(prepared.media, photo: photo)
                        photo.media = prepared.media
                        batch.photos[photoIndex] = photo
                        guard update(batch) else { return }
                    }
                    let result: Api<WardrobeMediaResult> = await engine.call("media_get", WardrobeID(id: photo.id))
                    guard canRun, !Task.isCancelled else { return }
                    guard case .ok(let current) = result else { pause = result.pausesPhotoDelivery; throw WardrobeWriteError(result.problem ?? "Could not check photo.") }
                    try validate(current.media, photo: photo)
                    photo.media = current.media
                    if let retry = photo.retryBody {
                        let result: Api<WardrobeMediaResult> = await engine.callFrozen("media_retry", body: retry)
                        guard canRun, !Task.isCancelled else { return }
                        guard case .ok(let retried) = result else {
                            pause = result.pausesPhotoDelivery
                            if case .failed(let code, _) = result, ["conflict", "invalid_input", "not_found"].contains(code ?? "") { photo.retryBody = nil }
                            throw WardrobeWriteError(result.problem ?? "Processing retry was rejected. Refresh before requesting another retry.")
                        }
                        try validate(retried.media, photo: photo); photo.media = retried.media
                        photo.retryBody = nil
                    } else if current.media.state == "awaiting_upload" {
                        let result = await engine.uploadPhoto(photo.id, bytes: bytes)
                        guard canRun, !Task.isCancelled else { return }
                        guard case .ok(let uploaded) = result else { pause = result.pausesPhotoDelivery; throw WardrobeWriteError(result.problem ?? "Could not upload photo.") }
                        try validate(uploaded.media, photo: photo); photo.media = uploaded.media
                    } else if current.media.state == "failed" { photo.problem = current.media.error ?? "Processing failed. Retry processing or stop attaching this batch." }
                } catch { photo.problem = error.localizedDescription }
                batch.photos[photoIndex] = photo
                guard update(batch), !pause else { return }
            }
            guard batch.photos.allSatisfy({ $0.media?.state == "ready" && $0.retryBody == nil }), !writes.contains(batch.garmentID), !batch.blocked else { continue }
            let current: Api<WardrobeGarmentResult> = await engine.call("garments_get", WardrobeID(id: batch.garmentID))
            guard canRun, !Task.isCancelled else { return }
            if case .ok(let current) = current, current.garment.archivedAt == nil, (current.garment.mediaIDs ?? []) == batch.baseline {
                guard !writes.contains(batch.garmentID) else { continue }
                let key = UUID().uuidString.lowercased()
                let fields: [String: Any] = ["id": batch.garmentID, "idempotency_key": key, "expected_version": current.garment.version, "patch": ["media_ids": batch.target]]
                do {
                    batch.attachment = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
                    batch.attachmentKey = key; batch.problem = nil
                    guard update(batch) else { return }
                    try writes.enqueuePrepared(id: key, operation: "garments_update", entity: batch.garmentID, title: "Photos · \(batch.title)", body: batch.attachment!)
                } catch { batch.problem = error.localizedDescription; update(batch) }
            } else {
                if case .ok = current { batch.blocked = true }
                batch.problem = current.problem ?? "The garment's photos or archive state changed. Review it before attaching these photos."
                update(batch)
            }
        }
    }

    func reconcile() {
        guard engine.isCurrentOwner, problem == nil, !running else { return }
        for batch in batches where batch.attachmentKey.map({ writes.acknowledgedIDs.contains($0) }) == true { finish(batch) }
    }

    func retryProcessing(batchID: String, photoID: String) throws {
        guard engine.isCurrentOwner, !running, problem == nil, let i = batches.firstIndex(where: { $0.id == batchID }),
              let p = batches[i].photos.firstIndex(where: { $0.id == photoID }), let media = batches[i].photos[p].media, media.state == "failed" else { throw WardrobeWriteError("Refresh this photo before retrying processing.") }
        var next = batches
        if next[i].photos[p].retryBody == nil {
            var fields = WardrobeDraftValidation.edit(id: photoID, version: media.version)
            fields["idempotency_key"] = UUID().uuidString.lowercased()
            next[i].photos[p].retryBody = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
            try commit(next)
        }
    }

    func discard(_ id: String) throws {
        guard engine.isCurrentOwner, !running, let batch = batches.first(where: { $0.id == id }) else { throw WardrobeWriteError("Wait for photo delivery to stop first.") }
        if let key = batch.attachmentKey {
            if let pending = writes.items.first(where: { $0.id == key }) {
                guard pending.rejected else { throw WardrobeWriteError("Reconcile the attachment in Pending saves before discarding it.") }
                try writes.remove(pending)
            } else { guard batch.blocked else { throw WardrobeWriteError("Retry to reconcile this attachment before discarding it.") } }
        }
        let before = sourceIDs
        try commit(batches.filter { $0.id != id })
        release(before)
    }

    func image(_ id: String, variant: String, reload: Bool = false) async -> Api<Data> {
        guard engine.isCurrentOwner, WardrobeMediaPath.path(id: id, variant: variant) != nil else { return .unauthorized }
        let file = cache.appending(path: "\(id)-\(variant).jpg")
        if !reload, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 12 * 1024 * 1024, let data = try? Data(contentsOf: file) { return .ok(data) }
        let result = await engine.photo(id, variant: variant)
        guard engine.isCurrentOwner, !Task.isCancelled else { return .unauthorized }
        if case .ok(let data) = result {
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            trimCache()
        }
        return result
    }

    private func validate(_ media: WardrobeMedia, photo: WardrobeLocalPhoto) throws {
        guard media.id == photo.id, media.checksum == photo.checksum, media.sizeBytes == Int64(photo.size), media.mimeType == "image/jpeg",
              ["awaiting_upload", "processing", "ready", "failed"].contains(media.state) else { throw WardrobeWriteError("Photo reservation does not match the saved bytes.") }
    }
    private func source(_ id: String) -> URL { folder.appending(path: "\(id).jpg") }
    private func pruneUnqueuedSources() {
        let retained = sourceIDs
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // A valid manifest owns queued bytes; allow a day before removing interrupted staging leftovers.
        for file in files where file.pathExtension == "jpg" {
            let id = file.deletingPathExtension().lastPathComponent
            guard WardrobeMediaPath.path(id: id) != nil, !retained.contains(id.lowercased()),
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < Date().addingTimeInterval(-86400) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
    private func createFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    private func commit(_ next: [WardrobePhotoBatch]) throws {
        try commitState(next, drafts: drafts)
    }
    private func commitState(_ next: [WardrobePhotoBatch], drafts nextDrafts: [WardrobePhotoDraft]) throws {
        let data = try JSONEncoder().encode(WardrobePhotoManifest(version: 1, batches: next, drafts: nextDrafts))
        guard data.count <= 4 * 1024 * 1024 else { throw WardrobeWriteError("Photo manifest is full. Resolve older work first.") }
        try createFolder()
        try data.write(to: folder.appending(path: "jobs.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        batches = next; drafts = nextDrafts
    }
    private var sourceIDs: Set<String> { Set(batches.flatMap { $0.photos.map { $0.id.lowercased() } } + drafts.flatMap { $0.sources.map { $0.id.lowercased() } }) }
    private func release(_ before: Set<String>) { for id in before.subtracting(sourceIDs) { try? FileManager.default.removeItem(at: source(id)) } }
    private static func draftSize(_ values: [WardrobePhotoDraft]) -> Int64 {
        var files: [String: Int] = [:]
        for value in values { for file in value.sources { files[file.id] = file.size } }
        return files.values.reduce(Int64(0)) { $0 + Int64($1) }
    }
    private static func validDraft(_ value: WardrobePhotoDraft) -> Bool {
        UUID(uuidString: value.id) != nil && WardrobeMediaPath.path(id: value.garment.id) != nil && value.garment.archivedAt == nil &&
        value.retained.count + value.photos.count <= 10 && Set(value.retained).count == value.retained.count &&
        value.retained.allSatisfy({ (value.garment.mediaIDs ?? []).contains($0) }) && Set(value.photos.map(\.id)).count == value.photos.count && Set(value.photos.map { $0.chosen.id }).count == value.photos.count && Set(value.retained).isDisjoint(with: value.photos.map { $0.chosen.id }) &&
        value.sources.allSatisfy { WardrobeMediaPath.path(id: $0.id) != nil && (1...12 * 1024 * 1024).contains($0.size) && $0.checksum.count == 64 && $0.checksum.allSatisfy({ "0123456789abcdef".contains($0) }) }
    }

    @discardableResult private func update(_ batch: WardrobePhotoBatch) -> Bool {
        do { try commit(batches.map { $0.id == batch.id ? batch : $0 }); return true }
        catch { problem = "Pending photos could not be stored. Reopen Retro to retry. \(error.localizedDescription)"; return false }
    }
    private func finish(_ batch: WardrobePhotoBatch) {
        do {
            let before = sourceIDs
            try commit(batches.filter { $0.id != batch.id })
            release(before)
        } catch { problem = "The attachment is acknowledged, but local cleanup failed. Reopen Retro to reconcile. \(error.localizedDescription)" }
    }
    private func trimCache() {
        let files = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let sorted = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        for file in sorted where total > 64 * 1024 * 1024 { total -= (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0; try? FileManager.default.removeItem(at: file) }
    }
}
