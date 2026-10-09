import CryptoKit
import Foundation
import Observation

struct WardrobeRead<Value> {
    var value: Value?
    var loading = false
    var problem: String?
    var cached = false
    var savedAt: Date?
}

struct WardrobeCached<Value: Codable>: Codable {
    let value: Value
    let savedAt: Date
}

@MainActor @Observable
final class WardrobeStore {
    var inventory = WardrobeRead<WardrobePage<WardrobeGarment>>()
    var history = WardrobeRead<WardrobePage<WardrobeOutfit>>()
    var day = WardrobeRead<WardrobeDay>()
    let writes: WardrobeWrites
    let photos: WardrobePhotos
    let drafts: WardrobeSavedDrafts
    var isCurrentOwner: Bool { engine.isCurrentOwner }
    var changes: Int { writes.acknowledgements }
    private let engine: Engine
    private let cache: DiskCache
    private var inventoryQuery = WardrobeInventoryQuery()
    private var historyQuery = WardrobeHistoryQuery()
    private var inventoryRevision = 0
    private var historyRevision = 0
    private var dayRevision = 0
    private var selectedDay: String?
    private var recordRevisions: [String: Int] = [:]

    init(engine: Engine) {
        self.engine = engine
        cache = DiskCache(owner: engine.owner)
        let writes = WardrobeWrites(engine: engine)
        self.writes = writes
        photos = WardrobePhotos(engine: engine, writes: writes)
        drafts = WardrobeSavedDrafts(engine: engine)
    }

    func sync(force: Bool = false) async {
        var changed = await writes.drain(force: force)
        await photos.step()
        if await writes.drain() { changed = true }
        photos.reconcile()
        guard changed, engine.isCurrentOwner else { return }
        await refreshInventory(inventoryQuery)
        await refreshHistory(historyQuery)
        if let selectedDay { await refreshDay(selectedDay) }
    }

    func submit(_ operation: String, entity: String, title: String, fields: [String: Any], context: String? = nil) throws {
        try writes.enqueue(operation: operation, entity: entity, title: title, fields: fields, context: context)
        Task { await sync() }
    }

    func choices(_ query: WardrobeInventoryQuery) async -> Api<WardrobePage<WardrobeGarment>> {
        await engine.call("garments_list", query)
    }

    func currentSummary(_ item: WardrobePending) async -> String {
        if item.operation.hasPrefix("garments_") {
            let result: Api<WardrobeGarmentResult> = await engine.call("garments_get", WardrobeID(id: item.entity))
            if case .ok(let result) = result {
                let g = result.garment
                return "Current: \(g.name) · \(WardrobeVocabulary.title(g.category)) · \(g.archivedAt == nil ? g.availability : "archived")\nColours: \((g.colours ?? []).joined(separator: ", "))\nNotes: \(g.notes ?? "")\nOpen the garment to review all current details."
            }
            return result.problem ?? "Could not load the current garment."
        }
        let result: Api<WardrobeOutfitResult> = await engine.call("outfits_get", WardrobeID(id: item.entity))
        if case .ok(let result) = result {
            let o = result.outfit
            return "Current: \(o.title) · \(o.day) · \(o.state) · \(o.timeZone)\nPieces: \(o.items.map { $0.snapshot?.name ?? $0.garmentID }.joined(separator: ", "))\nNotes: \(o.notes ?? "")"
        }
        return result.problem ?? "Could not load the current outfit."
    }

