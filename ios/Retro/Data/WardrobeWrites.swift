import CryptoKit
import Foundation
import Observation

struct WardrobePending: Codable, Identifiable {
    let id: String
    let entity: String
    let operation: String
    let title: String
    let body: Data
    let createdAt: Date
    var dispatched = false
    var rejected = false
    var problem: String?
    var context: String?
    var retryAfter: Date?

    func createFields() throws -> [String: Any] {
        guard ["garments_create", "outfits_create"].contains(operation), WardrobeMediaPath.path(id: entity) != nil,
              UUID(uuidString: id) != nil, let fields = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              fields["id"] as? String == entity, fields["idempotency_key"] as? String == id else { throw WardrobeWriteError("The original create request could not be restored.") }
        return fields
    }

    var requestedSummary: String {
        guard let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return title }
        let changes = (fields["patch"] as? [String: Any]) ?? fields
        return changes.keys.sorted().filter { !["id", "idempotency_key", "expected_version", "source"].contains($0) }.map { key in
            let value = changes[key]!
            if let items = value as? [[String: String]] {
                return context ?? "Pieces: \(items.count) · " + items.compactMap { $0["role"] }.joined(separator: ", ")
            }
            if let values = value as? [String] { return "\(WardrobeVocabulary.title(key)): \(values.joined(separator: ", "))" }
            if key == "favourite", let favourite = value as? Bool { return "Favourite: \(favourite ? "Yes" : "No")" }
            return "\(WardrobeVocabulary.title(key)): \(value)"
        }.joined(separator: "\n")
    }
}

// Accepted writes are durable records, never purgable read caches.
@MainActor @Observable final class WardrobeWrites {
    private(set) var items: [WardrobePending] = []
    private(set) var problem: String?
    private(set) var sending = false
    private(set) var acknowledgements = 0
    private(set) var acknowledgedIDs: Set<String> = []
    private let file: URL
    private let stillOwner: () -> Bool
    private let send: (String, Data) async -> Api<Bool>
    private let save: ([WardrobePending]) throws -> Void

    convenience init(engine: Engine) {
        let scope = SHA256.hash(data: Data(engine.cacheScope.utf8)).map { String(format: "%02x", $0) }.joined()
        self.init(file: DiskCache(owner: engine.owner).durableURL("wardrobe-writes-\(scope)"), stillOwner: { engine.isCurrentOwner }) { op, body in
            if op.hasPrefix("garments_") {
                let result: Api<WardrobeGarmentResult> = await engine.callFrozen(op, body: body)
                return result.map { _ in true }
            }
            let result: Api<WardrobeOutfitResult> = await engine.callFrozen(op, body: body)
            return result.map { _ in true }
        }
    }

