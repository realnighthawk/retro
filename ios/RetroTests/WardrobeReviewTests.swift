import XCTest
@testable import Retro

@MainActor final class WardrobeReviewTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe")))
    }
    func testQueuedCreateFollowupKeepsOriginalIdentityAcrossRelaunchAndReconciliation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writesFile = root.appending(path: "writes.json"), draftsFile = root.appending(path: "drafts.json")
        let queue = WardrobeWrites(file: writesFile, stillOwner: { true }, send: { _, _ in .ok(true) })
        let garment = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory")).items[0]
        var fields = try WardrobeGarmentDraft(garment).fields(); fields["id"] = garment.id
        try queue.enqueue(operation: "garments_create", entity: garment.id, title: garment.name, fields: fields)
        let original = queue.items[0]
        var owner = true
        let drafts = WardrobeSavedDrafts(file: draftsFile, stillOwner: { owner })
        var entry = try drafts.follow(original)
        entry.garmentDraft?.notes = "Later offline edit"
        try drafts.put(entry)
        XCTAssertEqual(queue.items[0].body, original.body)
        XCTAssertEqual(try drafts.follow(original).id, entry.id)
        XCTAssertNil(drafts.garment(nil), "A fresh Add must not reopen a queued create's followup")
        let restored = WardrobeSavedDrafts(file: draftsFile, stillOwner: { true })
        let value = try XCTUnwrap(restored.items.first)
        XCTAssertEqual(value.entityID, garment.id); XCTAssertEqual(value.dependency?.id, original.id)
        XCTAssertEqual(value.dependency?.body, original.body)
        XCTAssertNil(value.garment, "No server version is invented for an unacknowledged create")
        let patch = WardrobeDraftValidation.patch(try XCTUnwrap(value.garmentDraft).fields(), original: try value.originalGarment().fields())
        XCTAssertEqual(patch.keys.sorted(), ["notes"])
        owner = false; XCTAssertThrowsError(try drafts.follow(original))
        try queue.remove(original)
        var createdKeys: Set<String> = []
        let replay = WardrobeWrites(file: writesFile, stillOwner: { true }) { operation, body in
            XCTAssertEqual(operation, original.operation); XCTAssertEqual(body, original.body)
            createdKeys.insert(original.id); return .ok(true)
        }
        try replay.restoreCreate(try XCTUnwrap(value.dependency))
        XCTAssertTrue(replay.items[0].dispatched)
        XCTAssertThrowsError(try replay.remove(replay.items[0]))
        _ = await replay.drain(force: true)
        try replay.restoreCreate(original); _ = await replay.drain(force: true)
        XCTAssertEqual(createdKeys.count, 1); XCTAssertTrue(replay.items.isEmpty)
        XCTAssertEqual(restored.items[0].garmentDraft?.notes, "Later offline edit")
    }

    func testQueuedOutfitFollowupRetainsStateSourceAndRejectedCreateUsesNewKey() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = WardrobeWrites(file: root.appending(path: "writes.json"), stillOwner: { true }, send: { _, _ in .failed(code: "invalid_input", message: "Review details") })
        let entity = UUID().uuidString.lowercased(), garmentID = "11111111-1111-4111-8111-111111111111"
        var originalDraft = WardrobeOutfitDraft(date: try XCTUnwrap(WardrobeDraftValidation.date("2026-10-07")))
        originalDraft.timeZone = "UTC"; originalDraft.state = "worn"; originalDraft.source = "suggestion"
        originalDraft.items = [WardrobeSelection(id: garmentID, name: "Dress", role: "one_piece")]
        var fields = try originalDraft.fields(); fields["id"] = entity; fields["state"] = originalDraft.state; fields["source"] = originalDraft.source
        try queue.enqueue(operation: "outfits_create", entity: entity, title: "Outfit", fields: fields)
        let original = queue.items[0]
        let drafts = WardrobeSavedDrafts(file: root.appending(path: "drafts.json"), stillOwner: { true })
        var value = try drafts.follow(original)
        XCTAssertEqual(value.outfitDraft?.state, "worn"); XCTAssertEqual(value.outfitDraft?.source, "suggestion")
        value.outfitDraft?.notes = "Corrected notes"; try drafts.put(value)
        XCTAssertNil(drafts.outfit(nil, confirming: false))
        let patch = WardrobeDraftValidation.patch(try XCTUnwrap(value.outfitDraft).fields(), original: try value.originalOutfit().fields())
        XCTAssertEqual(patch.keys.sorted(), ["notes"])
        XCTAssertThrowsError(try queue.replaceRejected(original.id, operation: "outfits_create", fields: fields))
        _ = await queue.drain()
        fields["notes"] = "Corrected notes"
        try queue.replaceRejected(original.id, operation: "outfits_create", fields: fields)
        XCTAssertNotEqual(queue.items[0].id, original.id); XCTAssertEqual(queue.items[0].entity, entity)
        let replacement = try queue.items[0].createFields()
        XCTAssertEqual(replacement["state"] as? String, "worn"); XCTAssertEqual(replacement["source"] as? String, "suggestion")
        XCTAssertEqual(replacement["notes"] as? String, "Corrected notes")
        XCTAssertEqual(value.dependency?.body, original.body)
        let damaged = WardrobeSavedDraft(id: value.id, entityID: UUID().uuidString.lowercased(), garment: nil, outfit: nil, confirming: false, garmentDraft: nil, outfitDraft: value.outfitDraft, dependency: original)
        XCTAssertThrowsError(try drafts.put(damaged))
        XCTAssertEqual(drafts.items[0].entityID, entity)
    }

    func testSuggestionAnalysisAuditAndFiltersMatchWireContract() throws {
        let suggestions = try JSONDecoder().decode(WardrobeSuggestions.self, from: fixture("suggestions"))
        XCTAssertEqual(suggestions.items[0].items[0].version, 9007199254740993)
        XCTAssertEqual(suggestions.items[0].missingRoles, ["feet"])
        let analysis = try JSONDecoder().decode(WardrobeAnalysis.self, from: fixture("analysis"))
        XCTAssertEqual(analysis.wearDays, 1); XCTAssertEqual(analysis.outfitEvents, 2)
        let audit = try JSONDecoder().decode(WardrobePage<WardrobeChange>.self, from: fixture("audit"))
        XCTAssertEqual(audit.items[0].id, 9007199254740993)
        XCTAssertTrue(audit.items[0].details.contains("9007199254740993"))
        let query = WardrobeHistoryQuery(from: "2026-10-01", to: "2026-10-07", garmentID: suggestions.items[0].items[0].garmentID)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        XCTAssertEqual(fields["garment_id"] as? String, query.garmentID)
        XCTAssertEqual(fields["from"] as? String, query.from)
        XCTAssertNil(WardrobeDraftValidation.date("2026-1-7"))
        XCTAssertNil(WardrobeDraftValidation.date("2026-02-30"))
        var input = WardrobeSuggestQuery(day: "2026-10-07")
        let id = suggestions.items[0].items[0].garmentID
        input.requiredIDs = [id]; input.excludedIDs = [id]
        XCTAssertThrowsError(try input.validate())
    }
    func testDraftRelaunchKeepsEntityBaselineAndUnsentEditsAndFencesOwner() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "drafts.json")
        var owner = true
        let drafts = WardrobeSavedDrafts(file: file, stillOwner: { owner })
        let garment = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory")).items[0]
        var edited = WardrobeGarmentDraft(garment); edited.notes = "Unsaved after pending edit"
        let entry = WardrobeSavedDraft(id: UUID().uuidString.lowercased(), entityID: garment.id, garment: garment, outfit: nil, confirming: false, garmentDraft: edited, outfitDraft: nil)
        try drafts.put(entry)
        let restored = WardrobeSavedDrafts(file: file, stillOwner: { true })
        XCTAssertEqual(restored.items[0].garment?.version, 9007199254740993)
        XCTAssertEqual(restored.items[0].garmentDraft, edited)
        XCTAssertEqual(restored.items[0].entityID, garment.id)
        owner = false
        XCTAssertThrowsError(try drafts.remove(entry.id))
        XCTAssertThrowsError(try drafts.put(entry))
        try Data("damaged".utf8).write(to: file)
        let damaged = WardrobeSavedDrafts(file: file, stillOwner: { true })
        XCTAssertNotNil(damaged.problem)
        XCTAssertThrowsError(try damaged.put(entry))
        XCTAssertEqual(try String(contentsOf: file), "damaged")
    }
    func testReviewedReplacementIsAtomicUsesNewIdentityAndCannotReplaceUncertainWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "writes.json")
        var refuseStorage = false
        let queue = WardrobeWrites(file: file, stillOwner: { true }, save: { values in
            if refuseStorage { throw WardrobeWriteError("disk full") }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: file, options: .atomic)
        }, send: { _, _ in .failed(code: "conflict", message: "changed") })
        let entity = "11111111-1111-4111-8111-111111111111"
        try queue.enqueue(operation: "garments_update", entity: entity, title: "Edit", fields: ["id": entity, "expected_version": 1, "patch": ["notes": "requested"]])
        let original = queue.items[0]
        let fields: [String: Any] = ["id": entity, "expected_version": Int64(9007199254740993), "patch": ["notes": "reviewed"]]
        XCTAssertThrowsError(try queue.replaceRejected(original.id, operation: "garments_update", fields: fields))
        _ = await queue.drain()
        refuseStorage = true
        XCTAssertThrowsError(try queue.replaceRejected(original.id, operation: "garments_update", fields: fields))
        XCTAssertEqual(queue.items[0].body, original.body)
        XCTAssertTrue(queue.items[0].rejected)
        refuseStorage = false
        try queue.replaceRejected(original.id, operation: "garments_update", fields: fields)
        XCTAssertNotEqual(queue.items[0].id, original.id)
        XCTAssertFalse(queue.items[0].dispatched); XCTAssertFalse(queue.items[0].rejected)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: queue.items[0].body) as? [String: Any])
        XCTAssertEqual((body["expected_version"] as? NSNumber)?.int64Value, 9007199254740993)
        XCTAssertEqual(WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) }).items[0].body, queue.items[0].body)
    }
    func testSuggestionsRefreshExactPiecesAndRejectChangedVersions() async throws {
        let owner = "review-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); ReviewProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReviewProtocol.self]
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://review.test/api/v1", session: URLSession(configuration: config)), currentUser: { owner }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        let page = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory"))
        let bytes = try JSONEncoder().encode(WardrobeGarmentResult(garment: page.items[0]))
        ReviewProtocol.handle = { $0.finish(200, bytes) }
        let suggestion = try JSONDecoder().decode(WardrobeSuggestions.self, from: fixture("suggestions")).items[0]
        let input = WardrobeSuggestQuery(day: "2026-10-07")
        let draft = try await store.reviewSuggestion(suggestion, query: input)
        XCTAssertEqual(draft.items[0].name, page.items[0].name)
        XCTAssertEqual(draft.source, "suggestion"); XCTAssertEqual(draft.state, "planned")
        let stale = WardrobeSuggestion(items: [WardrobeSuggestedItem(garmentID: page.items[0].id, role: "one_piece", version: 1)], fingerprint: suggestion.fingerprint, reasons: [], missingRoles: [])
        do { _ = try await store.reviewSuggestion(stale, query: input); XCTFail("Changed piece must require regeneration") } catch { }
    }
    func testAutomaticRetryCooldownSurvivesRelaunchWithoutChangingPayload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "writes.json")
        var calls = 0
        let first = WardrobeWrites(file: file, stillOwner: { true }) { _, _ in calls += 1; return .retry("offline") }
        try first.enqueue(operation: "garments_create", entity: "11111111-1111-4111-8111-111111111111", title: "Draft", fields: [:])
        let body = first.items[0].body
        _ = await first.drain()
        XCTAssertNotNil(first.items[0].retryAfter)
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { _, payload in calls += 1; XCTAssertEqual(payload, body); return .ok(true) }
        _ = await restored.drain()
        XCTAssertEqual(calls, 1)
        _ = await restored.drain(force: true)
        XCTAssertEqual(calls, 2); XCTAssertTrue(restored.items.isEmpty)
    }
}
private final class ReviewProtocol: URLProtocol {
    static var handle: ((ReviewProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(self) }
    override func stopLoading() {}
    func finish(_ status: Int, _ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
}
