import CryptoKit
import Foundation
import Observation

struct WardrobeSavedDraft: Codable, Identifiable {
    let id: String
    let entityID: String
    let garment: WardrobeGarment?
    let outfit: WardrobeOutfit?
    let confirming: Bool
    var garmentDraft: WardrobeGarmentDraft?
    var outfitDraft: WardrobeOutfitDraft?
    var dependency: WardrobePending? = nil
    var importPhoto: WardrobePhotoBytes? = nil
    var importMediaID: String? = nil
    var updatedAt = Date()
    func originalGarment() throws -> WardrobeGarmentDraft {
        if let dependency { return try WardrobeGarmentDraft(createFields: dependency.createFields()) }
        return WardrobeGarmentDraft(garment)
    }
    func originalOutfit() throws -> WardrobeOutfitDraft {
        if let dependency { return try WardrobeOutfitDraft(createFields: dependency.createFields()) }
        return WardrobeOutfitDraft(outfit, date: outfitDraft?.date ?? Date())
    }
    func validateDependency() throws {
        if let photo = importPhoto {
            guard garmentDraft != nil, outfitDraft == nil, !confirming,
                  WardrobeMediaPath.path(id: photo.id) != nil, photo.size > 0, photo.size <= 12 * 1024 * 1024,
                  photo.checksum.count == 64, photo.checksum.allSatisfy({ "0123456789abcdef".contains($0) }),
                  importMediaID == nil || WardrobeMediaPath.path(id: importMediaID!) != nil else { throw WardrobeWriteError("Invalid import photo.") }
        } else if importMediaID != nil { throw WardrobeWriteError("Missing import photo.") }
        guard let dependency else { return }
        guard dependency.entity == entityID, garment == nil, outfit == nil, !confirming,
              (garmentDraft != nil ? dependency.operation == "garments_create" : dependency.operation == "outfits_create") else { throw WardrobeWriteError("Invalid draft dependency.") }
        if garmentDraft != nil { _ = try originalGarment() } else {
            let original = try originalOutfit()
            guard outfitDraft?.state == original.state, outfitDraft?.source == original.source else { throw WardrobeWriteError("A followup draft must keep the original outfit state and source.") }
        }
    }
    var title: String { garmentDraft?.name.nonEmpty ?? outfitDraft?.label.nonEmpty ?? (garmentDraft != nil ? "Garment draft" : "Outfit draft") }
    func hasImportEdits() throws -> Bool {
        guard importPhoto != nil, dependency != nil || garment != nil, let garmentDraft else { return false }
        return !WardrobeDraftValidation.patch(try garmentDraft.fields(), original: try originalGarment().fields()).isEmpty
    }
}
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

