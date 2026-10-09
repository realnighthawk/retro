import Foundation
import CryptoKit

struct WardrobeSuggestQuery: Codable, Hashable {
    var day: String
    var occasion = ""
    var warmth = ""
    var requiredIDs: [String] = []
    var excludedIDs: [String] = []
    var excludedCombinations: [String] = []
    var variant = 0
    var expectedPreferencesVersion: Int64? = nil
    var swapRole: String? = nil
    enum CodingKeys: String, CodingKey {
        case day, occasion, warmth, variant
        case requiredIDs = "required_ids", excludedIDs = "excluded_ids", excludedCombinations = "excluded_combinations"
        case expectedPreferencesVersion = "expected_preferences_version"
        case swapRole = "swap_role"
    }
    func validate() throws {
        guard WardrobeDraftValidation.date(day) != nil, occasion.utf8.count <= 100, ["", "light", "mid", "warm"].contains(warmth),
              requiredIDs.count <= 10, excludedIDs.count <= 100,
              Set(requiredIDs).count == requiredIDs.count, Set(excludedIDs).count == excludedIDs.count, Set(requiredIDs).isDisjoint(with: excludedIDs),
              (requiredIDs + excludedIDs).allSatisfy({ WardrobeMediaPath.path(id: $0) != nil }),
              variant >= 0, variant <= 1000, excludedCombinations.count <= 100,
              excludedCombinations.allSatisfy({ $0.count == 64 && $0.allSatisfy({ "0123456789abcdef".contains($0) }) }),
              expectedPreferencesVersion == nil || expectedPreferencesVersion! > 0,
              swapRole == nil || ["base", "bottom", "one_piece", "mid", "outer", "feet", "accessory"].contains(swapRole!) else { throw WardrobeWriteError("Review the date and suggestion constraints.") }
    }
}
extension WardrobeSuggestQuery {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(day: try c.decode(String.self, forKey: .day),
            occasion: try c.decodeIfPresent(String.self, forKey: .occasion) ?? "",
            warmth: try c.decodeIfPresent(String.self, forKey: .warmth) ?? "",
            requiredIDs: try c.decodeIfPresent([String].self, forKey: .requiredIDs) ?? [],
            excludedIDs: try c.decodeIfPresent([String].self, forKey: .excludedIDs) ?? [],
            excludedCombinations: try c.decodeIfPresent([String].self, forKey: .excludedCombinations) ?? [],
            variant: try c.decodeIfPresent(Int.self, forKey: .variant) ?? 0,
            expectedPreferencesVersion: try c.decodeIfPresent(Int64.self, forKey: .expectedPreferencesVersion),
            swapRole: try c.decodeIfPresent(String.self, forKey: .swapRole))
    }
}
struct WardrobeSuggestedItem: Codable {
    let garmentID: String
    let role: String
    let version: Int64
    var name: String? = nil
    enum CodingKeys: String, CodingKey { case garmentID = "garment_id", role, version, name }
}
struct WardrobeSuggestion: Codable, Identifiable {
    let items: [WardrobeSuggestedItem]
    let fingerprint: String
    let reasons: [String]
    let missingRoles: [String]
    var score: Int? = nil
    var id: String { fingerprint }
    enum CodingKeys: String, CodingKey { case items, fingerprint, reasons, score; case missingRoles = "missing_roles" }
    var calculatedFingerprint: String {
        SHA256.hash(data: Data(items.map(\.garmentID).sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func swapping(_ piece: WardrobeSelection, query: WardrobeSuggestQuery, locked: Set<String> = []) throws -> WardrobeSuggestQuery {
        try query.validate()
        guard Set(query.requiredIDs + Array(locked)).isSubset(of: Set(items.map(\.garmentID))), fingerprint == calculatedFingerprint,
              Set(query.excludedIDs).isDisjoint(with: items.map(\.garmentID)), !query.excludedCombinations.contains(fingerprint),
              items.contains(where: { $0.garmentID == piece.id && $0.role == piece.role }), !locked.contains(piece.id), !query.requiredIDs.contains(piece.id) else { throw WardrobeWriteError("Review the locked pieces and unlock this piece before swapping it.") }
        var next = query
        next.requiredIDs = items.filter { $0.garmentID != piece.id }.map(\.garmentID)
        next.excludedIDs = Array(Set(query.excludedIDs + [piece.id])).sorted()
        next.variant = 0
        next.swapRole = piece.role
        try next.validate(); return next
    }
}
struct WardrobeSuggestions: Codable {
    let day: String
    let algorithm: String
    let generatedAt: String
    let items: [WardrobeSuggestion]
    let noResultReason: String?
    var effectiveOccasion: String? = nil
    var preferencesSource: WardrobeContextSource? = nil
    var feedbackSamples: Int? = nil
    var feedbackCoverage: String? = nil
    var warnings: [String]? = nil
    enum CodingKeys: String, CodingKey {
        case day, algorithm, items, warnings
        case generatedAt = "generated_at", noResultReason = "no_result_reason", effectiveOccasion = "effective_occasion"
        case preferencesSource = "preferences_source", feedbackSamples = "feedback_samples", feedbackCoverage = "feedback_coverage"
    }
    func reviewQuery(_ input: WardrobeSuggestQuery, cached: Bool = false) throws -> WardrobeSuggestQuery {
        try input.validate()
        guard day == input.day, ["rules-v1", "rules-v2"].contains(algorithm), items.count <= 3,
              input.expectedPreferencesVersion == nil || algorithm == "rules-v2",
              (noResultReason?.utf8.count ?? 0) <= 1000,
              Set(items.map(\.id)).count == items.count, let time = GatewayAgentResult.date(generatedAt),
              time <= Date().addingTimeInterval(300), cached || abs(time.timeIntervalSinceNow) <= 300 else {
            throw WardrobeWriteError("Suggestion identity, freshness or coverage changed. Generate again.")
        }
        for option in items {
            guard (1...10).contains(option.items.count), option.fingerprint == option.calculatedFingerprint,
                  Set(option.items.map(\.garmentID)).count == option.items.count,
                  Set(option.items.map(\.role)).count == option.items.count,
                  option.items.allSatisfy({ WardrobeMediaPath.path(id: $0.garmentID) != nil && WardrobeDraftValidation.roles.contains($0.role) && $0.version > 0 && ($0.name?.utf8.count ?? 0) <= 100 }),
                  Set(input.requiredIDs).isSubset(of: Set(option.items.map(\.garmentID))), Set(input.excludedIDs).isDisjoint(with: option.items.map(\.garmentID)),
                  !input.excludedCombinations.contains(option.fingerprint), input.swapRole == nil || option.items.contains(where: { $0.role == input.swapRole }), option.reasons.count <= 60,
                  option.reasons.allSatisfy({ $0.utf8.count <= 500 }), option.missingRoles.count <= 4,
                  Set(option.missingRoles).count == option.missingRoles.count, Set(option.missingRoles).isDisjoint(with: option.items.map(\.role)),
                  option.missingRoles.allSatisfy({ ["base", "bottom", "one_piece", "feet"].contains($0) }) else {
                throw WardrobeWriteError("A suggestion does not match its pieces or the requested constraints.")
            }
        }
        var query = input
        if algorithm == "rules-v2" {
            guard let source = preferencesSource, source.entity_type == "preferences", source.version > 0,
                  WardrobeMediaPath.path(id: source.id) != nil, let occasion = effectiveOccasion, occasion.utf8.count <= 100,
                  let updated = source.updated_at, let sourceTime = GatewayAgentResult.date(updated), sourceTime <= time.addingTimeInterval(300),
                  input.occasion.isEmpty || input.occasion == occasion,
                  input.expectedPreferencesVersion == nil || input.expectedPreferencesVersion == source.version,
                  let count = feedbackSamples, (0...2000).contains(count),
                  feedbackCoverage == "latest_2000_version_matched_rated_wears_through_requested_day",
                  let warnings, warnings.count <= 8, warnings.allSatisfy({ $0.utf8.count <= 500 }),
                  items.allSatisfy({ $0.score != nil && (-1000...1000).contains($0.score!) && $0.items.allSatisfy({ $0.name?.isEmpty == false }) }) else { throw WardrobeWriteError("Preference or feedback ranking evidence is incomplete.") }
            query.occasion = occasion; query.expectedPreferencesVersion = source.version
        }
        return query
    }
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
