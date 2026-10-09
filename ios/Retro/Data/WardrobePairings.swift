import Foundation

struct WardrobePairing: Codable, Identifiable {
    let id: String
    let version: Int64
    let name: String
    let notes: String?
    let items: [WardrobeOutfitItem]
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, version, name, notes, items
        case archivedAt = "archived_at", createdAt = "created_at", updatedAt = "updated_at"
    }
    func validate() throws {
        guard WardrobeMediaPath.path(id: id) != nil, version > 0, (2...30).contains(items.count),
              Set(items.map(\.garmentID)).count == items.count,
              items.allSatisfy({ WardrobeMediaPath.path(id: $0.garmentID) != nil && WardrobeDraftValidation.roles.contains($0.role) && $0.snapshot?.id == $0.garmentID && ($0.snapshot?.version ?? 0) > 0 }) else { throw WardrobeWriteError("The saved pairing needs a fresh record review.") }
        _ = try WardrobePairingDraft(self).fields()
    }
}
struct WardrobePairingResult: Codable { let pairing: WardrobePairing }
struct WardrobePairingQuery: Codable, Hashable {
    var garmentID = ""
    var search = ""
    var includeArchived = false
    var limit = 20
    var cursor: String?
    enum CodingKeys: String, CodingKey { case search, limit, cursor; case garmentID = "garment_id", includeArchived = "include_archived" }
}
struct WardrobePairingDraft: Equatable {
    var name = ""
    var notes = ""
    var items: [WardrobeSelection] = []
    init(_ pairing: WardrobePairing? = nil, items: [WardrobeSelection] = []) {
        name = pairing?.name ?? ""; notes = pairing?.notes ?? ""
        self.items = pairing?.items.map { WardrobeSelection(id: $0.garmentID, name: $0.snapshot?.name ?? "Garment", role: $0.role) } ?? items
    }
    init(request: WardrobePending) throws {
        guard request.operation == "pairings_create", let fields = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              fields["id"] as? String == request.entity, fields["idempotency_key"] as? String == request.id, let name = fields["name"] as? String,
              let pieces = fields["items"] as? [[String: String]] else { throw WardrobeWriteError("The original pairing request could not be opened.") }
        self.name = name; notes = fields["notes"] as? String ?? ""
        items = try pieces.map { piece in
            guard let id = piece["garment_id"], let role = piece["role"] else { throw WardrobeWriteError("Review the original pairing pieces.") }
            return WardrobeSelection(id: id, name: "Saved piece", role: role)
        }
        try WardrobeDraftValidation.items(items)
    }
    func fields() throws -> [String: Any] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(name.utf8.count), notes.utf8.count <= 4000, items.count >= 2 else { throw WardrobeWriteError("Give the pairing a name and choose at least two pieces.") }
        try WardrobeDraftValidation.items(items)
        return ["name": name, "notes": notes, "items": items.map { ["garment_id": $0.id, "role": $0.role] }]
    }
}

struct WardrobeDaySelection: Codable {
    let id: String
    let day: String
    let version: Int64
    let outfitID: String?
    let timeZone: String
    let updatedAt: String?
    let outfit: WardrobeOutfit?
    let problem: String?
    enum CodingKeys: String, CodingKey {
        case id, day, version, outfit, problem
        case outfitID = "outfit_id", timeZone = "time_zone", updatedAt = "updated_at"
    }
    func validate() throws {
        guard WardrobeMediaPath.path(id: id) != nil, WardrobeDraftValidation.date(day) != nil, version >= 0,
              (problem?.utf8.count ?? 0) <= 1000, outfitID == outfit?.id,
              (version == 0 ? outfitID == nil && updatedAt == nil && timeZone.isEmpty : updatedAt.flatMap(GatewayAgentResult.date) != nil && TimeZone(identifier: timeZone) != nil) else { throw WardrobeWriteError("Refresh the daily selection before changing it.") }
    }
    func fields(choosing outfit: WardrobeOutfit?) throws -> [String: Any] {
        try validate()
        var fields: [String: Any] = ["id": id, "day": day, "expected_version": version, "outfit_id": NSNull()]
        if let outfit {
            guard outfit.day == day, outfit.state == "planned", outfit.version > 0, WardrobeMediaPath.path(id: outfit.id) != nil,
                  TimeZone(identifier: outfit.timeZone) != nil, !outfit.items.isEmpty,
                  outfit.items.allSatisfy({ $0.snapshot?.id == $0.garmentID && $0.snapshot?.archivedAt == nil && $0.snapshot?.availability == "ready" }) else { throw WardrobeWriteError("Choose a ready saved plan for this date. Selecting it does not record a wear.") }
            try WardrobeDraftValidation.items(outfit.items.map { WardrobeSelection(id: $0.garmentID, name: $0.snapshot?.name ?? "Garment", role: $0.role) })
            fields["outfit_id"] = outfit.id; fields["expected_outfit_version"] = outfit.version
        } else {
            guard version > 0 else { throw WardrobeWriteError("There is no saved selection to clear.") }
        }
        return fields
    }
}
struct WardrobeDaySelectionResult: Codable { let selection: WardrobeDaySelection }

extension WardrobeStore {
    func planPairing(_ pairing: WardrobePairing, date: Date) async throws -> WardrobeOutfitDraft {
        try pairing.validate()
        guard isCurrentOwner, !writes.contains(pairing.id), pairing.archivedAt == nil else { throw WardrobeWriteError("Resolve pending saves or restore the pairing before planning it.") }
        let read: WardrobeRead<WardrobePairingResult> = await self.read("pairings_get", input: WardrobeID(id: pairing.id))
        try Task.checkCancellation()
        guard isCurrentOwner, !read.cached, let current = read.value?.pairing, current.id == pairing.id, current.version == pairing.version, current.archivedAt == nil else { throw WardrobeWriteError(read.problem ?? "The pairing changed. Refresh before planning it.") }
        try current.validate()
        var draft = WardrobeOutfitDraft(date: date)
        draft.label = current.name; draft.notes = current.notes ?? ""
        draft.items = current.items.map { WardrobeSelection(id: $0.garmentID, name: $0.snapshot?.name ?? "Garment", role: $0.role) }
        let fresh = try await refreshReusePlan(draft)
        guard !writes.contains(pairing.id) else { throw WardrobeWriteError("The pairing has a pending save. Refresh before planning it.") }
        return fresh
    }
}
