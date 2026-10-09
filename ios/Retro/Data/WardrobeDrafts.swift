import Foundation

struct WardrobeGarmentDraft: Codable, Equatable {
    var name = ""
    var category = "top"
    var availability = "ready"
    var subtype = ""
    var colours = ""
    var warmth = "unknown"
    var seasons = ""
    var formality = ""
    var material = ""
    var brand = ""
    var notes = ""
    var favourite = false

    init(_ garment: WardrobeGarment? = nil) {
        guard let garment else { return }
        name = garment.name; category = garment.category; availability = garment.availability
        subtype = garment.subtype ?? ""; colours = (garment.colours ?? []).joined(separator: ", ")
        warmth = garment.warmth ?? "unknown"; seasons = (garment.seasons ?? []).joined(separator: ", ")
        formality = garment.formality ?? ""; material = garment.material ?? ""; brand = garment.brand ?? ""
        notes = garment.notes ?? ""; favourite = garment.favourite ?? false
    }

    init(createFields fields: [String: Any]) throws {
        self.init()
        guard let name = fields["name"] as? String, let category = fields["category"] as? String else { throw WardrobeWriteError("The queued garment details could not be opened.") }
        self.name = name; self.category = category
        availability = try WardrobeDraftValidation.text(fields, "availability", fallback: "ready")
        subtype = try WardrobeDraftValidation.text(fields, "subtype")
        colours = try WardrobeDraftValidation.values(fields, "colours").joined(separator: ", ")
        warmth = try WardrobeDraftValidation.text(fields, "warmth", fallback: "unknown")
        seasons = try WardrobeDraftValidation.values(fields, "seasons").joined(separator: ", ")
        formality = try WardrobeDraftValidation.text(fields, "formality"); material = try WardrobeDraftValidation.text(fields, "material")
        brand = try WardrobeDraftValidation.text(fields, "brand"); notes = try WardrobeDraftValidation.text(fields, "notes")
        if let value = fields["favourite"] { guard let value = value as? Bool else { throw WardrobeWriteError("Invalid favourite value.") }; favourite = value }
    }

    func fields() throws -> [String: Any] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WardrobeWriteError("Give this garment a name.") }
        let strings = ["name": name, "subtype": subtype, "formality": formality, "material": material, "brand": brand, "notes": notes]
        try WardrobeDraftValidation.strings(strings)
        guard WardrobeVocabulary.categories.contains(category), WardrobeVocabulary.availability.contains(availability),
              WardrobeDraftValidation.warmths.contains(warmth) else { throw WardrobeWriteError("Choose valid garment details.") }
        var fields: [String: Any] = strings
        fields["category"] = category; fields["availability"] = availability; fields["warmth"] = warmth
        fields["colours"] = try WardrobeDraftValidation.list(colours)
        fields["seasons"] = try WardrobeDraftValidation.list(seasons)
        fields["favourite"] = favourite
        return fields
    }
}

struct WardrobeSelection: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var role: String
    var fields: [String: String] { ["garment_id": id, "role": role] }
}

struct WardrobeOutfitDraft: Codable, Equatable {
    var date: Date
    var timeZone: String
    var state: String
    var label: String
    var occasion: String
    var notes: String
    var items: [WardrobeSelection]
    var source = "manual"

    init(_ outfit: WardrobeOutfit? = nil, date: Date = Date()) {
        self.date = outfit.flatMap { WardrobeDraftValidation.date($0.day) } ?? date
        timeZone = outfit?.timeZone ?? TimeZone.current.identifier
        state = outfit?.state ?? "planned"
        label = outfit?.label ?? ""; occasion = outfit?.occasion ?? ""; notes = outfit?.notes ?? ""
        items = outfit?.items.map { WardrobeSelection(id: $0.garmentID, name: $0.snapshot?.name ?? "Garment", role: $0.role) } ?? []
    }

