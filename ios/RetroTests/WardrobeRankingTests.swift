import XCTest
@testable import Retro

@MainActor final class WardrobeRankingTests: XCTestCase {
    private func fixture() throws -> WardrobeSuggestions {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ranked-suggestions", withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(WardrobeSuggestions.self, from: Data(contentsOf: url))
    }
    private func changed(_ value: WardrobeSuggestions, _ edit: (inout [String: Any]) -> Void) throws -> WardrobeSuggestions {
        var fields = try WardrobeSettingFields.object(value); edit(&fields)
        return try JSONDecoder().decode(WardrobeSuggestions.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testRankingKeepsExactPreferenceVersionAndDefaultOccasionForReview() throws {
        var value = try fixture(); value.effectiveOccasion = "casual"
        let input = WardrobeSuggestQuery(day: value.day)
        let query = try value.reviewQuery(input, cached: true)
        XCTAssertEqual(query.expectedPreferencesVersion, 9_007_199_254_740_993); XCTAssertEqual(query.occasion, "casual")
        let wire = try JSONDecoder().decode(GatewayJSON.self, from: JSONEncoder().encode(query))
        XCTAssertEqual(wire["expected_preferences_version"], .integer(9_007_199_254_740_993))
        XCTAssertEqual(value.items[0].items[0].name, "Renamed dress")
        XCTAssertThrowsError(try value.reviewQuery(input), "old cached rankings must not be called fresh")
        XCTAssertThrowsError(try value.reviewQuery(WardrobeSuggestQuery(day: "2026-10-10"), cached: true))
    }
    func testMalformedRankingOrUnmatchedConstraintsCannotBeReviewed() throws {
        let value = try fixture(); let input = WardrobeSuggestQuery(day: value.day)
        let wrongHash = try changed(value) { fields in
            var options = fields["items"] as! [[String: Any]]; options[0]["fingerprint"] = String(repeating: "0", count: 64); fields["items"] = options
        }
        XCTAssertThrowsError(try wrongHash.reviewQuery(input, cached: true))
        var wrong = value; wrong.feedbackCoverage = "complete_wardrobe"
        XCTAssertThrowsError(try wrong.reviewQuery(input, cached: true))
        wrong = try changed(value) { fields in
            var options = fields["items"] as! [[String: Any]]; options[0]["score"] = Int.min; fields["items"] = options
        }
        XCTAssertThrowsError(try wrong.reviewQuery(input, cached: true))
        var query = input; query.requiredIDs = [UUID().uuidString.lowercased()]
        XCTAssertThrowsError(try value.reviewQuery(query, cached: true))
        query = input; query.expectedPreferencesVersion = 1
        XCTAssertThrowsError(try value.reviewQuery(query, cached: true))
        let legacy = try changed(value) { $0["algorithm"] = "rules-v1" }
        query.expectedPreferencesVersion = value.preferencesSource?.version
        XCTAssertThrowsError(try legacy.reviewQuery(query, cached: true), "a versioned ranking cannot downgrade to legacy evidence")
    }
    func testSwapKeepsOtherPiecesExcludesTargetAndHonorsLocks() throws {
        let dress = WardrobeSuggestedItem(garmentID: "11111111-1111-4111-8111-111111111111", role: "one_piece", version: 1)
        let shoes = WardrobeSuggestedItem(garmentID: "22222222-2222-4222-8222-222222222222", role: "feet", version: 1)
        var option = WardrobeSuggestion(items: [dress, shoes], fingerprint: "", reasons: [], missingRoles: [])
        option = WardrobeSuggestion(items: option.items, fingerprint: option.calculatedFingerprint, reasons: [], missingRoles: [])
        let piece = WardrobeSelection(id: dress.garmentID, name: "Dress", role: "one_piece")
        let query = WardrobeSuggestQuery(day: "2026-10-09", requiredIDs: [shoes.garmentID])
        let swap = try option.swapping(piece, query: query)
        XCTAssertEqual(swap.requiredIDs, [shoes.garmentID]); XCTAssertEqual(swap.excludedIDs, [dress.garmentID]); XCTAssertEqual(swap.swapRole, "one_piece")
        XCTAssertThrowsError(try option.swapping(piece, query: query, locked: [piece.id]))
        var locked = query; locked.requiredIDs.append(piece.id)
        XCTAssertThrowsError(try option.swapping(piece, query: locked))
        locked = query; locked.requiredIDs.append(UUID().uuidString.lowercased())
        XCTAssertThrowsError(try option.swapping(piece, query: locked), "must not discard an unknown required piece")
    }
    func testFreshReviewRechecksRankingBeforeOpeningAnUnsavedPlan() async throws {
        let owner = "ranking-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); RankingProtocol.handle = nil }
        let response = try changed(fixture()) { $0["generated_at"] = ISO8601DateFormatter().string(from: Date()) }
        let query = try response.reviewQuery(WardrobeSuggestQuery(day: response.day))
        let option = try XCTUnwrap(response.items.first)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RankingProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://ranking.test/api/v1", session: session), currentUser: { owner }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "inventory", withExtension: "json", subdirectory: "wardrobe"))
        let garment = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: Data(contentsOf: url)).items[0]
        var operations: [String] = []; var stale = false
        RankingProtocol.handle = { request in
            let op = request.url!.lastPathComponent; operations.append(op)
            if op == "wardrobe_suggest" {
                if stale { return (409, Data(#"{"error":{"code":"conflict","message":"Preferences changed"}}"#.utf8)) }
                return (200, try JSONEncoder().encode(response))
            }
            return (200, try JSONEncoder().encode(WardrobeGarmentResult(garment: garment)))
        }
        let draft = try await store.reviewSuggestion(option, query: query)
        XCTAssertEqual(operations, ["wardrobe_suggest", "garments_get"])
        XCTAssertEqual(draft.state, "planned"); XCTAssertTrue(store.writes.items.isEmpty)
        stale = true; operations = []
        do { _ = try await store.reviewSuggestion(option, query: query); XCTFail("stale preference context") } catch {}
        XCTAssertEqual(operations, ["wardrobe_suggest"]); XCTAssertTrue(store.writes.items.isEmpty)
    }
}

private final class RankingProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handle = Self.handle else { throw URLError(.badServerResponse) }
            let (status, body) = try handle(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    func testTemperatureIsOptionalAndOnlySentWhenStated() throws {
        func fields(_ query: WardrobeSuggestQuery) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        }
        let plain = try fields(WardrobeSuggestQuery(day: "2026-10-09"))
        XCTAssertNil(plain["temperature_c"], "No temperature is stated, so ranking is not given one")
        XCTAssertNil(plain["precipitation"])
        var cold = WardrobeSuggestQuery(day: "2026-10-09")
        cold.temperatureC = 4; cold.precipitation = true
        let sent = try fields(cold)
        XCTAssertEqual(sent["temperature_c"] as? Int, 4)
        XCTAssertEqual(sent["precipitation"] as? Bool, true)
        // A cleared field removes the value rather than sending a zero.
        cold.temperatureC = nil; cold.precipitation = nil
        let cleared = try fields(cold)
        XCTAssertNil(cleared["temperature_c"]); XCTAssertNil(cleared["precipitation"])
    }
}
