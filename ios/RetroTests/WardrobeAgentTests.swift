import XCTest
@testable import Retro

private func agentResult(_ id: String, status: GatewayAgentStatus = .completed, input: GatewayAgentInput? = nil, owner: String = "A") -> GatewayAgentResult {
    let session = "mcp-test-" + id
    return GatewayAgentResult(schema_version: 1, request_id: id, session_id: session,
        turn_id: "agent:main:web:user:\(owner):session:\(session):turn:1", status: status,
        retrieved_at: ISO8601DateFormatter().string(from: Date()), completed_at: nil,
        answer: status == .completed ? "Use a light layer." : nil, truncated: false,
        coverage: "recent_top_level_tool_calls", sources: nil, pending_input: input, retry_after_ms: 100)
}
private func agentInput(_ id: String) -> GatewayAgentInput {
    let root = agentResult(id).turn_id
    return GatewayAgentInput(request_id: root + ":sub:1:act:2", kind: "permission", prompt: "Approve the connected tool?",
        options: [.init(id: "approve", label: "Approve"), .init(id: "deny", label: "Deny")], allow_free_text: false)
}

private final class AgentURLProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handle = Self.handle else { throw URLError(.badServerResponse) }
            let (status, headers, body) = try handle(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class GatewayMCPTests: XCTestCase {
    private func body(_ request: URLRequest) throws -> GatewayJSON {
        if let data = request.httpBody { return try JSONDecoder().decode(GatewayJSON.self, from: data) }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); guard count > 0 else { break }; data.append(buffer, count: count) }
        return try JSONDecoder().decode(GatewayJSON.self, from: data)
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AgentURLProtocol.self]
        return URLSession(configuration: config)
    }
    private func rpcResult(_ request: GatewayJSON) throws -> Data {
        let result: GatewayJSON
        switch request["method"]?.text {
        case "initialize": result = .object(["protocolVersion": .string("2025-06-18"), "serverInfo": .object(["name": .string("agent-harness-gateway")]), "capabilities": .object(["tools": .object([:])])])
        case "tools/list": result = .object(["tools": .array([.object(["name": .string("ask_agent"), "inputSchema": .object(["properties": .object(["query": .object(["type": .string("string")]), "request_id": .object(["type": .string("string")])])]), "outputSchema": .object(["type": .string("object")])])])])
        case "tools/call":
            let id = try XCTUnwrap(request["params"]?["arguments"]?["request_id"]?.text)
            result = .object(["structuredContent": try JSONDecoder().decode(GatewayJSON.self, from: JSONEncoder().encode(agentResult(id)))])
        default: throw URLError(.badServerResponse)
        }
        return try JSONEncoder().encode(GatewayJSON.object(["jsonrpc": .string("2.0"), "id": request["id"]!, "result": result]))
    }

    func testDiscoveryAndEveryPostUseExistingAuthWithOne401Refresh() async throws {
        var refreshes: [Bool] = []; var methods: [String] = []; var rejected = false
        let engine = Engine(owner: "A", router: RetroAPI(baseURL: "https://router.test"), currentUser: { "A" }, token: { refresh in refreshes.append(refresh); return refresh ? "fresh" : "cached" })
        let session = session(); defer { session.invalidateAndCancel(); AgentURLProtocol.handle = nil }
        AgentURLProtocol.handle = { request in
            XCTAssertEqual(request.url?.path, "/gateway/mcp")
            XCTAssertEqual(request.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2025-06-18")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try self.body(request); let method = try XCTUnwrap(body["method"]?.text); methods.append(method)
            if !rejected { rejected = true; return (401, [:], Data()) }
            if method == "notifications/initialized" { XCTAssertNil(body["id"]); return (202, [:], Data()) }
            return (200, ["Content-Type": "application/json"], try self.rpcResult(body))
        }
        let client = GatewayMCP(engine: engine, session: session); let id = UUID().uuidString.lowercased()
        let result = try await client.ask(.init(request_id: id, query: "Help with layers"))
        XCTAssertEqual(result.request_id, id)
        XCTAssertEqual(methods, ["initialize", "initialize", "notifications/initialized", "tools/list", "tools/call"])
        XCTAssertEqual(refreshes, [false, true, false, false, false])
        _ = try await client.ask(.init(request_id: id, query: "Help with layers"))
        XCTAssertEqual(methods.last, "tools/call"); XCTAssertEqual(methods.count, 6)
    }

    func testAccountSwitchBeforeDelegateSendsNoNewOwnersToken() async {
        var owner = "A"; var tokens = 0; var methods: [String] = []
        let engine = Engine(owner: "A", router: RetroAPI(baseURL: "https://router.test"), currentUser: { owner }, token: { _ in
            tokens += 1; if tokens == 4 { owner = "B" }; return owner == "A" ? "A-token" : "B-token"
        })
        let session = session(); defer { session.invalidateAndCancel(); AgentURLProtocol.handle = nil }
        AgentURLProtocol.handle = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer A-token")
            let body = try self.body(request); let method = try XCTUnwrap(body["method"]?.text); methods.append(method)
            return method == "notifications/initialized" ? (202, [:], Data()) : (200, ["Content-Type": "application/json"], try self.rpcResult(body))
        }
        do { _ = try await GatewayMCP(engine: engine, session: session).ask(.init(request_id: UUID().uuidString.lowercased(), query: "Help")); XCTFail("must fence the old account") } catch {}
        XCTAssertEqual(methods, ["initialize", "notifications/initialized", "tools/list"])
    }

    func testUnexpectedSSEOrSessionTransportFailsClosed() async {
        for headers in [["Content-Type": "text/event-stream"], ["Content-Type": "application/json", "Mcp-Session-Id": "stateful"]] {
            let engine = Engine(owner: "A", router: RetroAPI(baseURL: "https://router.test"), currentUser: { "A" }, token: { _ in "token" })
            let session = session(); var sends = 0
            AgentURLProtocol.handle = { request in sends += 1; return (200, headers, try self.rpcResult(self.body(request))) }
            do { _ = try await GatewayMCP(engine: engine, session: session).ask(.init(request_id: UUID().uuidString.lowercased(), query: "Help")); XCTFail("unsupported transport") } catch {}
            XCTAssertEqual(sends, 1); session.invalidateAndCancel(); AgentURLProtocol.handle = nil
        }
    }

    func testWrongRPCIdentityAndOversizedWireFailBeforeDelegation() async {
        let invalidBodies = [Data(#"{"jsonrpc":"2.0","id":"another-request","result":{}}"#.utf8), Data(repeating: 32, count: 128 * 1024 + 1)]
        for body in invalidBodies {
            let engine = Engine(owner: "A", router: RetroAPI(baseURL: "https://router.test"), currentUser: { "A" }, token: { _ in "token" })
            let session = session(); var sends = 0
            AgentURLProtocol.handle = { _ in sends += 1; return (200, ["Content-Type": "application/json"], body) }
            do { _ = try await GatewayMCP(engine: engine, session: session).ask(.init(request_id: UUID().uuidString.lowercased(), query: "Help")); XCTFail("invalid RPC") } catch {}
            XCTAssertEqual(sends, 1); session.invalidateAndCancel(); AgentURLProtocol.handle = nil
        }
    }

    func testEvidenceKeepsInt64AndRejectsWrongOwnerOrStaleSnapshot() throws {
        let data = Data(#"{"version":9007199254740993,"zero":0,"enabled":false}"#.utf8)
        let json = try JSONDecoder().decode(GatewayJSON.self, from: data)
        XCTAssertEqual(json["version"], .integer(9_007_199_254_740_993)); XCTAssertEqual(json["zero"], .integer(0)); XCTAssertEqual(json["enabled"], .bool(false))
        XCTAssertEqual(try JSONDecoder().decode(GatewayJSON.self, from: JSONEncoder().encode(json)), json)
        let id = UUID().uuidString.lowercased(); let result = agentResult(id)
        XCTAssertNoThrow(try result.validate(requestID: id, owner: "A"))
        XCTAssertThrowsError(try result.validate(requestID: id, owner: "B"))
        XCTAssertThrowsError(try result.validate(requestID: UUID().uuidString.lowercased(), owner: "A"))
        XCTAssertThrowsError(try result.validate(requestID: id, owner: "A", now: Date().addingTimeInterval(600)))
        let input = agentInput(id)
        XCTAssertNoThrow(try agentResult(id, status: .needsInput, input: input).validate(requestID: id, owner: "A"))
        XCTAssertThrowsError(try GatewayAgentResponse(request_id: input.request_id, selected_option_id: "unknown").validate(input))
        XCTAssertThrowsError(try GatewayAgentResponse(request_id: input.request_id, free_text: "approve").validate(input))
        XCTAssertThrowsError(try GatewayAgentResponse(request_id: input.request_id, selected_option_id: "approve", free_text: "yes").validate(input))
    }
}

@MainActor final class WardrobeAgentRequestsTests: XCTestCase {
    private func file() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "requests.json") }
    func testLostReplyReopensAndReusesOriginalTaskIdentityAndQuery() async throws {
        let file = file(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var calls: [GatewayAgentCall] = []
        let requests = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in calls.append(call); throw URLError(.networkConnectionLost) }
        let id = try requests.begin("Help with layers")
        do { _ = try await requests.perform(id); XCTFail("lost reply") } catch {}
        let reopened = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in calls.append(call); return agentResult(call.request_id) }
        _ = try await reopened.perform(id)
        XCTAssertEqual(calls.map(\.request_id), [id, id]); XCTAssertEqual(calls.map(\.query), ["Help with layers", "Help with layers"])
        XCTAssertTrue(reopened.items[0].terminal)
    }

    func testPersistenceFailurePreventsAcceptanceAndTransmission() async throws {
        var sent = 0; var denySave = false
        let requests = WardrobeAgentRequests(file: file(), owner: "A", stillOwner: { true }, save: { _ in if denySave { throw CocoaError(.fileWriteOutOfSpace) } }) { call in sent += 1; return agentResult(call.request_id) }
        denySave = true; XCTAssertThrowsError(try requests.begin("Help")); XCTAssertTrue(requests.items.isEmpty)
        denySave = false; let id = try requests.begin("Help"); denySave = true
        do { _ = try await requests.perform(id); XCTFail("must persist dispatch before send") } catch {}
        XCTAssertEqual(sent, 0); XCTAssertFalse(requests.items[0].dispatched)
    }

    func testOwnerAnswerAndStopIntentSurviveRelaunchWithoutAutoApproval() async throws {
        let file = file(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var calls: [GatewayAgentCall] = []
        let requests = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in calls.append(call); return agentResult(call.request_id, status: .needsInput, input: agentInput(call.request_id)) }
        let id = try requests.begin("Help"); _ = try await requests.perform(id)
        XCTAssertNil(calls[0].response)
        let input = try XCTUnwrap(requests.item(id)?.pendingInput)
        try requests.answer(id, response: .init(request_id: input.request_id, selected_option_id: "deny"))
        let reopened = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in calls.append(call); return agentResult(call.request_id, status: .running) }
        _ = try await reopened.perform(id); XCTAssertEqual(calls.last?.response?.selected_option_id, "deny")
        try reopened.requestCancellation([id])
        let stopped = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in calls.append(call); return agentResult(call.request_id, status: .cancelled) }
        await stopped.retryCancellations()
        XCTAssertEqual(calls.last?.request_id, id); XCTAssertTrue(calls.last?.cancel == true); XCTAssertNil(calls.last?.response)
        XCTAssertTrue(stopped.items[0].terminal)
    }

    func testOldOwnerCannotPollOrAnswerButCanRetainStopIntent() async throws {
        var owner = true; var sent = 0
        let requests = WardrobeAgentRequests(file: file(), owner: "A", stillOwner: { owner }, save: { _ in }) { call in sent += 1; return agentResult(call.request_id, status: .needsInput, input: agentInput(call.request_id)) }
        let id = try requests.begin("Help"); _ = try await requests.perform(id); owner = false
        XCTAssertThrowsError(try requests.answer(id, response: .init(request_id: agentInput(id).request_id, selected_option_id: "approve")))
        try requests.requestCancellation([id]); await requests.retryCancellations()
        XCTAssertEqual(sent, 1); XCTAssertTrue(requests.items[0].cancellationRequested)
        do { _ = try await requests.perform(id); XCTFail("wrong owner") } catch {}
    }

    func testLateResultCannotAcknowledgeThePreviousOwner() async throws {
        var owner = true
        let requests = WardrobeAgentRequests(file: file(), owner: "A", stillOwner: { owner }, save: { _ in }) { call in
            owner = false; return agentResult(call.request_id)
        }
        let id = try requests.begin("Help")
        do { _ = try await requests.perform(id); XCTFail("late result must be fenced") } catch {}
        XCTAssertNil(requests.item(id)?.latest); XCTAssertFalse(requests.item(id)?.terminal == true)
    }

    func testUnknownCancellationKeepsItsIdentityAndNeverRestartsTheTask() async throws {
        var calls: [GatewayAgentCall] = []
        let requests = WardrobeAgentRequests(file: file(), owner: "A", stillOwner: { true }, save: { _ in }) { call in
            calls.append(call); throw GatewayAgentError(code: "not_found", message: "Not visible yet")
        }
        let id = try requests.begin("Help"); try requests.requestCancellation([id])
        await requests.retryCancellations(); await requests.retryCancellations()
        XCTAssertEqual(calls.map(\.request_id), [id, id]); XCTAssertTrue(calls.allSatisfy(\.cancel))
        XCTAssertEqual(requests.item(id)?.statusText, "Stop pending")
    }

    func testUnreadableJournalIsPreservedAndBlocksNewRemoteRequests() throws {
        let file = file(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("unreadable".utf8); try corrupt.write(to: file)
        let requests = WardrobeAgentRequests(file: file, owner: "A", stillOwner: { true }) { call in agentResult(call.request_id) }
        XCTAssertNotNil(requests.storageProblem); XCTAssertThrowsError(try requests.begin("Help"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}

@MainActor final class WardrobeAssistantTests: XCTestCase {
    private func requests(send: @escaping (GatewayAgentCall) async throws -> GatewayAgentResult = { agentResult($0.request_id) }) -> WardrobeAgentRequests {
        WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "A", stillOwner: { true }, save: { _ in }, send: send)
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        XCTFail("controller did not reach the expected state")
    }
    private func context(_ input: WardrobeContextInput, oversized: Bool = false) throws -> WardrobeContext {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "preferences", withExtension: "json", subdirectory: "wardrobe"))
        var p = try JSONDecoder().decode(WardrobePreferencesResult.self, from: Data(contentsOf: url)).preferences
        if oversized {
            p.preferred_colours = (0..<10).map { String(repeating: "a", count: 90) + String($0) }
            p.avoided_colours = (0..<10).map { String(repeating: "b", count: 90) + String($0) }
        }
        return WardrobeContext(schema_version: 1, request_id: input.request_id, retrieved_at: ISO8601DateFormatter().string(from: Date()),
            coverage: "explicit_records_only", capabilities: ["wardrobe_records", "preferences", "care", "feedback"], preferences: p,
            garments: [], outfits: [], feedback: [], sources: [.init(entity_type: "preferences", id: p.id, version: p.version, updated_at: p.updated_at)])
    }

    func testLocalFactsAreBoundedVersionedAndLimitedToPreferences() async throws {
        var reads = 0
        let run = WardrobeAssistantRun(requests: requests(), question: "Help", day: "2026-10-09", remoteEnabled: false,
            current: { true }, read: { input in reads += 1; return .ok(try! self.context(input)) }, waitForOwner: { _ in XCTFail("no owner input") }, progress: { _ in })
        let text = try await run.readPreferences()
        let facts = try JSONDecoder().decode(GatewayJSON.self, from: Data(text.utf8))
        XCTAssertEqual(facts["preferences"]?["version"], .integer(9_007_199_254_740_993))
        XCTAssertNil(facts["preferences"]?["machine_presets"])
        XCTAssertTrue(facts["coverage"]?.text?.hasPrefix("preferences_only") == true)
        _ = try await run.readPreferences()
        do { _ = try await run.readPreferences(); XCTFail("read budget") } catch {}
        XCTAssertEqual(reads, 2)
        do { _ = try await run.askAgent("Help"); XCTFail("remote opt-in required") } catch {}
        XCTAssertTrue(run.requests.items.isEmpty)
    }

    func testToolDelegationBudgetAndGenerationFence() async throws {
        var current = true; var sends = 0
        let requests = requests { call in sends += 1; return agentResult(call.request_id) }
        let run = WardrobeAssistantRun(requests: requests, question: "Help", day: "2026-10-09", remoteEnabled: true,
            current: { current }, read: { _ in .retry("unused") }, waitForOwner: { _ in XCTFail("no pending input") }, progress: { _ in })
        _ = try await run.askAgent("Suggest layers"); _ = try await run.askAgent("Explain that suggestion")
        do { _ = try await run.askAgent("One more"); XCTFail("delegation budget") } catch {}
        XCTAssertEqual(sends, 2); XCTAssertEqual(Set(requests.items.map(\.id)).count, 2)
        XCTAssertTrue(requests.items.allSatisfy { $0.query.contains("Owner request:\nHelp") })
        current = false
        do { _ = try await run.readPreferences(); XCTFail("stale generation") } catch {}
        XCTAssertNil(run.factsRetrievedAt)
    }

    func testOversizedOrLatePreferencesNeverBecomeModelFacts() async {
        for oversized in [true, false] {
            var current = true
            let run = WardrobeAssistantRun(requests: requests(), question: "Help", day: "2026-10-09", remoteEnabled: false,
                current: { current }, read: { input in
                    let context = try! self.context(input, oversized: oversized)
                    if !oversized { current = false }
                    return .ok(context)
                }, waitForOwner: { _ in }, progress: { _ in })
            do { _ = try await run.readPreferences(); XCTFail("invalid context must stay out of the model") } catch {}
            XCTAssertNil(run.factsRetrievedAt)
        }
    }

    func testRepeatedModelQueryReusesTheTaskWithinAnAttempt() async throws {
        var calls: [GatewayAgentCall] = []
        let requests = requests { call in calls.append(call); return agentResult(call.request_id) }
        let run = WardrobeAssistantRun(requests: requests, question: "Help", day: "2026-10-09", remoteEnabled: true,
            current: { true }, read: { _ in .retry("unused") }, waitForOwner: { _ in }, progress: { _ in })
        _ = try await run.askAgent("Suggest layers"); _ = try await run.askAgent("Suggest layers")
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[0].request_id, calls[1].request_id)
        XCTAssertEqual(requests.items.count, 1)
    }

    func testRecoveredOwnerQuestionOnlyResumesAfterNativeChoice() async throws {
        var calls: [GatewayAgentCall] = []
        let requests = requests { call in
            calls.append(call)
            if call.response == nil { return agentResult(call.request_id, status: .needsInput, input: agentInput(call.request_id)) }
            return agentResult(call.request_id)
        }
        let id = try requests.begin("Help")
        let other = try requests.begin("Other question"); _ = try await requests.perform(other); calls = []
        let assistant = WardrobeAssistant(requests: requests, read: { _ in .retry("unused") })
        assistant.checkRequest(id)
        await waitUntil { assistant.waitingRequestID == id }
        XCTAssertEqual(calls.count, 1); XCTAssertTrue(assistant.running)
        assistant.answerRequest(other, response: .init(request_id: agentInput(other).request_id, selected_option_id: "approve"))
        XCTAssertNil(requests.item(other)?.response); XCTAssertEqual(calls.count, 1)
        assistant.answerRequest(id, response: .init(request_id: agentInput(id).request_id, selected_option_id: "deny"))
        await waitUntil { !assistant.running }
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[1].request_id, id); XCTAssertEqual(calls[1].response?.selected_option_id, "deny")
        XCTAssertEqual(assistant.answerOrigin, "Connected agent · recovered task")
    }

    func testPauseCancelsParkedInputAndDiscardsLateAnswer() async throws {
        var calls: [GatewayAgentCall] = []
        let requests = requests { call in
            calls.append(call)
            return call.cancel ? agentResult(call.request_id, status: .cancelled) : agentResult(call.request_id, status: .needsInput, input: agentInput(call.request_id))
        }
        let id = try requests.begin("Help")
        let assistant = WardrobeAssistant(requests: requests, read: { _ in .retry("unused") })
        assistant.checkRequest(id); await waitUntil { assistant.waitingRequestID == id }
        assistant.pause("Stopped")
        await waitUntil { calls.contains(where: \.cancel) }
        XCTAssertFalse(assistant.running); XCTAssertNil(assistant.answer); XCTAssertTrue(requests.item(id)?.cancellationRequested == true)
        XCTAssertTrue(calls.dropFirst().allSatisfy { $0.cancel && $0.response == nil && $0.request_id == id })
    }
}
