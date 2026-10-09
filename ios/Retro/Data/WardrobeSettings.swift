import Foundation

enum WardrobeSettingsRecord {
    case preferences, care(String), feedback(String)
    var title: String { switch self { case .preferences: "Wardrobe settings"; case .care: "Care instructions"; case .feedback: "Outfit feedback" } }
}

struct WardrobeCare: Codable, Equatable {
    var wash_method = "unknown"
    var max_temp_c: Int?
    var cycle = "unknown"
    var colour_group = "unknown"
    var drying = "unknown"
    var source = "manual"
    var evidence: String?
    var confirmed = false
}
struct WardrobeMachinePreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var temperature_c: Int
    var cycle: String
    var drying: String
}
struct WardrobePreferences: Codable {
    let id: String
    let version: Int64
    let updated_at: String
    var preferred_colours: [String]
    var avoided_colours: [String]
    var preferred_styles: [String]
    var default_occasion: String
    var temperature_unit: String
    var temperature_sensitivity: String
    var cold_threshold_c: Int
    var hot_threshold_c: Int
    var layering_preference: String
    var avoid_repeat_days: Int
    var prefer_underused_items: Bool
    var variety: String
    var machine_presets: [WardrobeMachinePreset]
}
struct WardrobePreferencesResult: Codable { let preferences: WardrobePreferences }
struct WardrobeFeedback: Codable {
    let id: String
    let outfit_id: String
    let outfit_version: Int64
    let version: Int64
    var rating: Int?
    var comfort_rating: Int?
    var style_rating: Int?
    var warmth: String
    var comment: String?
    let updated_at: String?
}
struct WardrobeFeedbackResult: Codable {
    let feedback: WardrobeFeedback
    let current_outfit_version: Int64
    let outfit_state: String
}
struct WardrobeEmpty: Codable {}
struct WardrobeContextInput: Encodable {
    let request_id: String
    let garment_ids: [String]
    let outfit_ids: [String]
}
struct WardrobeContextSource: Codable {
    let entity_type: String
    let id: String
    let version: Int64
    let updated_at: String?
}
struct WardrobeContext: Codable {
    let schema_version: Int
    let request_id: String
    let retrieved_at: String
    let coverage: String
    let capabilities: [String]
    let preferences: WardrobePreferences
    let garments: [WardrobeGarment]
    let outfits: [WardrobeOutfit]
    let feedback: [WardrobeFeedbackResult]
    let sources: [WardrobeContextSource]
    func validate(_ input: WardrobeContextInput, expected: [String: Int64]) throws {
        let pairs = sources.map { ($0.entity_type + ":" + $0.id, $0.version) }
        guard schema_version == 1, request_id == input.request_id, coverage == "explicit_records_only",
              garments.map(\.id) == input.garment_ids, outfits.map(\.id) == input.outfit_ids,
              feedback.map { $0.feedback.outfit_id } == input.outfit_ids,
              sources.count == 1 + garments.count + 2 * outfits.count,
              Set(pairs.map { $0.0 }).count == pairs.count, !expected.isEmpty else { throw WardrobeWriteError("Context identity or coverage does not match this editor.") }
        let versions = Dictionary(uniqueKeysWithValues: pairs)
        guard expected.allSatisfy({ versions[$0.key] == $0.value }), versions["preferences:" + preferences.id] == preferences.version else { throw WardrobeWriteError("The saved record changed. Reopen this editor before requesting assistance.") }
        guard garments.allSatisfy({ versions["garment:" + $0.id] == $0.version }), outfits.allSatisfy({ versions["outfit:" + $0.id] == $0.version }),
              zip(outfits, feedback).allSatisfy({ o, f in f.current_outfit_version == o.version && f.outfit_state == o.state && versions["feedback:" + f.feedback.id] == f.feedback.version }) else { throw WardrobeWriteError("Context records do not match their sources.") }
    }
}

