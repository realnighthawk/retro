import XCTest
@testable import Retro

@MainActor final class WardrobeDailyAutomationTests: XCTestCase {
    private struct Fixture: Decodable { let settings: WardrobeDailySettings; let run: WardrobeDailyRun }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "daily-automation", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var run = fields["run"] as! [String: Any]
        var choices = run["suggestions"] as! [String: Any]
        choices["generated_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        run["suggestions"] = choices
        run["expires_at"] = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
        fields["run"] = run
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func envelope(_ settings: WardrobeDailySettings, id: String) throws -> GatewayAgentResult {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "outfit-context", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let session = "mcp-fixture-" + id
        let turn = "agent:main:web:user:fixture-context:session:\(session):turn:1"
        let stamp = ISO8601DateFormatter().string(from: Date())
        fields["request_id"] = id; fields["session_id"] = session; fields["turn_id"] = turn
        fields["retrieved_at"] = stamp; fields["completed_at"] = stamp; fields["answer"] = "Narrative is not schedule evidence."
        fields["sources"] = [["tool_call_id": turn + ":act:7", "tool_name": "manage_wake", "status": "ok",
            "started_at": stamp, "completed_at": stamp, "truncated": false,
            "result": ["wake_id": "wake:agent:main:web:user:fixture-context:retro-daily-outfits", "state": settings.enabled ? "armed" : "paused",
                "objective": settings.objective, "time_zone": settings.time_zone, "daily_time": ["hour": settings.hour, "minute": settings.minute],
                "session_key": "agent:main:web:user:fixture-context", "workflow": "WakeWorkflow",
                "one_shot": false, "next_fire": ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))]]]
        return try JSONDecoder().decode(GatewayAgentResult.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testDailySnapshotDecodesExactVersionsAndSparseEngineQuery() throws {
        let f = try fixture(); try f.settings.validate()
        XCTAssertEqual(f.settings.version, 9_007_199_254_740_993)
        try f.run.validate(.init(day: f.run.day, time_zone: f.run.time_zone))
        XCTAssertEqual(f.run.query.requiredIDs, []); XCTAssertEqual(f.run.query.warmth, "")
        XCTAssertNotNil(f.run.query.expectedPreferencesVersion)
        XCTAssertEqual(f.run.delivery?.status, "claimed")
        XCTAssertThrowsError(try f.run.validate(.init(day: f.run.day, time_zone: "UTC")))
        let body = try JSONEncoder().encode(f.run.query)
        XCTAssertEqual(try JSONDecoder().decode(WardrobeSuggestQuery.self, from: body), f.run.query)
    }
    func testApplyQueryKeepsStableWakeAndVersionAndHasNoImmediateDelivery() throws {
        let settings = try fixture().settings
        let query = try settings.agentQuery(apply: true, owner: "fixture-context")
        XCTAssertEqual(try settings.agentQuery(apply: true, owner: "fixture-context"), query)
        XCTAssertLessThanOrEqual(query.utf8.count, 4000)
        XCTAssertTrue(query.contains("retro-daily-outfits")); XCTAssertTrue(query.contains("9007199254740993"))
        XCTAssertTrue(query.contains("Do not send a notification or generate outfits during setup."))
        let check = try settings.agentQuery(apply: false, owner: "fixture-context")
        XCTAssertTrue(check.contains("No changes, generation or delivery.")); XCTAssertFalse(check.contains("Objective:"))
        var invalid = settings; invalid.time_zone = "invented/zone"
        XCTAssertThrowsError(try invalid.fields())
        XCTAssertThrowsError(try settings.agentQuery(apply: true, owner: "someone:else"))
    }
    func testWakeConfirmationRequiresActualMatchingToolEvidence() throws {
        let settings = try fixture().settings
        let result = try envelope(settings, id: UUID().uuidString.lowercased())
        let receipt = try WardrobeDailyWakeReceipt(result: result, settings: settings, owner: "fixture-context")
        XCTAssertEqual(receipt.settingsVersion, settings.version); XCTAssertEqual(receipt.state, "armed")
        XCTAssertThrowsError(try WardrobeDailyWakeReceipt(result: result, settings: settings, owner: "other-owner"))
        for field in ["objective", "time_zone", "daily_time", "wake_id", "session_key", "workflow", "one_shot"] {
            var fields = try WardrobeSettingFields.object(result); var sources = fields["sources"] as! [[String: Any]]
            var raw = sources[0]["result"] as! [String: Any]; raw.removeValue(forKey: field); sources[0]["result"] = raw; fields["sources"] = sources
            let missing = try JSONDecoder().decode(GatewayAgentResult.self, from: JSONSerialization.data(withJSONObject: fields))
            XCTAssertThrowsError(try WardrobeDailyWakeReceipt(result: missing, settings: settings, owner: "fixture-context"), field)
        }
        var disabled = settings; disabled.enabled = false
        XCTAssertEqual(try WardrobeDailyWakeReceipt(result: envelope(disabled, id: UUID().uuidString.lowercased()), settings: disabled, owner: "fixture-context").state, "paused")
        var fields = try WardrobeSettingFields.object(result); var sources = fields["sources"] as! [[String: Any]]
        sources[0]["result"] = ["wake_id": "wake:agent:main:web:user:fixture-context:retro-daily-outfits", "state": "absent"]
        fields["sources"] = sources
        let absent = try JSONDecoder().decode(GatewayAgentResult.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(try WardrobeDailyWakeReceipt(result: absent, settings: disabled, owner: "fixture-context").state, "absent")
        XCTAssertThrowsError(try WardrobeDailyWakeReceipt(result: absent, settings: settings, owner: "fixture-context"))
    }
    func testDailySettingsSaveUsesExistingFrozenQueue() async throws {
        let settings = try fixture().settings
        var sent: [Data] = []
        let writes = WardrobeWrites(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            stillOwner: { true }, save: { _ in }, send: { op, body in
                XCTAssertEqual(op, "wardrobe_daily_settings_update"); sent.append(body); return .retry("offline")
            })
        var fields = WardrobeDraftValidation.edit(id: settings.id, version: settings.version); fields["patch"] = try settings.fields()
        try writes.enqueue(operation: "wardrobe_daily_settings_update", entity: settings.id, title: "Daily automation", fields: fields)
        let original = try XCTUnwrap(writes.items.first)
        _ = await writes.drain(force: true); _ = await writes.drain(force: true)
        XCTAssertEqual(sent, [original.body, original.body])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: original.body) as? [String: Any])
        XCTAssertEqual((body["expected_version"] as? NSNumber)?.int64Value, settings.version)
    }
    func testScheduleRecoveryChecksOriginalTaskWithoutCreatingAnother() async throws {
        let settings = try fixture().settings
        var calls: [String] = []
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "fixture-context",
            stillOwner: { true }, save: { _ in }, send: { call in calls.append(call.request_id); return try self.envelope(settings, id: call.request_id) })
        let id = try requests.begin(settings.agentQuery(apply: true, owner: requests.owner))
        let assistant = WardrobeAssistant(requests: requests, read: { _ in .retry("not used") })
        assistant.checkDailyWake(settings, apply: true, current: { true })
        for _ in 0..<1000 { if !assistant.running { break }; await Task.yield() }
        XCTAssertFalse(assistant.running); XCTAssertEqual(assistant.dailyWake?.state, "armed")
        XCTAssertEqual(calls, [id]); XCTAssertEqual(requests.items.count, 1)
    }
}
