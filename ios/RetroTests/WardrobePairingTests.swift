import XCTest
@testable import Retro

@MainActor final class WardrobePairingTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func changed<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var fields = try WardrobeSettingFields.object(value); edit(&fields)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testExactVersionsAndSeparateDailyChoiceClear() throws {
        let day = try fixture("selected-day", as: WardrobeDay.self)
        let selection = try XCTUnwrap(day.selection); let plan = try XCTUnwrap(selection.outfit)
        let fields = try selection.fields(choosing: plan)
        XCTAssertEqual(fields["expected_version"] as? Int64, 9_007_199_254_740_993)
        XCTAssertEqual(fields["expected_outfit_version"] as? Int64, plan.version)
        XCTAssertEqual(fields["outfit_id"] as? String, plan.id)
        XCTAssertEqual(plan.state, "planned")
        let clear = try selection.fields(choosing: nil)
        XCTAssertTrue(clear["outfit_id"] is NSNull); XCTAssertNil(clear["expected_outfit_version"])
        XCTAssertEqual(selection.outfitID, plan.id, "composing a clear must not mutate the read or its plan")
        let old = try fixture("day", as: WardrobeDay.self); XCTAssertNil(old.selection)
        let worn = try changed(plan) { $0["state"] = "worn" }
        XCTAssertThrowsError(try selection.fields(choosing: worn))
        let moved = try changed(plan) { $0["day"] = "2026-10-10" }
        XCTAssertThrowsError(try selection.fields(choosing: moved))
        let invalid = try changed(selection) { $0["version"] = 0 }
        XCTAssertThrowsError(try invalid.fields(choosing: plan))
    }
    func testPairingsAllowMultipleManualRolesButNeedDifferentRealPieces() throws {
        let pairing = try fixture("pairings", as: WardrobePage<WardrobePairing>.self).items[0]
        try pairing.validate(); XCTAssertEqual(pairing.version, 9_007_199_254_740_993)
        var draft = WardrobePairingDraft(pairing)
        draft.items[0].role = "accessory"; draft.items[1].role = "accessory"
        XCTAssertNoThrow(try draft.fields())
        draft.items.append(draft.items[0]); XCTAssertThrowsError(try draft.fields())
        draft.items = Array(draft.items.prefix(1)); XCTAssertThrowsError(try draft.fields())
    }
    func testLostDailySaveRestoresFrozenVersionsAndRejectsMalformedRecovery() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "writes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let selection = try XCTUnwrap(fixture("selected-day", as: WardrobeDay.self).selection)
        let queue = WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .retry("lost reply") })
        try queue.enqueue(operation: "wardrobe_day_selection_update", entity: selection.id, title: "Daily choice", fields: selection.fields(choosing: selection.outfit))
        let original = try XCTUnwrap(queue.items.first)
        _ = await queue.drain()
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { operation, body in
            XCTAssertEqual(operation, original.operation); XCTAssertEqual(body, original.body); return .ok(true)
        }
        let request = try WardrobeDayChoiceRequest(request: XCTUnwrap(restored.items.first))
        XCTAssertEqual(request.outfitID, selection.outfitID); XCTAssertEqual(request.day, selection.day)
        let replayed = await restored.drain(force: true); XCTAssertTrue(replayed)
        let malformed = WardrobePending(id: original.id, entity: original.entity, operation: original.operation, title: original.title,
            body: Data("{}".utf8), createdAt: original.createdAt)
        XCTAssertThrowsError(try WardrobeDayChoiceRequest(request: malformed), "missing outfit identity must not become a clear")
    }
    func testPlanningRefreshesPairingAndPiecesWithoutSavingOrRecordingWear() async throws {
        let owner = "pairings-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); PairingProtocol.handle = nil }
        let pairing = try fixture("pairings", as: WardrobePage<WardrobePairing>.self).items[0]
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PairingProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://pairings.test/api/v1", session: session), currentUser: { owner }, token: { _ in "token" })
        let store = WardrobeStore(engine: engine)
        let revised = try changed(pairing) { $0["version"] = 2 }
        let garments = try pairing.items.map { try XCTUnwrap($0.snapshot) }
        let washing = try garments.map { try changed($0) { $0["availability"] = "washing" } }
        var operations: [String] = []; var index = 0; var stale = false; var unavailable = false
        PairingProtocol.handle = { request in
            let op = request.url!.lastPathComponent; operations.append(op)
            if op == "pairings_get" {
                let current = stale ? revised : pairing
                return (200, try JSONEncoder().encode(WardrobePairingResult(pairing: current)))
            }
            let current = unavailable ? washing[index] : garments[index]; index += 1
            return (200, try JSONEncoder().encode(WardrobeGarmentResult(garment: current)))
        }
        let plan = try await store.planPairing(pairing, date: Date())
        XCTAssertEqual(plan.state, "planned"); XCTAssertEqual(plan.label, pairing.name)
        XCTAssertEqual(operations, ["pairings_get", "garments_get", "garments_get"]); XCTAssertTrue(store.writes.items.isEmpty)
        operations = []; index = 0; stale = true
        do { _ = try await store.planPairing(pairing, date: Date()); XCTFail("stale pairing") } catch {}
        XCTAssertEqual(operations, ["pairings_get"])
        operations = []; index = 0; stale = false; unavailable = true
        do { _ = try await store.planPairing(pairing, date: Date()); XCTFail("unavailable piece") } catch {}
        XCTAssertTrue(store.writes.items.isEmpty)
    }
    func testEngineQueueDecodesBothNewWriteResults() async throws {
        let owner = "pairing-writes-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); PairingProtocol.handle = nil }
        let pairing = try fixture("pairings", as: WardrobePage<WardrobePairing>.self).items[0]
        let selection = try XCTUnwrap(fixture("selected-day", as: WardrobeDay.self).selection)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PairingProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let engine = Engine(owner: owner, api: RetroAPI(baseURL: "https://pairings.test/api/v1", session: session), currentUser: { owner }, token: { _ in "token" })
        PairingProtocol.handle = { request in
            if request.url!.lastPathComponent == "pairings_create" { return (200, try JSONEncoder().encode(WardrobePairingResult(pairing: pairing))) }
            return (200, try JSONEncoder().encode(WardrobeDaySelectionResult(selection: selection)))
        }
        let writes = WardrobeWrites(engine: engine)
        var fields = try WardrobePairingDraft(pairing).fields(); fields["id"] = pairing.id
        try writes.enqueue(operation: "pairings_create", entity: pairing.id, title: pairing.name, fields: fields)
        try writes.enqueue(operation: "wardrobe_day_selection_update", entity: selection.id, title: "Daily choice", fields: selection.fields(choosing: selection.outfit))
        let acknowledged = await writes.drain(); XCTAssertTrue(acknowledged); XCTAssertTrue(writes.items.isEmpty)
    }
}

private final class PairingProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handle = Self.handle else { throw URLError(.badServerResponse) }
            let (status, data) = try handle(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
