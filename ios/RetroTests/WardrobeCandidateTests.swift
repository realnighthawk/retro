import XCTest
@testable import Retro

@MainActor final class WardrobeCandidateTests: XCTestCase {
    private let shoesID = "22222222-2222-4222-8222-222222222222"
    private func suggestions() throws -> WardrobeSuggestions {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ranked-suggestions", withExtension: "json", subdirectory: "wardrobe"))
        let source = try JSONDecoder().decode(WardrobeSuggestions.self, from: Data(contentsOf: url))
        let dress = source.items[0].items[0]
        let shoes = WardrobeSuggestedItem(garmentID: shoesID, role: "feet", version: 4, name: "Everyday shoes")
        let top = WardrobeSuggestedItem(garmentID: "33333333-3333-4333-8333-333333333333", role: "base", version: 7, name: "Blue shirt")
        let bottom = WardrobeSuggestedItem(garmentID: "44444444-4444-4444-8444-444444444444", role: "bottom", version: 2, name: "Dark trousers")
        let options = [[dress, shoes], [top, bottom, shoes]].map { pieces in
            let seed = WardrobeSuggestion(items: pieces, fingerprint: "", reasons: [], missingRoles: [])
            return WardrobeSuggestion(items: pieces, fingerprint: seed.calculatedFingerprint, reasons: ["Only active, ready pieces are included.", "Saved preferences determine this score."], missingRoles: [], score: 8)
        }
        return WardrobeSuggestions(day: source.day, algorithm: source.algorithm, generatedAt: ISO8601DateFormatter().string(from: Date()),
            items: options, noResultReason: nil, effectiveOccasion: "casual", preferencesSource: source.preferencesSource,
            feedbackSamples: source.feedbackSamples, feedbackCoverage: source.feedbackCoverage, warnings: source.warnings)
    }
    private func context() throws -> WardrobeCandidateContext {
        let result = try suggestions()
        return try WardrobeCandidateContext(input: WardrobeSuggestQuery(day: result.day, requiredIDs: [shoesID],
            excludedIDs: ["55555555-5555-4555-8555-555555555555"], excludedCombinations: [String(repeating: "0", count: 64)], variant: 4), result: result, revision: 0)
    }
    private func changed(_ value: WardrobeSuggestions, _ edit: (inout [String: Any]) -> Void) throws -> WardrobeSuggestions {
        var fields = try WardrobeSettingFields.object(value); edit(&fields)
        return try JSONDecoder().decode(WardrobeSuggestions.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func proposal(_ intent: WardrobeCandidateProposal.Intent = .compare, candidate: String? = "c1", piece: String? = nil,
                          evidence: [WardrobeCandidateProposal.Evidence] = [.init(candidate: "c1", reason: 1)],
                          unhandled: [String] = []) -> WardrobeCandidateProposal {
        WardrobeCandidateProposal(intent: intent, candidate: candidate, piece: piece, explanation: "Review this supplied choice.", evidence: evidence, unhandled: unhandled)
    }
    func testModelFactsUseScopedAliasesAndExactVersionsWithoutInventoryClaims() throws {
        let context = try context(); let text = try context.modelFacts()
        let facts = try JSONDecoder().decode(GatewayJSON.self, from: Data(text.utf8))
        XCTAssertEqual(facts["preferences_version"], .string("9007199254740993"))
        XCTAssertFalse(text.contains(shoesID)); XCTAssertTrue(text.contains("\"locked\":true"))
        XCTAssertTrue(text.contains("not exhaustive inventory")); XCTAssertLessThanOrEqual(text.utf8.count, 4000)
        XCTAssertEqual(context.candidate("c2")?.items.count, 3)
        XCTAssertNil(context.candidate("c01")); XCTAssertNil(context.candidate(context.result.items[0].id))
        XCTAssertEqual(context.piece("g1", in: context.result.items[1])?.role, "base")
        XCTAssertEqual(context.piece("g1", in: context.result.items[0])?.role, "one_piece")
    }
    func testSwapRetainsDateRoleOtherPiecesAndEveryOriginalExclusion() throws {
        let context = try context(); let proposal = proposal(.swap, piece: "g1")
        try proposal.validate(context)
        let next = try proposal.swapQuery(context)
        XCTAssertEqual(next.requiredIDs, [shoesID]); XCTAssertEqual(next.swapRole, "one_piece")
        XCTAssertEqual(Set(next.excludedIDs), Set(context.query.excludedIDs + [context.result.items[0].items[0].garmentID]))
        XCTAssertEqual(next.excludedCombinations, context.query.excludedCombinations)
        XCTAssertEqual(next.day, context.query.day); XCTAssertEqual(next.occasion, "casual"); XCTAssertEqual(next.warmth, context.query.warmth)
        XCTAssertEqual(next.expectedPreferencesVersion, 9_007_199_254_740_993); XCTAssertEqual(next.variant, 0)
        XCTAssertThrowsError(try self.proposal(.swap, piece: "g2").validate(context), "locked shoes cannot be swapped")
        XCTAssertThrowsError(try self.proposal(.swap, candidate: "c3", piece: "g1").validate(context))
        XCTAssertThrowsError(try self.proposal(.swap, piece: shoesID).validate(context), "model output never accepts raw garment IDs")
    }
    func testUnknownDuplicateOrUnshownEvidenceCannotBecomeAdvice() throws {
        let context = try context()
        try proposal().validate(context)
        for evidence in [[WardrobeCandidateProposal.Evidence(candidate: "c9", reason: 1)], [.init(candidate: "c1", reason: 0)],
                         [.init(candidate: "c1", reason: 4)], [.init(candidate: "c1", reason: 1), .init(candidate: "c1", reason: 1)]] {
            XCTAssertThrowsError(try proposal(evidence: evidence).validate(context))
        }
        XCTAssertThrowsError(try proposal(candidate: "c2").validate(context), "selected comparison needs its own engine evidence")
        XCTAssertThrowsError(try proposal(piece: "g1").validate(context), "comparison cannot include a swap action")
        try proposal(.unsupported, candidate: nil, evidence: [], unhandled: ["Specify which option and piece."]).validate(context)
        XCTAssertThrowsError(try proposal(.unsupported, candidate: nil, evidence: []).validate(context))
    }
    func testCachedStaleDowngradedOrChangedPiecesCannotEnterModelContext() throws {
        let context = try context(); let result = context.result
        XCTAssertThrowsError(try WardrobeCandidateContext(input: context.input, result: result, revision: 0, cached: true))
        let stale = try changed(result) { $0["generated_at"] = "2026-01-01T00:00:00Z" }
        XCTAssertThrowsError(try context.replacing(with: stale))
        let legacy = try changed(result) { $0["algorithm"] = "rules-v1" }
        XCTAssertThrowsError(try context.replacing(with: legacy))
        let revised = try changed(result) { fields in
            var options = fields["items"] as! [[String: Any]]; var pieces = options[0]["items"] as! [[String: Any]]
            pieces[0]["version"] = 1; options[0]["items"] = pieces; fields["items"] = options
        }
        XCTAssertThrowsError(try context.replacing(with: revised))
        let reordered = try changed(result) { fields in fields["items"] = Array((fields["items"] as! [[String: Any]]).reversed()) }
        XCTAssertThrowsError(try context.replacing(with: reordered), "an alias cannot silently bind a different choice")
    }
    func testOversizedFactsFailWithManualFallbackRatherThanDroppingConstraints() throws {
        let source = try context()
        let result = try changed(source.result) { $0["warnings"] = Array(repeating: String(repeating: "x", count: 500), count: 8) }
        let large = try WardrobeCandidateContext(input: source.input, result: result, revision: 0)
        XCTAssertThrowsError(try large.modelFacts())
        XCTAssertEqual(large.query.requiredIDs, source.query.requiredIDs)
        XCTAssertEqual(large.query.excludedIDs, source.query.excludedIDs)
        XCTAssertEqual(large.query.excludedCombinations, source.query.excludedCombinations)
    }
    func testReadToolSharesOneFreshSnapshotAndFencesLateResults() async throws {
        for changeDuringRead in [false, true] {
            let facts = try context(); var current = true; var reads = 0
            let requests = WardrobeAgentRequests(file: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), owner: "A",
                stillOwner: { true }, save: { _ in }, send: { _ in throw URLError(.unsupportedURL) })
            let run = WardrobeAssistantRun(requests: requests, question: "Compare", day: facts.query.day, remoteEnabled: false,
                current: { current }, read: { _ in .retry("not a preferences request") }, waitForOwner: { _ in XCTFail("no connected input") }, progress: { _ in },
                candidateRead: { reads += 1; if changeDuringRead { current = false }; return facts })
            if changeDuringRead {
                do { _ = try await run.readCandidates(); XCTFail("late source") } catch {}
                XCTAssertNil(run.candidateFacts)
            } else {
                let first = try await run.readCandidates(); let second = try await run.readCandidates()
                XCTAssertTrue(first.contains("wardrobe_suggest")); XCTAssertTrue(second.contains("already_read")); XCTAssertEqual(reads, 1)
                do { _ = try await run.readCandidates(); XCTFail("read-call budget") } catch {}
                current = false
                do { _ = try await run.readCandidates(); XCTFail("old generation") } catch {}
            }
            XCTAssertTrue(requests.items.isEmpty, "fresh local choices never create remote requests")
        }
    }
    func testFreshStoreReadRejectsCacheAndChangedVersionsWithoutWriting() async throws {
        let owner = "candidate-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); CandidateProtocol.handle = nil }
        let context = try context(); var offline = false; var revised = false; var reads = 0; var signedIn = owner
        let changed = try changed(context.result) { fields in
            var options = fields["items"] as! [[String: Any]]; var pieces = options[0]["items"] as! [[String: Any]]
            pieces[0]["version"] = 1; options[0]["items"] = pieces; fields["items"] = options
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CandidateProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://candidate.test/api/v1", session: session), currentUser: { signedIn }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        CandidateProtocol.handle = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "wardrobe_suggest"); reads += 1
            let query = try JSONDecoder().decode(WardrobeSuggestQuery.self, from: CandidateProtocol.body(request))
            XCTAssertEqual(query, context.query)
            if offline { throw URLError(.notConnectedToInternet) }
            return try JSONEncoder().encode(revised ? changed : context.result)
        }
        let fresh = try await store.refreshCandidateContext(context)
        XCTAssertEqual(fresh.query, context.query); XCTAssertEqual(reads, 1); XCTAssertTrue(store.writes.items.isEmpty)
        offline = true
        do { _ = try await store.refreshCandidateContext(context); XCTFail("cached model facts") } catch {}
        offline = false; revised = true
        do { _ = try await store.refreshCandidateContext(context); XCTFail("changed pieces") } catch {}
        revised = false
        try store.writes.enqueue(operation: "garments_update", entity: shoesID, title: "Shoes", fields: ["id": shoesID, "expected_version": 4, "name": "Edited shoes"])
        let pending = store.writes.items[0].body
        do { _ = try await store.refreshCandidateContext(context); XCTFail("pending piece") } catch {}
        XCTAssertEqual(store.writes.items.count, 1); XCTAssertEqual(store.writes.items[0].body, pending)
        let previousReads = reads; signedIn = "another owner"
        do { _ = try await store.refreshCandidateContext(context); XCTFail("old account") } catch {}
        XCTAssertEqual(reads, previousReads)
    }
}

private final class CandidateProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> Data)?
    static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); guard n > 0 else { break }; data.append(buffer, count: n) }
        return data
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let body = try Self.handle!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