    func refreshInventory(_ query: WardrobeInventoryQuery, debounce: Bool = false) async {
        guard engine.isCurrentOwner else { return }
        inventoryRevision += 1
        let revision = inventoryRevision
        let previous = query == inventoryQuery ? inventory : WardrobeRead<WardrobePage<WardrobeGarment>>()
        inventoryQuery = query
        inventory = restored(key("inventory", query))
        if inventory.value == nil { inventory = previous; inventory.cached = previous.value != nil }
        inventory.problem = nil
        inventory.loading = true
        defer { if revision == inventoryRevision { inventory.loading = false } }
        if debounce, !query.search.isEmpty {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
        let result: Api<WardrobePage<WardrobeGarment>> = await engine.call("garments_list", query)
        guard revision == inventoryRevision, engine.isCurrentOwner, !Task.isCancelled else { return }
        inventory = received(result, retaining: inventory, key: key("inventory", query))
    }

    func moreInventory() async {
        guard engine.isCurrentOwner, !inventory.loading, let cursor = inventory.value?.nextCursor else { return }
        let revision = inventoryRevision
        let baseQuery = inventoryQuery
        var query = baseQuery
        query.cursor = cursor
        inventory.loading = true
        defer { if revision == inventoryRevision { inventory.loading = false } }
        let result: Api<WardrobePage<WardrobeGarment>> = await engine.call("garments_list", query)
        guard revision == inventoryRevision, engine.isCurrentOwner, !Task.isCancelled else { return }
        switch result {
        case .ok(let page):
            let prior = inventory.value?.items ?? []
            let ids = Set(prior.map(\.id))
            let merged = WardrobePage(items: prior + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
            inventory = received(.ok(merged), retaining: inventory, key: key("inventory", baseQuery))
        default: inventory.problem = result.problem
        }
    }

    func refreshHistory(_ query: WardrobeHistoryQuery) async {
        guard engine.isCurrentOwner else { return }
        historyRevision += 1
        let revision = historyRevision
        let previous = query == historyQuery ? history : WardrobeRead<WardrobePage<WardrobeOutfit>>()
        historyQuery = query
        history = restored(key("history", query))
        if history.value == nil { history = previous; history.cached = previous.value != nil }
        history.problem = nil
        history.loading = true
        defer { if revision == historyRevision { history.loading = false } }
        let result: Api<WardrobePage<WardrobeOutfit>> = await engine.call("outfits_list", query)
        guard revision == historyRevision, engine.isCurrentOwner, !Task.isCancelled else { return }
        history = received(result, retaining: history, key: key("history", query))
    }

    func moreHistory() async {
        guard engine.isCurrentOwner, !history.loading, let cursor = history.value?.nextCursor else { return }
        let revision = historyRevision
        let baseQuery = historyQuery
        var query = baseQuery
        query.cursor = cursor
        history.loading = true
        defer { if revision == historyRevision { history.loading = false } }
        let result: Api<WardrobePage<WardrobeOutfit>> = await engine.call("outfits_list", query)
        guard revision == historyRevision, engine.isCurrentOwner, !Task.isCancelled else { return }
        switch result {
        case .ok(let page):
            let prior = history.value?.items ?? []
            let ids = Set(prior.map(\.id))
            let merged = WardrobePage(items: prior + page.items.filter { !ids.contains($0.id) }, nextCursor: page.nextCursor)
            history = received(.ok(merged), retaining: history, key: key("history", baseQuery))
        default: history.problem = result.problem
        }
    }

    func refreshDay(_ selectedDay: String) async {
        guard engine.isCurrentOwner else { return }
        dayRevision += 1
        let revision = dayRevision
        let query = WardrobeDayQuery(day: selectedDay)
        let cacheKey = key("day", query)
        let previous = selectedDay == self.selectedDay ? day : WardrobeRead<WardrobeDay>()
        self.selectedDay = selectedDay
        day = restored(cacheKey)
        if day.value == nil { day = previous; day.cached = previous.value != nil }
        day.problem = nil
        day.loading = true
        defer { if revision == dayRevision { day.loading = false } }
        let result: Api<WardrobeDay> = await engine.call("wardrobe_day_get", query)
        guard revision == dayRevision, engine.isCurrentOwner, !Task.isCancelled else { return }
        day = received(result, retaining: day, key: cacheKey)
    }

    func record<Value: Codable>(_ operation: String, id: String, fallback: Value) async -> WardrobeRead<Value> {
        guard engine.isCurrentOwner else { return WardrobeRead(problem: Api<Value>.unauthorized.problem) }
        let query = WardrobeID(id: id)
        let cacheKey = key(operation, query)
        let revision = (recordRevisions[cacheKey] ?? 0) + 1
        recordRevisions[cacheKey] = revision
        var previous: WardrobeRead<Value> = restored(cacheKey)
        if previous.value == nil { previous.value = fallback; previous.cached = true }
        let result: Api<Value> = await engine.call(operation, query)
        guard recordRevisions[cacheKey] == revision, engine.isCurrentOwner, !Task.isCancelled else { return WardrobeRead() }
        return received(result, retaining: previous, key: cacheKey)
    }

    func read<Input: Encodable, Value: Codable>(_ operation: String, input: Input) async -> WardrobeRead<Value> {
        guard engine.isCurrentOwner else { return WardrobeRead(problem: Api<Value>.unauthorized.problem) }
        let cacheKey = key(operation, input)
        let revision = (recordRevisions[cacheKey] ?? 0) + 1
        recordRevisions[cacheKey] = revision
        let previous: WardrobeRead<Value> = restored(cacheKey)
        let result: Api<Value> = await engine.call(operation, input)
        guard recordRevisions[cacheKey] == revision, engine.isCurrentOwner, !Task.isCancelled else { return WardrobeRead() }
        return received(result, retaining: previous, key: cacheKey)
    }

    func reviewSuggestion(_ suggestion: WardrobeSuggestion, query: WardrobeSuggestQuery) async throws -> WardrobeOutfitDraft {
        try query.validate()
        guard (1...30).contains(suggestion.items.count), Set(suggestion.items.map(\.garmentID)).count == suggestion.items.count,
              Set(query.requiredIDs).isSubset(of: Set(suggestion.items.map(\.garmentID))),
              Set(query.excludedIDs).isDisjoint(with: suggestion.items.map(\.garmentID)),
              !query.excludedCombinations.contains(suggestion.fingerprint) else { throw WardrobeWriteError("This suggestion does not match the requested pieces. Generate again.") }
        var draft = WardrobeOutfitDraft(date: WardrobeDraftValidation.date(query.day) ?? Date())
        draft.source = "suggestion"; draft.occasion = query.occasion
        for item in suggestion.items {
            guard WardrobeMediaPath.path(id: item.garmentID) != nil, WardrobeDraftValidation.roles.contains(item.role), !writes.contains(item.garmentID) else { throw WardrobeWriteError("Resolve the pieces' pending saves and generate again.") }
            let result: Api<WardrobeGarmentResult> = await engine.call("garments_get", WardrobeID(id: item.garmentID))
            try Task.checkCancellation()
            guard engine.isCurrentOwner else { throw WardrobeWriteError("Sign in again before reviewing this suggestion.") }
            guard case .ok(let result) = result else { throw WardrobeWriteError(result.problem ?? "Could not refresh the suggested garment.") }
            let garment = result.garment
            guard garment.id == item.garmentID, garment.version == item.version, garment.archivedAt == nil, garment.availability == "ready" else { throw WardrobeWriteError("A suggested piece changed or is unavailable. Generate fresh suggestions.") }
            draft.items.append(WardrobeSelection(id: garment.id, name: garment.name, role: item.role))
        }
        return draft
    }

    func reuseOutfit(_ id: String) async throws -> WardrobeReuseReview {
        guard engine.isCurrentOwner, !writes.contains(id) else { throw WardrobeWriteError("Wait for the original outfit's pending save before reusing it.") }
        let result: Api<WardrobeOutfitResult> = await engine.call("outfits_get", WardrobeID(id: id))
        try Task.checkCancellation()
        guard case .ok(let result) = result, result.outfit.id == id, engine.isCurrentOwner else { throw WardrobeWriteError(result.problem ?? "A fresh outfit is needed before reusing it.") }
        let outfit = result.outfit
        guard (1...30).contains(outfit.items.count), Set(outfit.items.map(\.garmentID)).count == outfit.items.count else { throw WardrobeWriteError("Invalid original outfit pieces.") }
        var pieces: [WardrobeReusePiece] = []
        for item in outfit.items {
            guard WardrobeMediaPath.path(id: item.garmentID) != nil, WardrobeDraftValidation.roles.contains(item.role) else { throw WardrobeWriteError("Invalid original outfit piece.") }
            let current: Api<WardrobeGarmentResult> = await engine.call("garments_get", WardrobeID(id: item.garmentID))
            try Task.checkCancellation()
            guard engine.isCurrentOwner else { throw WardrobeWriteError("Sign in again to reuse an outfit.") }
            if case .ok(let current) = current {
                let garment = current.garment
                guard garment.id == item.garmentID else { throw WardrobeWriteError("The current garment does not match the original piece.") }
                let problem = writes.contains(garment.id) ? "Pending save" : garment.archivedAt != nil ? "Archived" : garment.availability != "ready" ? WardrobeVocabulary.title(garment.availability) : nil
                pieces.append(WardrobeReusePiece(id: garment.id, name: garment.name, role: item.role, problem: problem))
            } else if case .failed("not_found", _) = current {
                pieces.append(WardrobeReusePiece(id: item.garmentID, name: item.snapshot?.name ?? "Missing garment", role: item.role, problem: "No longer available"))
            } else { throw WardrobeWriteError(current.problem ?? "Could not refresh an original piece. Try again when connected.") }
        }
        guard !writes.contains(id) else { throw WardrobeWriteError("The original outfit has a pending save. Refresh before reusing it.") }
        return WardrobeReuseReview(outfit: outfit, pieces: pieces)
    }
    func refreshReusePlan(_ draft: WardrobeOutfitDraft) async throws -> WardrobeOutfitDraft {
        var draft = draft
        for index in draft.items.indices {
            let item = draft.items[index]
            let result: Api<WardrobeGarmentResult> = await engine.call("garments_get", WardrobeID(id: item.id))
            try Task.checkCancellation()
            guard engine.isCurrentOwner else { throw WardrobeWriteError("Sign in again before composing this plan.") }
            guard case .ok(let current) = result, current.garment.id == item.id, current.garment.archivedAt == nil,
                  current.garment.availability == "ready", !writes.contains(item.id) else { throw WardrobeWriteError("\(item.name) changed or could not be refreshed. Review the pieces again.") }
            draft.items[index].name = current.garment.name
        }
        _ = try draft.fields()
        return draft
    }

    private func key<Input: Encodable>(_ prefix: String, _ input: Input) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // All inputs here are fixed Codable wire types, never arbitrary caller paths.
        let data = (try? encoder.encode(input)) ?? Data()
        let digest = SHA256.hash(data: Data(engine.cacheScope.utf8) + data).map { String(format: "%02x", $0) }.joined()
        return "wardrobe-\(prefix)-\(digest)"
    }

    private func restored<Value: Codable>(_ key: String) -> WardrobeRead<Value> {
        guard let saved = cache.load(WardrobeCached<Value>.self, key) else { return WardrobeRead() }
        return WardrobeRead(value: saved.value, cached: true, savedAt: saved.savedAt)
    }

    private func received<Value: Codable>(_ result: Api<Value>, retaining previous: WardrobeRead<Value>, key: String) -> WardrobeRead<Value> {
        switch result {
        case .ok(let value):
            let now = Date()
            cache.save(WardrobeCached(value: value, savedAt: now), as: key)
            return WardrobeRead(value: value, savedAt: now)
        default:
            var state = previous
            state.loading = false
            state.problem = result.problem
            return state
        }
    }
}
