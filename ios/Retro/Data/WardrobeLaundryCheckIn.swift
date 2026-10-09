import Foundation

struct WardrobeLaundryReminder: Codable, Equatable {
    var wear_days: Int?
    var interval_days: Int?
    func validate() throws {
        guard wear_days != nil || interval_days != nil,
              wear_days.map({ (1...100).contains($0) }) ?? true,
              interval_days.map({ (1...365).contains($0) }) ?? true else { throw WardrobeWriteError("Choose a wear-day threshold from 1–100 and/or a calendar interval from 1–365 days.") }
    }
    var summary: String { [wear_days.map { "\($0) distinct wear days" }, interval_days.map { "\($0) calendar days" }].compactMap { $0 }.joined(separator: " or ") }
}
struct WardrobeLaundryCleaningSource: Codable {
    let id: String
    let version: Int64
    let completed_at: String
}
struct WardrobeLaundryWearStats: Codable {
    let wear_days: Int64
    let wear_events: Int64
    let same_day_wear_days: Int64
    let same_day_wear_events: Int64
}
struct WardrobeLaundryCheckInItem: Codable, Identifiable {
    let garment_id: String
    let garment_version: Int64
    let name: String
    let availability: String
    let archived_at: String?
    let reminder: WardrobeLaundryReminder?
    let last_cleaning: WardrobeLaundryCleaningSource?
    let wears_since_cleaning: WardrobeLaundryWearStats?
    let days_since_cleaning: Int?
    let due: Bool
    let due_reasons: [String]
    var id: String { garment_id }
    var status: String {
        if archived_at != nil { return "Archived — reminder paused" }
        if availability == "washing" { return "Washing or drying — reminder paused" }
        if reminder == nil { return "Reminders off" }
        if last_cleaning == nil { return "Awaiting a confirmed cleaning baseline" }
        return due ? "Care review due" : "Below your review thresholds"
    }
    func validate(generatedAt: Date, zone: TimeZone) throws {
        guard WardrobeMediaPath.path(id: id) != nil, garment_version > 0, (1...100).contains(name.utf8.count), WardrobeVocabulary.availability.contains(availability),
              archived_at == nil || archived_at.flatMap(GatewayAgentResult.date) != nil else { throw WardrobeWriteError("Refresh the garment check-in sources.") }
        try reminder?.validate()
        if let cleaning = last_cleaning {
            guard WardrobeMediaPath.path(id: cleaning.id) != nil, cleaning.version > 0, let completed = GatewayAgentResult.date(cleaning.completed_at), completed <= generatedAt,
                  let wears = wears_since_cleaning, let days = days_since_cleaning,
                  wears.wear_days >= 0, wears.wear_events >= wears.wear_days, wears.same_day_wear_days >= 0, wears.same_day_wear_events >= wears.same_day_wear_days else { throw WardrobeWriteError("The cleaning baseline or wear totals need review.") }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            var dates = Calendar(identifier: .gregorian); dates.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = dates.date(from: calendar.dateComponents([.year, .month, .day], from: completed))
            let end = dates.date(from: calendar.dateComponents([.year, .month, .day], from: generatedAt))
            guard days >= 0, let start, let end, dates.dateComponents([.day], from: start, to: end).day == days else { throw WardrobeWriteError("Refresh the calendar-day check-in for this time zone.") }
        } else {
            guard wears_since_cleaning == nil, days_since_cleaning == nil else { throw WardrobeWriteError("A missing cleaning baseline cannot have a known wear count.") }
        }
        var expected: [String] = []
        if archived_at == nil, availability != "washing", let reminder, last_cleaning != nil, let wears = wears_since_cleaning, let days = days_since_cleaning {
            if let threshold = reminder.wear_days, wears.wear_days >= Int64(threshold) { expected.append("wear_threshold") }
            if let interval = reminder.interval_days, days >= interval { expected.append("interval_threshold") }
        }
        guard due_reasons == expected, due == !expected.isEmpty else { throw WardrobeWriteError("The reminder doesn't match the supplied facts. Refresh before reviewing.") }
    }
}
struct WardrobeLaundryCheckInQuery: Codable, Equatable { var time_zone = TimeZone.current.identifier; var garment_id = "" }
struct WardrobeLaundryCheckIn: Codable {
    let generated_at: String
    let time_zone: String
    let coverage: String
    let inventory_count: Int
    let items: [WardrobeLaundryCheckInItem]
    func validate(_ query: WardrobeLaundryCheckInQuery, cached: Bool = false) throws {
        guard time_zone == query.time_zone, let zone = TimeZone(identifier: time_zone), let generated = GatewayAgentResult.date(generated_at), generated <= Date().addingTimeInterval(300), cached || abs(generated.timeIntervalSinceNow) <= 300,
              (0...2000).contains(inventory_count), items.count == inventory_count, Set(items.map(\.id)).count == items.count else { throw WardrobeWriteError("Check-in coverage, time zone or freshness changed. Refresh the list.") }
        if query.garment_id.isEmpty {
            guard coverage == "active_garments_only", items.allSatisfy({ $0.archived_at == nil }) else { throw WardrobeWriteError("The check-in is not a complete active-wardrobe view.") }
        } else {
            guard coverage == "explicit_garment", items.count == 1, items[0].id == query.garment_id else { throw WardrobeWriteError("The check-in belongs to another garment.") }
        }
        for item in items { try item.validate(generatedAt: generated, zone: zone) }
    }
}
struct WardrobeLaundryReminderDraft: Equatable {
    var enabled = false
    var wearEnabled = true
    var wearDays = 3
    var intervalEnabled = false
    var intervalDays = 7
    init(_ reminder: WardrobeLaundryReminder? = nil) {
        if let reminder { enabled = true; wearEnabled = reminder.wear_days != nil; wearDays = reminder.wear_days ?? 3; intervalEnabled = reminder.interval_days != nil; intervalDays = reminder.interval_days ?? 7 }
    }
    func patch() throws -> [String: Any] {
        if !enabled { return ["laundry_reminder": NSNull()] }
        let reminder = WardrobeLaundryReminder(wear_days: wearEnabled ? wearDays : nil, interval_days: intervalEnabled ? intervalDays : nil)
        try reminder.validate()
        return ["laundry_reminder": try WardrobeSettingFields.object(reminder)]
    }
}
