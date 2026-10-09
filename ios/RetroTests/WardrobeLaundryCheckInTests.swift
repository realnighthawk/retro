import XCTest
@testable import Retro

@MainActor final class WardrobeLaundryCheckInTests: XCTestCase {
    private func fixture() throws -> WardrobeLaundryCheckIn {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "laundry-check-in", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let now = Date(); let formatter = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cleaned = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))
        fields["generated_at"] = formatter.string(from: now)
        var items = fields["items"] as! [[String: Any]]; var baseline = items[0]["last_cleaning"] as! [String: Any]
        baseline["completed_at"] = formatter.string(from: cleaned); items[0]["last_cleaning"] = baseline; fields["items"] = items
        return try JSONDecoder().decode(WardrobeLaundryCheckIn.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func changed(_ value: WardrobeLaundryCheckIn, _ update: (inout [String: Any]) -> Void) throws -> WardrobeLaundryCheckIn {
        var fields = try WardrobeSettingFields.object(value); update(&fields)
        return try JSONDecoder().decode(WardrobeLaundryCheckIn.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testKnownCountsAndUnknownBaselineKeepExactSourcesAndScope() throws {
        let value = try fixture(); let query = WardrobeLaundryCheckInQuery(time_zone: "UTC")
        XCTAssertNoThrow(try value.validate(query))
        XCTAssertEqual(value.items[0].garment_version, 9_007_199_254_740_993)
        XCTAssertEqual(value.items[0].last_cleaning?.version, 9_007_199_254_740_993)
        XCTAssertEqual(value.items[0].wears_since_cleaning?.wear_days, 3)
        XCTAssertEqual(value.items[0].wears_since_cleaning?.same_day_wear_events, 2)
        XCTAssertNil(value.items[1].wears_since_cleaning); XCTAssertFalse(value.items[1].due)
        XCTAssertEqual(value.items[1].status, "Awaiting a confirmed cleaning baseline")
        XCTAssertThrowsError(try value.validate(.init(time_zone: "America/Los_Angeles")))
        XCTAssertThrowsError(try value.validate(.init(time_zone: "UTC", garment_id: value.items[0].id)))
        let duplicated = try changed(value) { $0["items"] = [try! WardrobeSettingFields.object(value.items[0]), try! WardrobeSettingFields.object(value.items[0])] }
        XCTAssertThrowsError(try duplicated.validate(query))
    }
    func testReminderFactsCannotBeForgedAndCachedAgeIsMeasuredAtItsSnapshot() throws {
        let value = try fixture(); let query = WardrobeLaundryCheckInQuery(time_zone: "UTC")
        let forged = try changed(value) { fields in
            var items = fields["items"] as! [[String: Any]]; var wears = items[0]["wears_since_cleaning"] as! [String: Any]
            wears["wear_days"] = 2; items[0]["wears_since_cleaning"] = wears; fields["items"] = items
        }
        XCTAssertThrowsError(try forged.validate(query), "Ambiguous same-day records cannot make up a missing definite wear day.")
        let invented = try changed(value) { fields in
            var items = fields["items"] as! [[String: Any]]; items[1]["days_since_cleaning"] = 0; fields["items"] = items
        }
        XCTAssertThrowsError(try invented.validate(query))
        let stale = try changed(value) { fields in
            fields["generated_at"] = "2026-01-10T12:00:00Z"
            var items = fields["items"] as! [[String: Any]]; var source = items[0]["last_cleaning"] as! [String: Any]
            source["completed_at"] = "2026-01-07T12:00:00Z"; items[0]["last_cleaning"] = source; fields["items"] = items
        }
        XCTAssertNoThrow(try stale.validate(query, cached: true))
        XCTAssertThrowsError(try stale.validate(query))
        let washing = try changed(value) { fields in
            var items = fields["items"] as! [[String: Any]]; items[0]["availability"] = "washing"; items[0]["due"] = false; items[0]["due_reasons"] = []; fields["items"] = items
        }
        XCTAssertNoThrow(try washing.validate(query)); XCTAssertEqual(washing.items[0].status, "Washing or drying — reminder paused")
    }
    func testOptInRequiresThresholdsAndOffIsAnExplicitClearWithoutAvailabilityChanges() throws {
        var draft = WardrobeLaundryReminderDraft()
        XCTAssertTrue(try draft.patch()["laundry_reminder"] is NSNull)
        draft.enabled = true; draft.wearEnabled = false
        XCTAssertThrowsError(try draft.patch())
        draft.intervalEnabled = true; draft.intervalDays = 7
        let patch = try draft.patch(); let reminder = try XCTUnwrap(patch["laundry_reminder"] as? [String: Any])
        XCTAssertEqual(reminder["interval_days"] as? Int, 7); XCTAssertNil(reminder["wear_days"])
        XCTAssertNil(patch["availability"]); XCTAssertNil(patch["care"])
        draft.intervalDays = 366; XCTAssertThrowsError(try draft.patch())
    }
    func testReminderSavesFreezeReviewedVersionAndReplayAfterLostAcknowledgement() async throws {
        let value = try fixture(); let item = value.items[0]
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "writes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let writes = WardrobeWrites(file: file, stillOwner: { true }) { _, _ in .retry("lost acknowledgement") }
        var draft = WardrobeLaundryReminderDraft(item.reminder); draft.enabled = false
        var fields = WardrobeDraftValidation.edit(id: item.id, version: item.garment_version); fields["patch"] = try draft.patch()
        try writes.enqueue(operation: "garments_update", entity: item.id, title: item.name, fields: fields)
        let original = try XCTUnwrap(writes.items.first); _ = await writes.drain()
        let reopened = WardrobeWrites(file: file, stillOwner: { true }) { operation, body in
            XCTAssertEqual(operation, "garments_update"); XCTAssertEqual(body, original.body)
            let object = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            XCTAssertEqual((object["expected_version"] as? NSNumber)?.int64Value, 9_007_199_254_740_993)
            XCTAssertTrue((object["patch"] as? [String: Any])?["laundry_reminder"] is NSNull)
            return .ok(true)
        }
        let acknowledged = await reopened.drain(force: true); XCTAssertTrue(acknowledged)
        XCTAssertTrue(reopened.items.isEmpty)
    }
}