@MainActor @Observable final class WardrobeSavedDrafts {
    private(set) var items: [WardrobeSavedDraft] = []
    private(set) var problem: String?
    private let file: URL
    private let stillOwner: () -> Bool
    private var photoFolder: URL { file.deletingPathExtension().appending(path: "import-photos") }
    var imports: [WardrobeSavedDraft] { items.filter { $0.importPhoto != nil } }
    convenience init(engine: Engine) {
        let scope = SHA256.hash(data: Data(engine.cacheScope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.init(file: DiskCache(owner: engine.owner).durableURL("wardrobe-drafts-\(scope)"), stillOwner: { engine.isCurrentOwner })
    }
    init(file: URL, stillOwner: @escaping () -> Bool) {
        self.file = file; self.stillOwner = stillOwner
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1024 * 1024 else { throw WardrobeWriteError("Draft storage exceeds its limit.") }
                let values = try JSONDecoder().decode([WardrobeSavedDraft].self, from: Data(contentsOf: file))
                guard values.count <= 100, Set(values.map(\.id)).count == values.count,
                      values.allSatisfy({ UUID(uuidString: $0.id) != nil && WardrobeMediaPath.path(id: $0.entityID) != nil && ($0.garmentDraft == nil) != ($0.outfitDraft == nil) && ($0.garment?.id ?? $0.outfit?.id ?? $0.entityID) == $0.entityID }) else { throw WardrobeWriteError("Invalid draft records.") }
                try values.forEach { try $0.validateDependency() }
                guard values.filter({ $0.importPhoto != nil }).count <= 20 else { throw WardrobeWriteError("Too many import photos.") }
                items = values
            }
            pruneImportPhotos()
        } catch { problem = "Drafts could not be opened. Keep app data and reopen Retro. \(error.localizedDescription)" }
    }
    func garment(_ id: String?) -> WardrobeSavedDraft? { items.last { $0.importPhoto == nil && $0.dependency == nil && $0.garmentDraft != nil && $0.garment?.id == id } }
    func addImport(_ data: Data) throws {
        guard stillOwner(), problem == nil, imports.count < 20, data.count > 0, data.count <= 12 * 1024 * 1024 else { throw WardrobeWriteError(problem ?? "Keep up to 20 reviewed import photos on this phone.") }
        var folder = photoFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
        let stored = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]).reduce(Int64(0)) { total, file in total + Int64((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        guard stored + Int64(data.count) <= 256 * 1024 * 1024 else { throw WardrobeWriteError("Import photo storage is full. Finish older items first.") }
        let photo = WardrobePhotoBytes(id: UUID().uuidString.lowercased(), checksum: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: data.count)
        let source = folder.appending(path: "\(photo.id).jpg")
        try data.write(to: source, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do {
            try put(WardrobeSavedDraft(id: UUID().uuidString.lowercased(), entityID: UUID().uuidString.lowercased(), garment: nil, outfit: nil, confirming: false, garmentDraft: WardrobeGarmentDraft(nil), outfitDraft: nil, importPhoto: photo))
        } catch { try? FileManager.default.removeItem(at: source); throw error }
    }
    func importBytes(_ id: String) async throws -> Data {
        guard stillOwner(), problem == nil, let photo = items.first(where: { $0.id == id })?.importPhoto else { throw WardrobeWriteError(problem ?? "Reopen this import while signed in.") }
        let folder = photoFolder
        let data = try await Task.detached {
            let file = folder.appending(path: "\(photo.id).jpg")
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == photo.size else { throw WardrobeWriteError("Import photo is missing or changed. Keep this draft to recover it.") }
            let bytes = try Data(contentsOf: file)
            guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == photo.checksum else { throw WardrobeWriteError("Import photo checksum changed.") }
            return bytes
        }.value
        guard stillOwner(), items.first(where: { $0.id == id })?.importPhoto == photo, !Task.isCancelled else { throw WardrobeWriteError("Import changed. Reopen it.") }
        return data
    }
    func outfit(_ id: String?, confirming: Bool) -> WardrobeSavedDraft? { items.last { $0.dependency == nil && $0.outfitDraft != nil && $0.outfit?.id == id && $0.confirming == confirming } }
    func follow(_ pending: WardrobePending, names: [String: String] = [:]) throws -> WardrobeSavedDraft {
        guard stillOwner(), problem == nil else { throw WardrobeWriteError(problem ?? "Sign in before editing a queued create.") }
        if let existing = items.last(where: { $0.dependency?.id == pending.id }) { return existing }
        let fields = try pending.createFields()
        let garment = pending.operation == "garments_create"
        var value = WardrobeSavedDraft(id: UUID().uuidString.lowercased(), entityID: pending.entity, garment: nil, outfit: nil, confirming: false,
                                      garmentDraft: garment ? try WardrobeGarmentDraft(createFields: fields) : nil,
                                      outfitDraft: garment ? nil : try WardrobeOutfitDraft(createFields: fields), dependency: pending)
        if var outfit = value.outfitDraft {
            outfit.items = outfit.items.map { var piece = $0; piece.name = names[piece.id] ?? piece.name; return piece }
            value.outfitDraft = outfit
        }
        try put(value)
        return value
    }
    func put(_ value: WardrobeSavedDraft) throws {
        guard stillOwner(), problem == nil else { throw WardrobeWriteError(problem ?? "Sign in before storing a draft.") }
        try value.validateDependency()
        guard WardrobeMediaPath.path(id: value.id) != nil, WardrobeMediaPath.path(id: value.entityID) != nil,
              (value.garmentDraft == nil) != (value.outfitDraft == nil), (value.garment?.id ?? value.outfit?.id ?? value.entityID) == value.entityID else { throw WardrobeWriteError("Invalid draft record.") }
        var value = value; value.updatedAt = Date()
        let next = items.filter { $0.id != value.id } + [value]
        guard next.count <= 100, next.filter({ $0.importPhoto != nil }).count <= 20 else { throw WardrobeWriteError("Resolve older drafts before adding more.") }
        try commit(next)
    }
    func remove(_ id: String) throws {
        guard stillOwner(), problem == nil else { throw WardrobeWriteError(problem ?? "Sign in before discarding a draft.") }
        guard items.contains(where: { $0.id == id }) else { return }
        try commit(items.filter { $0.id != id })
    }
    private func pruneImportPhotos() {
        let retained = Set(items.compactMap { $0.importPhoto?.id })
        for file in (try? FileManager.default.contentsOfDirectory(at: photoFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where file.pathExtension == "jpg" {
            let id = file.deletingPathExtension().lastPathComponent
            guard WardrobeMediaPath.path(id: id) != nil, !retained.contains(id),
                  let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < Date().addingTimeInterval(-86400) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
    private func commit(_ next: [WardrobeSavedDraft]) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= 4 * 1024 * 1024 else { throw WardrobeWriteError("Draft storage is full. Resolve older drafts first.") }
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let released = Set(items.compactMap { $0.importPhoto?.id }).subtracting(next.compactMap { $0.importPhoto?.id })
        items = next
        for id in released { try? FileManager.default.removeItem(at: photoFolder.appending(path: "\(id).jpg")) }
    }
}
