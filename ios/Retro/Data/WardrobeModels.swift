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
    let pattern: String?
    let style: String?
    let fit: String?
    let notes: String?
    let favourite: Bool?
    let mediaIDs: [String]?
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String
    let wearDays: Int64
    let wearEvents: Int64
    let lastWornOn: String?
    var care: WardrobeCare? = nil
    var laundryReminder: WardrobeLaundryReminder? = nil
    var purchase: WardrobePurchase? = nil

    enum CodingKeys: String, CodingKey {
        case id, version, name, category, availability, subtype, colours, warmth, seasons, formality, material, brand, notes, favourite, care, pattern, style, fit, purchase
        case mediaIDs = "media_ids", archivedAt = "archived_at", createdAt = "created_at", updatedAt = "updated_at"
        case wearDays = "wear_days", wearEvents = "wear_events", lastWornOn = "last_worn_on"
        case laundryReminder = "laundry_reminder"
    }
}

// Money stays in integer minor units of an explicit currency. Nothing is converted, and a missing
// amount is unknown rather than zero. The engine supplies the currency's exponent for display.
struct WardrobePurchase: Codable, Equatable {
    let date: String?
    let currency: String?
    let amountMinor: Int64?
    let currencyExponent: Int?
    let evidence: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case date, currency, evidence, source
        case amountMinor = "amount_minor", currencyExponent = "currency_exponent"
    }

    var amountText: String? {
        guard let amountMinor else { return nil }
        let exponent = max(0, min(currencyExponent ?? 2, 3))
        let scale = [Int64(1), 10, 100, 1000][exponent]
        let whole = amountMinor / scale, fraction = amountMinor % scale
        return exponent == 0 ? "\(whole)" : "\(whole)." + String(format: "%0\(exponent)lld", fraction)
    }
    var amountSummary: String? {
        guard let amountText else { return currency }
        return currency.map { "\(amountText) \($0)" } ?? amountText
    }
    var summary: String {
        var parts: [String] = []
        if let date, !date.isEmpty { parts.append(date) }
        if let amountSummary { parts.append(amountSummary) }
        if let source, source != "manual" { parts.append(WardrobeVocabulary.title(source)) }
        return parts.joined(separator: " · ")
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
    // Counted by the engine in the same read as this page; other lists do not report it.
    var totalMatches: Int64? = nil
    enum CodingKeys: String, CodingKey { case items, totalMatches = "total_matches"; case nextCursor = "next_cursor" }
}

struct WardrobeDay: Codable {
    let day: String
    let outfits: [WardrobeOutfit]
    var selection: WardrobeDaySelection? = nil
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
    var brand = ""
    var notes = ""
    var colour = ""
    var season = ""
    var favourite: Bool? = nil
    var washMethod = ""
    var careConfirmed: Bool? = nil
    var sort = "id"
    var limit = 50
    var cursor: String?
    enum CodingKeys: String, CodingKey {
        case search, category, availability, limit, cursor, brand, notes, colour, season, favourite, sort
        case includeArchived = "include_archived"
        case washMethod = "wash_method"
        case careConfirmed = "care_confirmed"
    }
    static let sorts = ["id", "name", "recent", "added"]
    static let washMethods = ["unknown", "machine", "hand", "dry_clean", "do_not_wash"]
    var hasTextFilters: Bool { ![search, brand, notes, colour, season].allSatisfy(\.isEmpty) }
    var sortTitle: String {
        ["id": "Default order", "name": "Name", "recent": "Recently updated", "added": "Newest first"][sort] ?? sort
    }
    // Shown above the grid so the owner can see exactly which predicates are narrowing the list.
    var activeFilters: [String] {
        var values: [String] = []
        for (label, text) in [("Name", search), ("Brand", brand), ("Notes", notes), ("Colour", colour), ("Season", season)] where !text.isEmpty {
            values.append("\(label): \(text)")
        }
        if !category.isEmpty { values.append("Category: \(WardrobeVocabulary.title(category))") }
        if !availability.isEmpty { values.append("Availability: \(WardrobeVocabulary.title(availability))") }
        if !washMethod.isEmpty { values.append("Wash: \(WardrobeVocabulary.title(washMethod))") }
        if let favourite { values.append(favourite ? "Favourites only" : "Not favourite") }
        if let careConfirmed { values.append(careConfirmed ? "Care reviewed" : "Care needs review") }
        if includeArchived { values.append("Including archived") }
        return values
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