enum WardrobeSettingFields {
    static func label(_ key: String) -> String {
        ["cold_threshold_c": "Cold threshold (°C)", "hot_threshold_c": "Hot threshold (°C)", "max_temp_c": "Maximum wash temperature (°C)", "temperature_c": "Wash temperature (°C)", "avoid_repeat_days": "Days before repeating", "evidence": "Label instructions", "confirmed": "I reviewed these care instructions" ][key] ?? WardrobeVocabulary.title(key)
    }
    static let preferences = ["preferred_colours", "avoided_colours", "preferred_styles", "default_occasion", "temperature_unit", "temperature_sensitivity", "cold_threshold_c", "hot_threshold_c", "layering_preference", "avoid_repeat_days", "prefer_underused_items", "variety"]
    static let care = ["wash_method", "max_temp_c", "cycle", "colour_group", "drying", "source", "evidence", "confirmed"]
    static let feedback = ["rating", "comfort_rating", "style_rating", "warmth", "comment"]
    static let preset = ["name", "temperature_c", "cycle", "drying"]
    static let lists = Set(["preferred_colours", "avoided_colours", "preferred_styles"])
    static let booleans = Set(["prefer_underused_items", "confirmed"])
    static let ranges = ["cold_threshold_c": -20...30, "hot_threshold_c": 10...45, "avoid_repeat_days": 0...30, "max_temp_c": 0...95, "temperature_c": 0...95, "rating": 1...5, "comfort_rating": 1...5, "style_rating": 1...5]
    static let choices = [
        "temperature_unit": ["celsius", "fahrenheit"], "temperature_sensitivity": ["low", "normal", "high"],
        "layering_preference": ["minimal", "moderate", "heavy"], "variety": ["low", "moderate", "high"],
        "wash_method": ["unknown", "machine", "hand", "dry_clean", "do_not_wash"],
        "cycle": ["unknown", "normal", "gentle", "delicate"], "colour_group": ["unknown", "white", "light", "dark", "separate"],
        "drying": ["unknown", "line", "flat", "tumble_low", "tumble_normal", "do_not_tumble", "professional"],
        "source": ["manual", "label"], "warmth": ["unknown", "too_cold", "comfortable", "too_warm"]
    ]
    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }
    static func patch(_ values: [String: Any], keys: [String]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, values[$0] ?? NSNull()) })
    }
    static func validate(_ values: [String: Any], keys: [String]) throws {
        for key in keys {
            guard let range = ranges[key] else { continue }
            if values[key] == nil || values[key] is NSNull {
                guard ["max_temp_c", "rating", "comfort_rating", "style_rating"].contains(key) else { throw WardrobeWriteError("Enter \(WardrobeVocabulary.title(key)).") }
                continue
            }
            guard let number = values[key] as? Int, range.contains(number) else { throw WardrobeWriteError("\(WardrobeVocabulary.title(key)) must be between \(range.lowerBound) and \(range.upperBound).") }
        }
        if let cold = values["cold_threshold_c"] as? Int, let hot = values["hot_threshold_c"] as? Int, cold >= hot { throw WardrobeWriteError("Cold threshold must be lower than hot threshold.") }
        for key in lists where keys.contains(key) {
            guard let list = values[key] as? [String], list.count <= 10, list.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 }), Set(list.map { $0.lowercased() }).count == list.count else { throw WardrobeWriteError("Use up to ten unique, short values for \(label(key)).") }
        }
        if keys.contains("wash_method") {
            let method = values["wash_method"] as? String ?? "unknown", cycle = values["cycle"] as? String ?? "unknown"
            let temp = values["max_temp_c"] as? Int
            if ["dry_clean", "do_not_wash"].contains(method), temp != nil || cycle != "unknown" { throw WardrobeWriteError("Clear wash temperature and cycle for non-wash care.") }
            if values["confirmed"] as? Bool == true {
                guard method != "unknown", !["machine", "hand"].contains(method) || temp != nil, method != "machine" || cycle != "unknown" else { throw WardrobeWriteError("Review wash method, temperature and cycle before confirming care.") }
            }
            if values["source"] as? String == "label", (values["evidence"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WardrobeWriteError("Enter readable label instructions.") }
        }
    }
}
