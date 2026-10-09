import XCTest
@testable import Retro

@MainActor final class WardrobeOutfitContextTests: XCTestCase {
    private var request: WardrobeOutfitContextRequest { .init(day: "2026-10-09", timeZone: "America/Los_Angeles", location: "San Francisco") }
    private func fixture(id: String = "88888888-8888-4888-8888-888888888888") throws -> GatewayAgentResult {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "outfit-context", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let old = fields["turn_id"] as! String
        let session = "mcp-fixture-" + id; let turn = "agent:main:web:user:fixture-context:session:\(session):turn:1"
        let formatter = ISO8601DateFormatter(); let now = formatter.string(from: Date())
        fields["request_id"] = id; fields["session_id"] = session; fields["turn_id"] = turn
        fields["retrieved_at"] = now; fields["completed_at"] = now
        fields["answer"] = (fields["answer"] as! String).replacingOccurrences(of: old, with: turn)
        var sources = fields["sources"] as! [[String: Any]]
        for index in sources.indices {
            sources[index]["tool_call_id"] = (sources[index]["tool_call_id"] as! String).replacingOccurrences(of: old, with: turn)
            sources[index]["started_at"] = formatter.string(from: Date().addingTimeInterval(-2))
            sources[index]["completed_at"] = formatter.string(from: Date().addingTimeInterval(-1))
        }
        var weather = sources[0]["result"] as! [String: Any]; weather["issued_at"] = now; sources[0]["result"] = weather
        fields["sources"] = sources
        return try JSONDecoder().decode(GatewayAgentResult.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func changed(_ result: GatewayAgentResult, _ edit: (inout [String: Any]) -> Void) throws -> GatewayAgentResult {
        var fields = try WardrobeSettingFields.object(result); edit(&fields)
        return try JSONDecoder().decode(GatewayAgentResult.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func facts(_ result: GatewayAgentResult) throws -> WardrobeOutfitContext { try WardrobeOutfitContext(result: result, request: request, owner: "fixture-context") }

    func testLiteralProviderFactsHaveNativeUnitsTimezoneCoverageAndExpiry() throws {
        let result = try fixture(); let facts = try facts(result)
        XCTAssertEqual(facts.weather?.lowC, 10); XCTAssertEqual(facts.weather?.highC, 20)
        XCTAssertEqual(facts.calendar.first?.title, "Dinner with friends"); XCTAssertEqual(facts.travel.first?.title, "Flight to Seattle")
        XCTAssertEqual(facts.weather?.source.connection, "weather"); XCTAssertEqual(facts.aliases, ["w1", "e1", "t1"])
        XCTAssertEqual(facts.coverage.map(\.status), ["available", "available", "available"])
        XCTAssertThrowsError(try facts.validate(request, now: facts.expiresAt))
        let model = try facts.modelFacts(); XCTAssertLessThanOrEqual(model.utf8.count, 2000)
        XCTAssertFalse(model.contains(result.turn_id)); XCTAssertTrue(model.contains("not complete schedules"))
        XCTAssertEqual(result.sources?[0].result?["provider_version"], .integer(9_007_199_254_740_993))
        XCTAssertLessThanOrEqual(try request.agentQuery().utf8.count, 4000)
    }
    func testContextScopeProducesTheSameSavedQuery() throws {
        let original = try request.agentQuery()
        for _ in 0..<20 {
            let restored = try JSONDecoder().decode(WardrobeOutfitContextRequest.self, from: JSONEncoder().encode(request))
            XCTAssertEqual(try restored.agentQuery(), original, "scope serialization must retain the immutable query used for task recovery")
        }
    }
    func testForgedMissingStaleOrUnsupportedProviderFactsStayUnavailable() throws {
        for failure in ["missing_source", "inline", "wrong_place", "unit", "stale", "missing_identity", "truncated"] {
            let result = try changed(fixture()) { fields in
                var sources = fields["sources"] as! [[String: Any]]; var weather = sources[0]["result"] as! [String: Any]
                var manifest = try! JSONSerialization.jsonObject(with: Data((fields["answer"] as! String).utf8)) as! [String: Any]
                var section = manifest["weather"] as! [String: Any]; var items = section["items"] as! [[String: Any]]
                var pointers = items[0]["fields"] as! [String: String]
                switch failure {
                case "missing_source": items[0]["source_id"] = "not-this-turn"
                case "inline": pointers["temperature_min"] = "20"
                case "wrong_place": weather["location"] = "London"
                case "unit": weather["unit"] = "kelvin"
                case "stale": sources[0]["started_at"] = "2020-01-01T00:00:00Z"; sources[0]["completed_at"] = "2020-01-01T00:00:01Z"
                case "missing_identity": sources[0].removeValue(forKey: "server"); sources[0].removeValue(forKey: "tool")
                default: sources[0]["truncated"] = true; fields["truncated"] = true
                }
                items[0]["fields"] = pointers; section["items"] = items; manifest["weather"] = section
                fields["answer"] = String(decoding: try! JSONSerialization.data(withJSONObject: manifest), as: UTF8.self)
                sources[0]["result"] = weather; fields["sources"] = sources
            }
            let facts = try facts(result)
            XCTAssertNil(facts.weather, failure); XCTAssertEqual(facts.coverage[0].status, "unavailable", failure)
            XCTAssertEqual(facts.calendar.count, 1, "unrelated valid evidence survives a rejected weather item")
        }
    }
    func testScopeOwnerAndProviderIntervalsCannotBeInvented() throws {
        let result = try fixture()
        XCTAssertThrowsError(try WardrobeOutfitContext(result: result, request: request, owner: "another-account"))
        let otherPlace = WardrobeOutfitContextRequest(day: request.day, timeZone: request.timeZone, location: "London")
        XCTAssertThrowsError(try WardrobeOutfitContext(result: result, request: otherPlace, owner: "fixture-context"))
        let moved = try changed(result) { fields in
            var sources = fields["sources"] as! [[String: Any]]; var raw = sources[1]["result"] as! [String: Any]
            var event = raw["event"] as! [String: Any]; event["start"] = "2026-10-10T19:00:00-07:00"; event["end"] = "2026-10-10T20:30:00-07:00"
            raw["event"] = event; sources[1]["result"] = raw; fields["sources"] = sources
        }
        XCTAssertTrue(try facts(moved).calendar.isEmpty, "events outside the selected local day cannot be advice evidence")
        let allDay = try changed(result) { fields in
            var sources = fields["sources"] as! [[String: Any]]; var raw = sources[1]["result"] as! [String: Any]
            var event = raw["event"] as! [String: Any]; event["start"] = "2026-10-09"; event["end"] = "2026-10-10"
            raw["event"] = event; sources[1]["result"] = raw; fields["sources"] = sources
        }
        XCTAssertEqual(try facts(allDay).calendar.first?.allDay, true)
    }
    func testSourcePointersHandleArraysEscapesAndJSONTextWithoutGuessing() throws {
        let raw = GatewayJSON.object(["a/b": .object(["~name": .array([.integer(9_007_199_254_740_993)])]), "body": .string(#"{"low":10}"#)])
        XCTAssertEqual(try raw.value(at: "/a~1b/~0name/0"), .integer(9_007_199_254_740_993))
        XCTAssertEqual(try raw.value(at: "/body/low"), .integer(10))
        for pointer in ["inline", "/a~1b/~0name/01", "/a~1b/~0name/-1", "/bad~3", "/missing"] { XCTAssertThrowsError(try raw.value(at: pointer)) }
    }
    func testRefinementPreservesLocksExclusionsAndPreferenceFence() throws {
        let facts = try facts(fixture())
        let query = WardrobeSuggestQuery(day: request.day, occasion: "casual", warmth: "light", requiredIDs: ["11111111-1111-4111-8111-111111111111"],
            excludedIDs: ["22222222-2222-4222-8222-222222222222"], excludedCombinations: [String(repeating: "0", count: 64)], variant: 3, expectedPreferencesVersion: 9_007_199_254_740_993, swapRole: "feet")
        let next = try facts.refining(query, warmth: "warm", occasion: "dinner")
        XCTAssertEqual(next.requiredIDs, query.requiredIDs); XCTAssertEqual(next.excludedIDs, query.excludedIDs)
        XCTAssertEqual(next.excludedCombinations, query.excludedCombinations); XCTAssertEqual(next.swapRole, query.swapRole)
        XCTAssertEqual(next.expectedPreferencesVersion, query.expectedPreferencesVersion); XCTAssertEqual(next.variant, 0)
        XCTAssertThrowsError(try facts.refining(query, warmth: "waterproof", occasion: nil))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ranked-suggestions", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        fields["generated_at"] = ISO8601DateFormatter().string(from: Date())
        let result = try JSONDecoder().decode(WardrobeSuggestions.self, from: JSONSerialization.data(withJSONObject: fields))
        let context = try WardrobeCandidateContext(input: .init(day: request.day), result: result, revision: 0, timeZone: request.timeZone)
        var proposal = WardrobeCandidateProposal(intent: .refine, candidate: nil, piece: nil, explanation: "Review a warmer request.", evidence: [], unhandled: [], warmth: "warm", contextEvidence: ["w1"])
        XCTAssertNoThrow(try proposal.validate(context, connected: facts))
        XCTAssertThrowsError(try proposal.validate(context), "a guided shape cannot invent connected evidence")
        proposal.contextEvidence = ["w9"]
        XCTAssertThrowsError(try proposal.validate(context, connected: facts))
    }
    func testModelReusesFreshNativeContextWithoutAnotherRemoteTask() async throws {
        let facts = try facts(fixture())
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "fixture-context",
            stillOwner: { true }, save: { _ in }, send: { _ in XCTFail("fresh context must stay local"); throw URLError(.unsupportedURL) })
        let run = WardrobeAssistantRun(requests: requests, question: "What fits the forecast?", day: request.day, remoteEnabled: true,
            current: { true }, read: { _ in .retry("not used") }, waitForOwner: { _ in XCTFail("no new question") }, progress: { _ in }, outfitContextRequest: request, contextSeed: facts)
        XCTAssertNil(run.connectedFacts, "the model must read context before it can cite aliases")
        let text = try await run.readOutfitContext()
        XCTAssertTrue(text.contains("w1")); XCTAssertNotNil(run.connectedFacts); XCTAssertTrue(requests.items.isEmpty)
    }
    func testNativeFetchAndRecoveryRetainOriginalJobWithoutAnAppleModel() async throws {
        var calls: [GatewayAgentCall] = []
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "fixture-context",
            stillOwner: { true }, save: { _ in }, send: { call in calls.append(call); return try self.fixture(id: call.request_id) })
        let original = try requests.begin(request.agentQuery())
        let assistant = WardrobeAssistant(requests: requests, read: { _ in .retry("not used") })
        assistant.fetchOutfitContext(request, current: { true })
        for _ in 0..<1000 { if !assistant.running { break }; await Task.yield() }
        XCTAssertFalse(assistant.running); XCTAssertEqual(assistant.outfitContext?.weather?.lowC, 10)
        XCTAssertEqual(calls.map(\.request_id), [original]); XCTAssertEqual(requests.items.count, 1)
        assistant.fetchOutfitContext(request, current: { true }, requestID: original)
        for _ in 0..<1000 { if !assistant.running { break }; await Task.yield() }
        XCTAssertEqual(calls.map(\.request_id), [original, original]); XCTAssertEqual(requests.items.count, 1)
    }
    func testLateContextIsFencedAfterTheRequestChanges() async throws {
        var current = true
        let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "fixture-context",
            stillOwner: { true }, save: { _ in }, send: { call in current = false; return try self.fixture(id: call.request_id) })
        let assistant = WardrobeAssistant(requests: requests, read: { _ in .retry("not used") })
        assistant.fetchOutfitContext(request, current: { current })
        for _ in 0..<1000 { if !assistant.running { break }; await Task.yield() }
        XCTAssertFalse(assistant.running); XCTAssertNil(assistant.outfitContext); XCTAssertNil(assistant.answer)
        XCTAssertEqual(requests.items.count, 1, "a changed request must not start a replacement job")
    }
}
