import Foundation

struct WardrobeSuggestQuery: Codable, Hashable {
    var day: String
    var occasion = ""
    var warmth = ""
    var requiredIDs: [String] = []
    var excludedIDs: [String] = []
    var excludedCombinations: [String] = []
    var variant = 0
    enum CodingKeys: String, CodingKey {
        case day, occasion, warmth, variant
        case requiredIDs = "required_ids", excludedIDs = "excluded_ids", excludedCombinations = "excluded_combinations"
    }
    func validate() throws {
        guard WardrobeDraftValidation.date(day) != nil, occasion.utf8.count <= 100, ["", "light", "mid", "warm"].contains(warmth),
              requiredIDs.count <= 10, excludedIDs.count <= 100, Set(requiredIDs).isDisjoint(with: excludedIDs),
              (requiredIDs + excludedIDs).allSatisfy({ WardrobeMediaPath.path(id: $0) != nil }),
              variant >= 0, variant <= 1000, excludedCombinations.count <= 100 else { throw WardrobeWriteError("Review the date and suggestion constraints.") }
    }
}
struct WardrobeSuggestedItem: Codable {
    let garmentID: String
    let role: String
    let version: Int64
    enum CodingKeys: String, CodingKey { case garmentID = "garment_id", role, version }
}
struct WardrobeSuggestion: Codable, Identifiable {
    let items: [WardrobeSuggestedItem]
    let fingerprint: String
    let reasons: [String]
    let missingRoles: [String]
    var id: String { fingerprint }
    enum CodingKeys: String, CodingKey { case items, fingerprint, reasons; case missingRoles = "missing_roles" }
}
struct WardrobeSuggestions: Codable {
    let day: String
    let algorithm: String
    let generatedAt: String
    let items: [WardrobeSuggestion]
    let noResultReason: String?
    enum CodingKeys: String, CodingKey { case day, algorithm, items; case generatedAt = "generated_at", noResultReason = "no_result_reason" }
}
struct WardrobeAnalysisQuery: Codable, Hashable { var from = ""; var to = "" }
struct WardrobeCategoryUsage: Codable, Identifiable {
    let category: String
    let garments: Int64
    let wornGarments: Int64
    let wearEvents: Int64
    var id: String { category }
    enum CodingKeys: String, CodingKey { case category, garments; case wornGarments = "worn_garments", wearEvents = "wear_events" }
}
struct WardrobeAnalysis: Codable {
    let from: String?
    let to: String?
    let outfitEvents: Int64
    let wearDays: Int64
    let garments: Int64
    let unwornGarments: Int64
    let categories: [WardrobeCategoryUsage]
    enum CodingKeys: String, CodingKey {
        case from, to, garments, categories
        case outfitEvents = "outfit_events", wearDays = "wear_days", unwornGarments = "unworn_garments"
    }
}
struct WardrobeAuditQuery: Codable, Hashable {
    let entityType: String
    let id: String
    var cursor: String?
    var limit = 50
    enum CodingKeys: String, CodingKey { case entityType = "entity_type", id, cursor, limit }
}
struct WardrobeChange: Codable, Identifiable {
    let id: Int64
    let actor: String
    let operation: String
    let before: WardrobeJSON
    let after: WardrobeJSON
    let occurredAt: String
    enum CodingKeys: String, CodingKey { case id, actor, operation, before, after; case occurredAt = "occurred_at" }
    var details: String {
        guard case .object(let old) = before, case .object(let new) = after else { return "Before: \(before.text)\nAfter: \(after.text)" }
        return Set(old.keys).union(new.keys).sorted().filter { old[$0] != new[$0] }.map {
            "\(WardrobeVocabulary.title($0)): \(old[$0]?.text ?? "Empty") → \(new[$0]?.text ?? "Empty")"
        }.joined(separator: "\n")
    }
}
// Audit values preserve integer versions instead of decoding every number through Double.
indirect enum WardrobeJSON: Codable, Equatable {
    case object([String: WardrobeJSON]), array([WardrobeJSON]), string(String), integer(Int64), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: WardrobeJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([WardrobeJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    var text: String {
        switch self {
        case .string(let v): v
        case .integer(let v): String(v)
        case .number(let v): String(v)
        case .bool(let v): v ? "Yes" : "No"
        case .null: "Empty"
        case .array(let v): v.map(\.text).joined(separator: ", ")
        case .object(let v): v.keys.sorted().map { "\(WardrobeVocabulary.title($0)): \(v[$0]!.text)" }.joined(separator: "; ")
        }
    }
}
