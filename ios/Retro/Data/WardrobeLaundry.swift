import Foundation

struct WardrobeLaundryProgram: Codable, Equatable {
    var wash_method = "machine"
    var temperature_c: Int? = 20
    var cycle = "gentle"
    var drying = "line"
    var summary: String { [WardrobeVocabulary.title(wash_method), temperature_c.map { "\($0) °C" }, cycle == "unknown" ? nil : WardrobeVocabulary.title(cycle), WardrobeVocabulary.title(drying)].compactMap { $0 }.joined(separator: " · ") }
    func validate() throws {
        if wash_method == "dry_clean", temperature_c == nil, cycle == "unknown", drying == "professional" { return }
        guard ["machine", "hand"].contains(wash_method), let temperature_c, (0...95).contains(temperature_c),
              ["line", "flat", "tumble_low", "tumble_normal"].contains(drying),
              wash_method == "machine" ? ["normal", "gentle", "delicate"].contains(cycle) : cycle == "unknown" else { throw WardrobeWriteError("Choose a wash method, explicit temperature, applicable cycle and drying method.") }
    }
    mutating func method(_ value: String) {
        wash_method = value
        temperature_c = value == "dry_clean" ? nil : temperature_c ?? 20
        cycle = value == "machine" ? "gentle" : "unknown"
        drying = value == "dry_clean" ? "professional" : "line"
    }
}
struct WardrobeLaundrySelection: Codable, Equatable { let garment_id: String; let expected_version: Int64 }
struct WardrobeLaundryCandidate: Codable, Identifiable {
    let garment_id: String
    let version: Int64
    let name: String
    var id: String { garment_id }
    var selection: WardrobeLaundrySelection { .init(garment_id: garment_id, expected_version: version) }
    func validate() throws { guard WardrobeMediaPath.path(id: id) != nil, version > 0, (1...100).contains(name.utf8.count) else { throw WardrobeWriteError("Refresh the laundry garment sources.") } }
}
struct WardrobeLaundryGroup: Codable, Identifiable { let id: String; let colour_group: String; let items: [WardrobeLaundryCandidate] }
struct WardrobeLaundryBlocked: Codable, Identifiable {
    let garment_id: String; let version: Int64; let name: String; let reason: String
    var id: String { garment_id }
}
struct WardrobeLaundryPreviewInput: Codable { let program: WardrobeLaundryProgram }
struct WardrobeLaundryPreview: Codable {
    let program: WardrobeLaundryProgram
    let generated_at: String
    let coverage: String
    let inventory_count: Int
    let groups: [WardrobeLaundryGroup]
    let blocked: [WardrobeLaundryBlocked]
    func validate(_ input: WardrobeLaundryProgram, cached: Bool = false) throws {
        try program.validate()
        let candidates = groups.flatMap(\.items)
        let ids = candidates.map(\.id) + blocked.map(\.id)
        guard program == input, coverage == "active_needs_wash_only", (0...2000).contains(inventory_count), ids.count == inventory_count,
              Set(ids).count == ids.count, Set(groups.map(\.id)).count == groups.count,
              let stamp = GatewayAgentResult.date(generated_at), stamp <= Date().addingTimeInterval(300), cached || abs(stamp.timeIntervalSinceNow) <= 300 else { throw WardrobeWriteError("Laundry preview scope, coverage or freshness changed. Refresh the groups.") }
        for group in groups {
            guard !group.items.isEmpty, ["white", "light", "dark", "separate"].contains(group.colour_group),
                  group.colour_group == "separate" ? group.items.count == 1 && group.id == "separate:" + group.items[0].id : group.id == group.colour_group else { throw WardrobeWriteError("The laundry colour groups need review.") }
        }
        for item in candidates { try item.validate() }
        for item in blocked {
            try WardrobeLaundryCandidate(garment_id: item.id, version: item.version, name: item.name).validate()
            guard (1...1000).contains(item.reason.utf8.count) else { throw WardrobeWriteError("A blocked laundry item has no review reason.") }
        }
    }
    func selections(_ ids: Set<String>) throws -> [WardrobeLaundrySelection] {
        try validate(program)
        guard (1...30).contains(ids.count), let group = groups.first(where: { ids.isSubset(of: Set($0.items.map(\.id))) }) else { throw WardrobeWriteError("Choose 1–30 garments from one compatible colour group. Wash-separately items need their own load.") }
        return group.items.filter { ids.contains($0.id) }.map(\.selection)
    }
}
struct WardrobeLaundryItem: Codable, Identifiable {
    let garment_id: String; let expected_version: Int64; let snapshot: WardrobeGarment
    var id: String { garment_id }
    var selection: WardrobeLaundrySelection { .init(garment_id: garment_id, expected_version: expected_version) }
}
struct WardrobeLaundryLoad: Codable, Identifiable {
    let id: String; let version: Int64; let name: String; let day: String; let time_zone: String; let state: String
    let program: WardrobeLaundryProgram; let items: [WardrobeLaundryItem]
    let started_at: String?; let washed_at: String?; let completed_at: String?; let cancelled_at: String?
    let created_at: String; let updated_at: String
    static let states = ["planned", "washing", "drying", "completed", "cancelled"]
    var stateTitle: String { program.wash_method == "dry_clean" && state == "washing" ? "With cleaner" : WardrobeVocabulary.title(state) }
    var progressTitle: String {
        switch state {
        case "planned": program.wash_method == "dry_clean" ? "Confirm sent to cleaner" : "Confirm washing started"
        case "washing": program.wash_method == "dry_clean" ? "Confirm returned clean" : "Confirm wash finished; begin drying"
        default: "Confirm dry and ready"
        }
    }
    func validate() throws {
        _ = try WardrobeLaundryDraft(self).fields()
        guard WardrobeMediaPath.path(id: id) != nil, version > 0, Self.states.contains(state),
              GatewayAgentResult.date(created_at) != nil, GatewayAgentResult.date(updated_at) != nil,
              items.allSatisfy({ $0.snapshot.id == $0.id && $0.snapshot.version > 0 && $0.expected_version >= $0.snapshot.version && $0.snapshot.availability == "needs_wash" && $0.snapshot.care?.confirmed == true }),
              state != "drying" || program.wash_method != "dry_clean" else { throw WardrobeWriteError("The laundry record has invalid sources or progress.") }
        let stamps = [started_at, washed_at, completed_at, cancelled_at].compactMap { $0 }
        let dates = stamps.compactMap(GatewayAgentResult.date)
        guard dates.count == stamps.count, dates == dates.sorted(),
              state == "planned" ? stamps.isEmpty : state == "cancelled" ? cancelled_at != nil && completed_at == nil : started_at != nil && cancelled_at == nil,
              state != "washing" || washed_at == nil && completed_at == nil,
              state != "drying" || washed_at != nil && completed_at == nil,
              state != "completed" || washed_at != nil && completed_at != nil else { throw WardrobeWriteError("Refresh the dated laundry progress.") }
    }
}
struct WardrobeLaundryResult: Codable { let load: WardrobeLaundryLoad }
struct WardrobeLaundryQuery: Codable, Equatable { var state = ""; var garment_id = ""; var limit = 20; var cursor: String? }
struct WardrobeLaundryDraft: Codable, Equatable {
    static let keys = ["name", "day", "time_zone", "program", "items"]
    var name = "Cold wash"
    var day = WardrobeVocabulary.dayKey(Date())
    var time_zone = TimeZone.current.identifier
    var program = WardrobeLaundryProgram()
    var items: [WardrobeLaundrySelection] = []
    init(_ load: WardrobeLaundryLoad? = nil) {
        if let load { name = load.name; day = load.day; time_zone = load.time_zone; program = load.program; items = load.items.map(\.selection) }
    }
    init(request: WardrobePending, current: WardrobeLaundryLoad? = nil) throws {
        guard ["laundry_create", "laundry_update"].contains(request.operation),
              let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any], body["id"] as? String == request.entity, body["idempotency_key"] as? String == request.id else { throw WardrobeWriteError("The original laundry save could not be opened.") }
        var fields = try WardrobeSettingFields.object(WardrobeLaundryDraft(current))
        let requested: [String: Any]
        if request.operation == "laundry_create" {
            guard Set(Self.keys).isSubset(of: Set(body.keys)) else { throw WardrobeWriteError("The original laundry programme, date or pieces are missing. Keep the stored request for review.") }
            requested = body
        } else {
            guard current != nil, let patch = body["patch"] as? [String: Any], !patch.isEmpty, Set(patch.keys).isSubset(of: Set(Self.keys)) else { throw WardrobeWriteError("Read the current planned load and original field changes before recovery.") }
            requested = patch
        }
        for key in Self.keys { if let value = requested[key] { fields[key] = value } }
        self = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: fields))
        _ = try self.fields()
    }
    func fields() throws -> [String: Any] {
        try program.validate()
        guard (1...100).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count), WardrobeDraftValidation.date(day) != nil,
              time_zone.utf8.count <= 100, TimeZone(identifier: time_zone) != nil, (1...30).contains(items.count), Set(items.map(\.garment_id)).count == items.count,
              items.allSatisfy({ WardrobeMediaPath.path(id: $0.garment_id) != nil && $0.expected_version > 0 }) else { throw WardrobeWriteError("Name the load, choose its date/time zone and review 1–30 garment versions.") }
        var fields = try WardrobeSettingFields.object(self)
        fields["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return fields
    }
}