    init(file: URL, stillOwner: @escaping () -> Bool, save: (([WardrobePending]) throws -> Void)? = nil,
         send: @escaping (String, Data) async -> Api<Bool>) {
        self.file = file
        self.stillOwner = stillOwner
        self.send = send
        self.save = save ?? { items in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var folder = file.deletingLastPathComponent()
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            try folder.setResourceValues(attributes)
            try JSONEncoder().encode(items).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                items = try JSONDecoder().decode([WardrobePending].self, from: Data(contentsOf: file))
            }
        } catch { problem = "Pending saves could not be opened. Keep this app's data and retry opening Retro. \(error.localizedDescription)" }
    }

    func contains(_ entity: String) -> Bool { items.contains { $0.entity == entity } }

    // Frozen requests stay immutable; dependent edits remain local drafts until reviewed against a fresh record.
    func enqueue(operation: String, entity: String, title: String, fields: [String: Any], context: String? = nil) throws {
        guard stillOwner(), problem == nil else { throw WardrobeWriteError(problem ?? "Sign in again before saving.") }
        guard !contains(entity) else { throw WardrobeWriteError("This record already has a pending save. Resolve it in Pending saves first.") }
        guard items.count < 100 else { throw WardrobeWriteError("Resolve pending saves before adding more.") }
        let id = UUID().uuidString.lowercased()
        var payload = fields
        payload["idempotency_key"] = id
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try enqueuePrepared(id: id, operation: operation, entity: entity, title: title, body: body, context: context)
    }

    func enqueuePrepared(id: String, operation: String, entity: String, title: String, body: Data, context: String? = nil) throws {
        guard stillOwner(), problem == nil else { throw WardrobeWriteError(problem ?? "Sign in again before saving.") }
        if let existing = items.first(where: { $0.id == id }) {
            guard existing.body == body, existing.operation == operation, existing.entity == entity else { throw WardrobeWriteError("The pending request identity has changed.") }
            return
        }
        guard !contains(entity), items.count < 100 else { throw WardrobeWriteError("Resolve this record's pending saves first.") }
        try commit(items + [WardrobePending(id: id, entity: entity, operation: operation, title: title, body: body, createdAt: Date(), context: context)])
    }

    func restoreCreate(_ original: WardrobePending) throws {
        _ = try original.createFields()
        guard stillOwner(), problem == nil, !sending else { throw WardrobeWriteError(problem ?? "Wait for pending saves before retrying the original create.") }
        if let stored = items.first(where: { $0.id == original.id }) {
            guard stored.body == original.body, stored.operation == original.operation, stored.entity == original.entity else { throw WardrobeWriteError("The original request identity has changed.") }
            return
        }
        guard !contains(original.entity), items.count < 100 else { throw WardrobeWriteError("Resolve this record's pending save first.") }
        var replay = original
        replay.dispatched = true; replay.rejected = false; replay.retryAfter = nil; replay.problem = nil
        try commit(items + [replay])
    }

    func remove(_ item: WardrobePending) throws {
        guard let stored = items.first(where: { $0.id == item.id }) else { return }
        guard stillOwner(), !sending, !stored.dispatched || stored.rejected else {
            throw WardrobeWriteError("Retry this save to find out whether Retro received it before removing it.")
        }
        try commit(items.filter { $0.id != item.id })
    }

    func replaceRejected(_ id: String, operation: String, fields: [String: Any]) throws {
        guard stillOwner(), problem == nil, !sending, let stored = items.first(where: { $0.id == id }), stored.rejected,
              fields["id"] as? String == stored.entity else { throw WardrobeWriteError("Refresh the rejected request before replacing it.") }
        let key = UUID().uuidString.lowercased()
        var fields = fields; fields["idempotency_key"] = key
        let body = try JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
        let replacement = WardrobePending(id: key, entity: stored.entity, operation: operation, title: stored.title, body: body, createdAt: Date(), context: stored.context)
        try commit(items.map { $0.id == id ? replacement : $0 })
    }

    func drain(force: Bool = false) async -> Bool {
        guard stillOwner(), problem == nil, !sending else { return false }
        sending = true
        defer { sending = false }
        var changed = false
        while stillOwner(), !Task.isCancelled, let index = items.firstIndex(where: { !$0.rejected }) {
            if !force, let retryAfter = items[index].retryAfter, retryAfter > Date() { break }
            var next = items
            next[index].dispatched = true
            next[index].problem = "Awaiting acknowledgement. Retry uses the original save."
            do { try commit(next) } catch { problem = "Pending saves could not be stored. Reopen Retro to retry. \(error.localizedDescription)"; break }
            let item = items[index]
            let result = await send(item.operation, item.body)
            guard stillOwner(), !Task.isCancelled else { break }
            do {
                if case .ok = result {
                    try commit(items.filter { $0.id != item.id })
                    acknowledgements += 1
                    acknowledgedIDs.insert(item.id)
                    changed = true
                } else {
                    next = items
                    let rejected: Bool
                    if case .failed(let code, _) = result {
                        rejected = ["conflict", "duplicate", "invalid_input", "not_found", "too_large"].contains(code ?? "")
                    } else { rejected = false }
                    next[index].rejected = rejected
                    next[index].problem = result.problem
                    next[index].retryAfter = rejected ? nil : Date().addingTimeInterval(10)
                    try commit(next)
                    if !rejected { break }
                }
            } catch { problem = "Pending saves could not be stored. Reopen Retro to retry. \(error.localizedDescription)"; break }
        }
        return changed
    }

    private func commit(_ next: [WardrobePending]) throws { try save(next); items = next }
}

struct WardrobeWriteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