    init(createFields fields: [String: Any]) throws {
        guard let day = fields["day"] as? String, let date = WardrobeDraftValidation.date(day),
              let pieces = fields["items"] as? [[String: String]] else { throw WardrobeWriteError("The queued outfit details could not be opened.") }
        self.init(date: date)
        timeZone = try WardrobeDraftValidation.text(fields, "time_zone")
        state = try WardrobeDraftValidation.text(fields, "state", fallback: "planned")
        source = try WardrobeDraftValidation.text(fields, "source", fallback: "manual")
        label = try WardrobeDraftValidation.text(fields, "label"); occasion = try WardrobeDraftValidation.text(fields, "occasion")
        notes = try WardrobeDraftValidation.text(fields, "notes")
        items = try pieces.map {
            guard let id = $0["garment_id"], WardrobeMediaPath.path(id: id) != nil, let role = $0["role"] else { throw WardrobeWriteError("Invalid queued outfit pieces.") }
            return WardrobeSelection(id: id, name: "Garment · " + String(id.prefix(8)), role: role)
        }
        guard items.count <= 30, Set(items.map(\.id)).count == items.count else { throw WardrobeWriteError("Invalid queued outfit pieces.") }
    }

    func fields() throws -> [String: Any] {
        try WardrobeDraftValidation.strings(["label": label, "occasion": occasion, "notes": notes])
        guard (timeZone == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(timeZone)), let zone = TimeZone(identifier: timeZone) else { throw WardrobeWriteError("Use an IANA time zone such as America/Los_Angeles.") }
        guard ["planned", "worn"].contains(state) else { throw WardrobeWriteError("Choose a planned or worn outfit.") }
        guard (1...30).contains(items.count), Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.id != "00000000-0000-0000-0000-000000000000" && WardrobeDraftValidation.roles.contains($0.role) }) else {
            throw WardrobeWriteError("Choose 1–30 different garments and a role for each.")
        }
        let day = WardrobeVocabulary.dayKey(date)
        guard day.count == 10 else { throw WardrobeWriteError("Choose a date between years 1 and 9999.") }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
        guard state != "worn" || day <= formatter.string(from: Date()) else { throw WardrobeWriteError("Future outfits can be planned, but cannot be recorded worn.") }
        return ["day": day, "time_zone": timeZone, "label": label, "occasion": occasion, "notes": notes,
                "items": items.map(\.fields)]
    }
}

enum WardrobeDraftValidation {
    static let roles = ["base", "mid", "bottom", "one_piece", "outer", "feet", "accessory", "other"]
    static let warmths = ["unknown", "light", "mid", "warm"]
    static func text(_ fields: [String: Any], _ key: String, fallback: String = "") throws -> String {
        guard let value = fields[key] else { return fallback }
        guard let value = value as? String else { throw WardrobeWriteError("Invalid queued \(key) value.") }
        return value
    }
    static func values(_ fields: [String: Any], _ key: String) throws -> [String] {
        guard let value = fields[key] else { return [] }
        guard let value = value as? [String] else { throw WardrobeWriteError("Invalid queued \(key) values.") }
        return value
    }
    static func strings(_ fields: [String: String]) throws {
        for (key, value) in fields where value.utf8.count > (key == "notes" ? 4000 : 100) {
            throw WardrobeWriteError("\(WardrobeVocabulary.title(key)) is too long (maximum \(key == "notes" ? 4000 : 100) UTF-8 bytes).")
        }
    }
    static func list(_ value: String) throws -> [String] {
        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard items.count <= 10, Set(items).count == items.count, items.allSatisfy({ $0.utf8.count <= 100 }) else {
            throw WardrobeWriteError("Use up to 10 different comma-separated values, each at most 100 UTF-8 bytes.")
        }
        return items
    }
    static func date(_ day: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard day.count == 10, let value = formatter.date(from: day), formatter.string(from: value) == day else { return nil }
        return value
    }
    static func patch(_ fields: [String: Any], original: [String: Any]) -> [String: Any] {
        fields.filter { key, value in
            guard let previous = original[key] else { return true }
            return !NSDictionary(dictionary: ["value": value]).isEqual(to: ["value": previous])
        }
    }
    static func edit(id: String, version: Int64) -> [String: Any] { ["id": id, "expected_version": version] }
    static func role(_ category: String) -> String {
        ["top": "base", "bottom": "bottom", "one_piece": "one_piece", "outerwear": "outer", "footwear": "feet", "accessory": "accessory"][category] ?? "other"
    }
}
