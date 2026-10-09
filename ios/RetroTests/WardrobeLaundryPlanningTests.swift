import XCTest
@testable import Retro

@MainActor final class WardrobeLaundryPlanningTests: XCTestCase {
    private struct Fixture: Decodable {
        let scope: WardrobeLaundryPlanningScope
        let preview: WardrobeLaundryPreview
        let page: WardrobePage<WardrobeOutfit>
        let proposal: WardrobeLaundryPlanningProposal
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "laundry-planning", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let zone = TimeZone(secondsFromGMT: 0)!
        let today = WardrobeLaundryPlanningScope.day(Date(), zone: zone)
        let need = WardrobeLaundryPlanningScope.day(Date().addingTimeInterval(3 * 86400), zone: zone)
        fields["scope"] = ["from": today, "need_by": need, "time_zone": "UTC"]
        var preview = fields["preview"] as! [String: Any]; preview["generated_at"] = ISO8601DateFormatter().string(from: Date()); fields["preview"] = preview
        var page = fields["page"] as! [String: Any]; var plans = page["items"] as! [[String: Any]]
        for i in plans.indices { plans[i]["day"] = need }; page["items"] = plans; fields["page"] = page
        var proposal = fields["proposal"] as! [String: Any]; proposal["from"] = today; proposal["need_by"] = need
        var batches = proposal["batches"] as! [[String: Any]]; for i in batches.indices { batches[i]["day"] = today }; proposal["batches"] = batches; fields["proposal"] = proposal
        let unbound = try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: fields))
        proposal["snapshot"] = try context(unbound).snapshot; fields["proposal"] = proposal
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func context(_ f: Fixture) throws -> WardrobeLaundryPlanningContext { try .init(scope: f.scope, preview: f.preview, page: f.page, revision: 0) }
    private func changed<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var fields = try WardrobeSettingFields.object(value); edit(&fields)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func result(_ proposal: WardrobeLaundryPlanningProposal, call: GatewayAgentCall, owner: String) throws -> GatewayAgentResult {
        let session = "mcp-fixture-" + call.request_id; let now = ISO8601DateFormatter().string(from: Date())
        return .init(schema_version: 1, request_id: call.request_id, session_id: session, turn_id: "agent:main:web:user:\(owner):session:\(session):turn:1", status: .completed,
            retrieved_at: now, completed_at: now, answer: String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self), truncated: false,
            coverage: "recent_top_level_tool_calls", sources: [], pending_input: nil, retry_after_ms: nil)
    }
    func testGroupsPlansCoverageAndVersionedBatchHandoff() throws {
        let f = try fixture(); let context = try context(f)
        try f.proposal.validate(context)
        XCTAssertEqual(context.piece("g1")?.version, 9_007_199_254_740_993)
        XCTAssertEqual(context.plan("p1")?.version, 9_007_199_254_740_993)
        XCTAssertEqual(context.otherZonePlans, 1); XCTAssertEqual(context.omittedPlans, 1); XCTAssertEqual(context.planCoverage, "first_page_partial")
        XCTAssertNil(context.plan("p3")); XCTAssertNil(context.piece("g5"))
        XCTAssertThrowsError(try f.proposal.reviewedBatch(0, context: context, fresh: context, connected: nil, acceptedLimitations: false))
        let draft = try f.proposal.reviewedBatch(0, context: context, fresh: context, connected: nil, acceptedLimitations: true)
        XCTAssertEqual(draft.day, f.scope.from); XCTAssertEqual(draft.time_zone, "UTC"); XCTAssertEqual(draft.program, f.preview.program)
        XCTAssertEqual(draft.items.map(\.expected_version), [9_007_199_254_740_993, 7])
        XCTAssertNil(try draft.fields()["state"], "reviewing a proposal cannot advance progress")
        XCTAssertLessThanOrEqual(try context.modelFacts().utf8.count, 2400)
        XCTAssertLessThanOrEqual(try context.agentQuery(String(repeating: "a", count: 600)).utf8.count, 4000)
        XCTAssertEqual(try context.agentQuery("Plan these loads"), try self.context(f).agentQuery("Plan these loads"), "same sources retain the saved query identity")
        let delegated = try context.agentQuery("Keep my dinner pieces available; do not mix white and dark", focus: "Prioritize dinner")
        XCTAssertTrue(delegated.contains("Keep my dinner pieces available; do not mix white and dark")); XCTAssertTrue(delegated.contains("Prioritize dinner"))
    }
    func testRejectsInventedMixedBlockedReusedAndLatePieces() throws {
        let f = try fixture(); let c = try context(f)
        for issue in ["unknown", "mixed", "blocked", "reuse", "wrong_plan", "late", "scope", "snapshot", "external", "separate"] {
            let proposal = try changed(f.proposal) { fields in
                var batches = fields["batches"] as! [[String: Any]]
                switch issue {
                case "unknown": batches[0]["pieces"] = ["g99"]
                case "mixed": batches[0]["pieces"] = ["g1", "g3"]
                case "blocked": batches[0]["pieces"] = [f.preview.blocked[0].id]
                case "reuse": batches.append(batches[0])
                case "wrong_plan": batches[0]["plans"] = ["p2"]
                case "late": batches[0]["day"] = "9999-12-31"
                case "scope": fields["time_zone"] = "America/Los_Angeles"
                case "snapshot": fields["snapshot"] = String(repeating: "0", count: 64)
                case "external": batches[0]["context_evidence"] = ["e1"]
                default: batches[0]["group"] = f.preview.groups[2].id; batches[0]["pieces"] = ["g4", "g1"]
                }
                fields["batches"] = batches
            }
            XCTAssertThrowsError(try proposal.validate(c), issue)
        }
    }
    func testCareVersionPlanChangesAndCachedSourcesBlockHandoff() throws {
        let f = try fixture(); let old = try context(f)
        let changedPreview = try changed(f.preview) { fields in
            var groups = fields["groups"] as! [[String: Any]]; var items = groups[0]["items"] as! [[String: Any]]
            items[0]["version"] = Int64(9_007_199_254_740_994); groups[0]["items"] = items; fields["groups"] = groups
        }
        let fresh = try WardrobeLaundryPlanningContext(scope: f.scope, preview: changedPreview, page: f.page, revision: 0)
        XCTAssertNotEqual(fresh.snapshot, old.snapshot)
        XCTAssertThrowsError(try f.proposal.reviewedBatch(0, context: old, fresh: fresh, connected: nil, acceptedLimitations: true))
        let changedPage = try changed(f.page) { fields in
            var items = fields["items"] as! [[String: Any]]; items[0]["version"] = Int64(9_007_199_254_740_994); fields["items"] = items
        }
        let newPlans = try WardrobeLaundryPlanningContext(scope: f.scope, preview: f.preview, page: changedPage, revision: 0)
        XCTAssertThrowsError(try f.proposal.reviewedBatch(0, context: old, fresh: newPlans, connected: nil, acceptedLimitations: true))
        XCTAssertThrowsError(try WardrobeLaundryPlanningContext(scope: f.scope, preview: f.preview, page: f.page, revision: 0, cached: true))
        let stale = try changed(f.preview) { $0["generated_at"] = "2001-01-01T00:00:00Z" }
        XCTAssertThrowsError(try WardrobeLaundryPlanningContext(scope: f.scope, preview: stale, page: f.page, revision: 0))
    }
    func testOmittingACitationCannotBypassAnEarlierKnownOutfitNeed() throws {
        let f = try fixture()
        let page = try changed(f.page) { fields in
            var items = fields["items"] as! [[String: Any]]; items[0]["day"] = f.scope.from; fields["items"] = items
        }
        let context = try WardrobeLaundryPlanningContext(scope: f.scope, preview: f.preview, page: page, revision: 0)
        let proposal = try changed(f.proposal) { fields in
            fields["snapshot"] = context.snapshot
            var batches = fields["batches"] as! [[String: Any]]; batches[0]["plans"] = []; batches[0]["day"] = f.scope.need_by; fields["batches"] = batches
        }
        XCTAssertThrowsError(try proposal.validate(context))
    }
    func testCalendarWindowUsesDateLabelsAcrossDSTAndStopsAtLocalMidnight() throws {
        let now = try XCTUnwrap(GatewayAgentResult.date("2026-03-07T23:30:00-08:00"))
        let scope = WardrobeLaundryPlanningScope(from: "2026-03-07", need_by: "2026-03-20", time_zone: "America/Los_Angeles")
        XCTAssertNoThrow(try scope.validate(now: now))
        XCTAssertThrowsError(try WardrobeLaundryPlanningScope(from: scope.from, need_by: "2026-03-21", time_zone: scope.time_zone).validate(now: now))
        XCTAssertThrowsError(try scope.validate(now: try XCTUnwrap(GatewayAgentResult.date("2026-03-08T00:01:00-08:00"))))
        XCTAssertThrowsError(try WardrobeLaundryPlanningScope(from: scope.from, need_by: "2026-02-30", time_zone: scope.time_zone).validate(now: now))
    }
    func testConnectedProposalRecoveryReusesSavedIdentityWithoutAppleModel() async throws {
        let f = try fixture(); let context = try context(f); var calls: [GatewayAgentCall] = []
        let owner = "fixture-laundry-planning"
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: owner, stillOwner: { true }, save: { _ in }, send: { call in
            calls.append(call); return try self.result(f.proposal, call: call, owner: owner)
        })
        let original = try requests.begin(context.agentQuery("Plan these loads"))
        func run() -> WardrobeAssistantRun {
            .init(requests: requests, question: "Plan these loads", day: f.scope.need_by, remoteEnabled: true, current: { true }, read: { _ in .retry("unused") },
                waitForOwner: { _ in XCTFail("no question expected") }, progress: { _ in }, outfitContextRequest: f.scope.contextRequest, laundryRead: { context })
        }
        let first = run(); _ = try await first.readLaundryChoices(); _ = try await first.askAgent("Plan these loads")
        XCTAssertEqual(first.laundryAdvice?.proposal.batches.count, 2)
        let recovered = run(); _ = try await recovered.readLaundryChoices(); _ = try await recovered.askAgent("Plan these loads")
        XCTAssertEqual(calls.map(\.request_id), [original, original]); XCTAssertEqual(requests.items.count, 1)
    }
    func testLateLaundryReadCannotBeAppliedAfterSourceOrOwnerChanges() async throws {
        let f = try fixture(); let context = try context(f); var current = true
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "fixture-laundry-planning", stillOwner: { true }, save: { _ in }, send: { _ in XCTFail("no delegation"); throw URLError(.unsupportedURL) })
        let run = WardrobeAssistantRun(requests: requests, question: "Plan", day: f.scope.need_by, remoteEnabled: false, current: { current }, read: { _ in .retry("unused") }, waitForOwner: { _ in }, progress: { _ in },
            outfitContextRequest: f.scope.contextRequest, laundryRead: { current = false; return context })
        do { _ = try await run.readLaundryChoices(); XCTFail("late facts must be fenced") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(run.laundryFacts); XCTAssertNil(run.laundryAdvice); XCTAssertTrue(requests.items.isEmpty)
        current = true
        let owner = "fixture-laundry-planning"
        let lateRequests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: owner, stillOwner: { true }, save: { _ in }, send: { call in
            current = false; return try self.result(f.proposal, call: call, owner: owner)
        })
        let lateRun = WardrobeAssistantRun(requests: lateRequests, question: "Plan", day: f.scope.need_by, remoteEnabled: true, current: { current }, read: { _ in .retry("unused") }, waitForOwner: { _ in }, progress: { _ in }, outfitContextRequest: f.scope.contextRequest, laundryRead: { context })
        _ = try await lateRun.readLaundryChoices()
        do { _ = try await lateRun.askAgent("Plan"); XCTFail("late proposals must be fenced") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(lateRun.laundryAdvice); XCTAssertEqual(lateRequests.items.count, 1, "the saved task remains recoverable")
    }
    func testReviewedBatchSaveRetainsExactVersionAndFrozenIntentAfterLostReply() async throws {
        let f = try fixture(); let context = try context(f)
        let draft = try f.proposal.reviewedBatch(0, context: context, fresh: context, connected: nil, acceptedLimitations: true)
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "writes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { _, _ in .retry("lost reply") }
        let id = UUID().uuidString.lowercased(); var fields = try draft.fields(); fields["id"] = id
        try queue.enqueue(operation: "laundry_create", entity: id, title: draft.name, fields: fields)
        let original = try XCTUnwrap(queue.items.first); _ = await queue.drain()
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { operation, body in
            XCTAssertEqual(operation, "laundry_create"); XCTAssertEqual(body, original.body); return .ok(true)
        }
        XCTAssertEqual(try WardrobeLaundryDraft(request: XCTUnwrap(restored.items.first)).items[0].expected_version, 9_007_199_254_740_993)
        let saved = await restored.drain(force: true); XCTAssertTrue(saved)
    }
}
