import Foundation

// Wire records stay independent of the productivity demo and its restricted slots/colours.
struct WardrobeGarment: Codable, Identifiable, Equatable {
    let id: String
    let version: Int64
    let name: String
    let category: String
    let availability: String
    let subtype: String?
    let colours: [String]?
    let warmth: String?
    let seasons: [String]?
    let formality: String?
    let material: String?
    let brand: String?
    let notes: String?
    let favourite: Bool?
    let mediaIDs: [String]?
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String
    let wearDays: Int64
    let wearEvents: Int64
    let lastWornOn: String?

    enum CodingKeys: String, CodingKey {
        case id, version, name, category, availability, subtype, colours, warmth, seasons, formality, material, brand, notes, favourite
        case mediaIDs = "media_ids", archivedAt = "archived_at", createdAt = "created_at", updatedAt = "updated_at"
        case wearDays = "wear_days", wearEvents = "wear_events", lastWornOn = "last_worn_on"
    }
}

struct WardrobeOutfit: Codable, Identifiable, Equatable {
    let id: String
    let version: Int64
    let day: String
    let timeZone: String
    let state: String
    let label: String?
    let occasion: String?
    let notes: String?
    let source: String?
    let previousState: String?
    let confirmedAt: String?
    let createdAt: String
    let updatedAt: String
    let items: [WardrobeOutfitItem]

    enum CodingKeys: String, CodingKey {
        case id, version, day, state, label, occasion, notes, source, items
        case timeZone = "time_zone", previousState = "previous_state", confirmedAt = "confirmed_at"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    var title: String { label.flatMap { $0.isEmpty ? nil : $0 } ?? "Outfit" }
}

struct WardrobeOutfitItem: Codable, Identifiable, Equatable {
    let garmentID: String
    let role: String
    let snapshot: WardrobeGarment?
    var id: String { garmentID }
    enum CodingKeys: String, CodingKey { case garmentID = "garment_id", role, snapshot }
}

struct WardrobePage<Item: Codable>: Codable {
    var items: [Item]
    var nextCursor: String?
    enum CodingKeys: String, CodingKey { case items, nextCursor = "next_cursor" }
}

struct WardrobeDay: Codable {
    let day: String
    let outfits: [WardrobeOutfit]
}

struct WardrobeGarmentResult: Codable { let garment: WardrobeGarment }
struct WardrobeOutfitResult: Codable { let outfit: WardrobeOutfit }
struct WardrobeID: Encodable { let id: String }
struct WardrobeDayQuery: Encodable { let day: String }

struct WardrobeInventoryQuery: Codable, Hashable {
    var search = ""
    var category = ""
    var availability = ""
    var includeArchived = false
    var limit = 50
    var cursor: String?
    enum CodingKeys: String, CodingKey {
        case search, category, availability, limit, cursor
        case includeArchived = "include_archived"
    }
}

struct WardrobeHistoryQuery: Codable, Hashable {
    var state = "worn"
    var from = ""
    var to = ""
    var garmentID = ""
    enum CodingKeys: String, CodingKey { case state, from, to, limit, cursor; case garmentID = "garment_id" }
    var limit = 50
    var cursor: String?
}

enum WardrobeVocabulary {
    static let categories = ["top", "bottom", "one_piece", "outerwear", "footwear", "accessory", "other"]
    static let availability = ["ready", "needs_wash", "washing", "unavailable"]
    static func title(_ value: String) -> String { value.replacingOccurrences(of: "_", with: " ").capitalized }
    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
