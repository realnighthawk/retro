import XCTest
@testable import Retro

@MainActor final class WardrobeAssistanceTests: XCTestCase {
    private let extraID = "11111111-1111-4111-8111-222222222222"
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func changing<T: Codable>(_ value: T, _ fields: [String: Any]) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object.merge(fields) { _, new in new }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testInterpretationKeepsUnsupportedConditionsOutOfEngineInputAndRequiresRealIDs() throws {
        let query = try WardrobeLanguageDraft(category: "outerwear", availability: "ready", unhandled: ["Jacket subtype", "Waterproof"]).searchQuery()
        XCTAssertEqual(query.category, "outerwear"); XCTAssertEqual(query.availability, "ready")
        XCTAssertEqual(query.search, ""); XCTAssertNil(query.cursor)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        XCTAssertNil(wire["unhandled"]); XCTAssertNil(wire["material"])
        XCTAssertThrowsError(try WardrobeLanguageDraft(category: "jacket").searchQuery())
        XCTAssertThrowsError(try WardrobeLanguageDraft(occasion: "Dinner", category: "top").validate(.outfit))
        XCTAssertThrowsError(try WardrobeLanguageDraft(requiredGarments: ["the shirt"]).searchQuery())
        XCTAssertThrowsError(try WardrobeLanguageDraft(nameQuery: String(repeating: "é", count: 51)).searchQuery())
        let id = try fixture("inventory", as: WardrobePage<WardrobeGarment>.self).items[0].id
        let piece = WardrobeSelection(id: id, name: "Chosen dress", role: "one_piece")
        let request = WardrobeLanguageDraft(occasion: "Dinner", warmth: "warm", requiredGarments: ["the blue dress"], unhandled: ["Forecast"])
        let input = try request.outfitQuery(day: "2026-10-07", required: [piece], excluded: [])
        XCTAssertEqual(input.requiredIDs, [id]); XCTAssertEqual(input.occasion, "Dinner")
        XCTAssertThrowsError(try request.outfitQuery(day: "2026-10-07", required: [piece, piece], excluded: []))
        XCTAssertThrowsError(try request.outfitQuery(day: "2026-10-07", required: [piece], excluded: [piece]))
        XCTAssertThrowsError(try request.outfitQuery(day: "2026-02-30", required: [piece], excluded: []))
    }
    func testTranscriptHandoffRequiresSameInputOwnerAndBoundedReviewedText() throws {
        XCTAssertEqual(try WardrobeSpeech.reviewed("Blue shirt", baseline: "typed", current: "typed", owner: true, byteLimit: 100), "Blue shirt")
        XCTAssertThrowsError(try WardrobeSpeech.reviewed("Blue shirt", baseline: "typed", current: "edited", owner: true, byteLimit: 100))
        XCTAssertThrowsError(try WardrobeSpeech.reviewed("Blue shirt", baseline: "", current: "", owner: false, byteLimit: 100))
        XCTAssertThrowsError(try WardrobeSpeech.reviewed("   ", baseline: "", current: "", owner: true, byteLimit: 100))
        XCTAssertThrowsError(try WardrobeSpeech.reviewed("éé", baseline: "", current: "", owner: true, byteLimit: 3))
    }
    func testReuseMakesNewPlanWithExplicitReplacementAndNewRequestIdentity() throws {
        let historical = try fixture("history", as: WardrobePage<WardrobeOutfit>.self).items[0]
        let original = try changing(historical, ["occasion": "Dinner", "notes": "Notes about that wear", "source": "suggestion"])
        let item = original.items[0]
        let review = WardrobeReuseReview(outfit: original, pieces: [WardrobeReusePiece(id: item.garmentID, name: "Archived dress", role: item.role, problem: "Archived")])
        let date = try XCTUnwrap(WardrobeDraftValidation.date("2026-10-20"))
        XCTAssertThrowsError(try review.plan(date: date, replacements: [:], omitted: []))
        XCTAssertThrowsError(try review.plan(date: date, replacements: [:], omitted: [item.garmentID]))
        XCTAssertThrowsError(try review.plan(date: date, replacements: [extraID: WardrobeSelection(id: extraID, name: "New", role: "base")], omitted: []))
        let plan = try review.plan(date: date, replacements: [item.garmentID: WardrobeSelection(id: extraID, name: "Ready dress", role: "base")], omitted: [])
        XCTAssertEqual(plan.items[0].role, item.role); XCTAssertEqual(plan.items[0].id, extraID)
        XCTAssertEqual(plan.state, "planned"); XCTAssertEqual(plan.source, "manual"); XCTAssertEqual(plan.notes, "")
        XCTAssertEqual(WardrobeVocabulary.dayKey(plan.date), "2026-10-20"); XCTAssertEqual(plan.timeZone, TimeZone.current.identifier)
        XCTAssertEqual(plan.occasion, "Dinner"); XCTAssertEqual(original.state, "worn"); XCTAssertEqual(original.items[0].snapshot, historical.items[0].snapshot)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .ok(true) })
        let entity = UUID().uuidString.lowercased()
        var fields = try plan.fields(); fields["id"] = entity; fields["state"] = plan.state; fields["source"] = plan.source
        try queue.enqueue(operation: "outfits_create", entity: entity, title: "Reused plan", fields: fields)
        XCTAssertNotEqual(queue.items[0].entity, original.id)
        let body = try queue.items[0].createFields()
        XCTAssertEqual(body["state"] as? String, "planned"); XCTAssertEqual(body["source"] as? String, "manual")
        XCTAssertEqual(body["id"] as? String, entity); XCTAssertNil(body["confirmed_at"])
        let repeated = WardrobeReuseReview(outfit: original, pieces: [review.pieces[0], WardrobeReusePiece(id: extraID, name: "Other", role: "feet", problem: nil)])
        XCTAssertThrowsError(try repeated.plan(date: date, replacements: [item.garmentID: WardrobeSelection(id: extraID, name: "Same", role: "base")], omitted: []))
    }
    func testComparisonUsesActualPiecesAndRejectsForgedOrMissingDrafts() throws {
        let query = WardrobeSuggestQuery(day: "2026-10-07")
        let first = try fixture("suggestions", as: WardrobeSuggestions.self).items[0]
        let second = WardrobeSuggestion(items: first.items + [WardrobeSuggestedItem(garmentID: extraID, role: "feet", version: 2)], fingerprint: "another-real-option", reasons: ["Footwear included"], missingRoles: [])
        func draft(_ option: WardrobeSuggestion) -> WardrobeOutfitDraft {
            var result = WardrobeOutfitDraft(date: WardrobeDraftValidation.date(query.day)!)
            result.source = "suggestion"; result.items = option.items.map { WardrobeSelection(id: $0.garmentID, name: "Actual piece", role: $0.role) }
            return result
        }
        let drafts = [first.id: draft(first), second.id: draft(second)]
        let comparison = try WardrobeComparison(query: query, options: [first, second], drafts: drafts)
        XCTAssertEqual(comparison.sharedIDs, Set(first.items.map(\.garmentID)))
        XCTAssertEqual(comparison.candidates[1].option.reasons, second.reasons)
        XCTAssertEqual(comparison.candidates[1].draft.items.filter { !comparison.sharedIDs.contains($0.id) }.map(\.id), [extraID])
        XCTAssertThrowsError(try WardrobeComparison(query: query, options: [first, first], drafts: drafts))
        XCTAssertThrowsError(try WardrobeComparison(query: query, options: [first, second], drafts: [first.id: draft(first)]))
        var forged = draft(second); forged.items[0].role = "base"
        XCTAssertThrowsError(try WardrobeComparison(query: query, options: [first, second], drafts: [first.id: draft(first), second.id: forged]))
        forged = draft(second); forged.items[0] = WardrobeSelection(id: UUID().uuidString, name: "Invented", role: "one_piece")
        XCTAssertThrowsError(try WardrobeComparison(query: query, options: [first, second], drafts: [first.id: draft(first), second.id: forged]))
    }
    func testReuseRefreshesLiveGarmentsAndDistinguishesMissingFromUnavailableService() async throws {
        let owner = "assistance-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); AssistanceProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistanceProtocol.self]
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://assistance.test/api/v1", session: URLSession(configuration: config)), currentUser: { owner }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        let outfit = try fixture("history", as: WardrobePage<WardrobeOutfit>.self).items[0]
        let garment = try fixture("inventory", as: WardrobePage<WardrobeGarment>.self).items[0]
        let originalBytes = try JSONEncoder().encode(WardrobeOutfitResult(outfit: outfit))
        var garmentBytes = try JSONEncoder().encode(WardrobeGarmentResult(garment: garment)), status = 200
        AssistanceProtocol.handle = { request in
            if request.request.url?.lastPathComponent == "outfits_get" { request.finish(200, originalBytes) }
            else { request.finish(status, garmentBytes) }
        }
        let fresh = try await store.reuseOutfit(outfit.id)
        XCTAssertEqual(fresh.pieces[0].name, garment.name); XCTAssertNil(fresh.pieces[0].problem)
        XCTAssertEqual(fresh.outfit, outfit); XCTAssertNotEqual(fresh.pieces[0].name, outfit.items[0].snapshot?.name)
        let plan = try fresh.plan(date: Date(), replacements: [:], omitted: [])
        let archived = try changing(garment, ["archived_at": "2026-10-08T00:00:00Z"])
        garmentBytes = try JSONEncoder().encode(WardrobeGarmentResult(garment: archived))
        let blocked = try await store.reuseOutfit(outfit.id)
        XCTAssertEqual(blocked.pieces[0].problem, "Archived")
        do { _ = try await store.refreshReusePlan(plan); XCTFail("An archived piece cannot seed a plan") } catch { }
        status = 404; garmentBytes = Data(#"{"error":{"code":"not_found","message":"Missing garment"}}"#.utf8)
        let missing = try await store.reuseOutfit(outfit.id)
        XCTAssertEqual(missing.pieces[0].name, outfit.items[0].snapshot?.name); XCTAssertNotNil(missing.pieces[0].problem)
        status = 503
        do { _ = try await store.reuseOutfit(outfit.id); XCTFail("Service failure cannot be treated as a missing piece") } catch { }
    }
    func testAccountSwitchDuringReuseRejectsLateResult() async throws {
        let owner = "assistance-\(UUID().uuidString)"; var currentOwner = owner
        defer { DiskCache(owner: owner).wipeCaches(); AssistanceProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AssistanceProtocol.self]
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://assistance.test/api/v1", session: URLSession(configuration: config)), currentUser: { currentOwner }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        let outfit = try fixture("history", as: WardrobePage<WardrobeOutfit>.self).items[0]
        let bytes = try JSONEncoder().encode(WardrobeOutfitResult(outfit: outfit))
        AssistanceProtocol.handle = { request in Task { @MainActor in currentOwner = "other"; request.finish(200, bytes) } }
        do { _ = try await store.reuseOutfit(outfit.id); XCTFail("An old account must not receive a reusable plan") } catch { }
        XCTAssertTrue(store.writes.items.isEmpty)
    }
}
private final class AssistanceProtocol: URLProtocol {
    static var handle: ((AssistanceProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(self) }
    override func stopLoading() {}
    func finish(_ status: Int, _ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
}
