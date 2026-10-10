import Foundation

// Bounded maintenance over garments the owner selects explicitly. A batch never writes anything itself:
// it builds one frozen per-item request and hands each to the existing durable queue, which keeps its
// one-pending-write-per-entity rule, its 100-item budget and its per-item acknowledgement.
enum WardrobeBatchAction: String, CaseIterable, Identifiable {
    case available, needsWash, favourite, notFavourite, archive, restore
    var id: String { rawValue }
    var title: String {
        switch self {
        case .available: "Mark available"
        case .needsWash: "Mark needs wash"
        case .favourite: "Add to favourites"
        case .notFavourite: "Remove from favourites"
        case .archive: "Archive"
        case .restore: "Restore"
        }
    }
    var operation: String {
        switch self {
        case .archive: "garments_archive"
        case .restore: "garments_restore"
        default: "garments_update"
        }
    }
    var patch: [String: Any]? {
        switch self {
        case .available: ["availability": "ready"]
        case .needsWash: ["availability": "needs_wash"]
        case .favourite: ["favourite": true]
        case .notFavourite: ["favourite": false]
        default: nil
        }
    }
    // Archiving hides a garment from the wardrobe until it is restored, so it is confirmed explicitly.
    var isDestructive: Bool { self == .archive }
    var needsArchived: Bool { self == .restore }
}

struct WardrobeBatchItem: Identifiable, Equatable {
    let id: String
    let name: String
    let version: Int64
    let archived: Bool
    let availability: String
    let favourite: Bool
    init(_ garment: WardrobeGarment) {
        id = garment.id; name = garment.name; version = garment.version
        archived = garment.archivedAt != nil; availability = garment.availability; favourite = garment.favourite ?? false
    }
    var stateTitle: String { archived ? "Archived" : WardrobeVocabulary.title(availability) + (favourite ? " · Favourite" : "") }
}

// The frozen intent for one item: the record's exact version plus the change, and nothing else.
struct WardrobeBatchPlan {
    let action: WardrobeBatchAction
    let items: [WardrobeBatchItem]
    let skipped: [String]
    static let queueBudget = 100

    static func build(action: WardrobeBatchAction, selected: [WardrobeBatchItem], pending: Set<String>, pendingCount: Int = 0) -> WardrobeBatchPlan {
        var items: [WardrobeBatchItem] = [], skipped: [String] = []
        var room = max(0, queueBudget - pendingCount)
        for item in selected {
            if let reason = reason(action, item) {
                skipped.append("\(item.name): \(reason)")
            } else if pending.contains(item.id) {
                skipped.append("\(item.name): has a pending save to review first")
            } else if room < 1 {
                skipped.append("\(item.name): pending saves are full (\(queueBudget))")
            } else {
                room -= 1
                items.append(item)
            }
        }
        return WardrobeBatchPlan(action: action, items: items, skipped: skipped)
    }
    // An item that is already in the requested state is left out instead of writing a no-op.
    static func reason(_ action: WardrobeBatchAction, _ item: WardrobeBatchItem) -> String? {
        switch action {
        case .restore: return item.archived ? nil : "is not archived"
        case .archive: return item.archived ? "is already archived" : nil
        case .available: return item.archived ? "is archived; restore it first" : item.availability == "ready" ? "is already available" : nil
        case .needsWash: return item.archived ? "is archived; restore it first" : item.availability == "needs_wash" ? "already needs wash" : nil
        case .favourite: return item.favourite ? "is already a favourite" : nil
        case .notFavourite: return item.favourite ? nil : "is not a favourite"
        }
    }
    func fields(_ item: WardrobeBatchItem) -> [String: Any] {
        var fields: [String: Any] = ["id": item.id, "expected_version": item.version]
        if let patch = action.patch { fields["patch"] = patch }
        return fields
    }
    var summary: String {
        "\(items.count) \(items.count == 1 ? "garment" : "garments") will be queued as \(items.count == 1 ? "one frozen request" : "separate frozen requests"), each with the version it was reviewed at."
    }
}

enum WardrobeBatchOutcome: Equatable {
    case queued, sending, retrying, rejected(String), acknowledged, settled, unknown
    var title: String {
        switch self {
        case .queued: "Waiting to send"
        case .sending: "Sending"
        case .retrying: "Waiting to retry"
        case .rejected(let message): "Refused: \(message)"
        case .acknowledged: "Saved"
        case .settled: "No longer pending — open the record to confirm its current state"
        case .unknown: "Not queued by this batch"
        }
    }
    // A rejection is the only outcome reported as a failure; an item still queued is never called saved.
    var isFailure: Bool { if case .rejected = self { return true }; return false }
}
enum WardrobeBatchReport {
    // Each item is reported from the queue's own state, never from the batch's intent. An item that has
    // left the queue is only called saved when this session saw it acknowledged.
    static func outcome(_ id: String, pending: [WardrobePending], acknowledged: Set<String>, queued: Set<String>, now: Date = Date()) -> WardrobeBatchOutcome {
        if let item = pending.first(where: { $0.entity == id }) {
            if item.rejected { return .rejected(item.problem ?? "refused by the engine") }
            if item.dispatched { return .sending }
            if let retryAfter = item.retryAfter, retryAfter > now { return .retrying }
            return .queued
        }
        guard queued.contains(id) else { return .unknown }
        return acknowledged.contains(id) ? .acknowledged : .settled
    }
}
