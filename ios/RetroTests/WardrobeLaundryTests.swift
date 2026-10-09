import XCTest
@testable import Retro

@MainActor final class WardrobeLaundryTests: XCTestCase {
    private struct Fixture: Decodable { let preview: WardrobeLaundryPreview; let load: WardrobeLaundryLoad }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "laundry", withExtension: "json", subdirectory: "wardrobe"))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var preview = fields["preview"] as! [String: Any]
        preview["generated_at"] = ISO8601DateFormatter().string(from: Date())
        fields["preview"] = preview
        return try JSONDecoder().decode(Fixture.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func changed<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
        var fields = try WardrobeSettingFields.object(value); edit(&fields)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testGroupsKeepExactVersionsAndRejectBlockedMixedAndStaleSelections() throws {
        let f = try fixture(); try f.load.validate(); try f.preview.validate(f.preview.program)
        let piece = f.preview.groups[0].items[0]
        XCTAssertEqual(try f.preview.selections([piece.id])[0].expected_version, 9_007_199_254_740_993)
        XCTAssertThrowsError(try f.preview.selections([f.preview.blocked[0].id]))
        XCTAssertThrowsError(try f.preview.selections([piece.id, f.preview.blocked[0].id]))
        let stale = try changed(f.preview) { $0["generated_at"] = "2001-01-01T00:00:00Z" }
        XCTAssertNoThrow(try stale.validate(f.preview.program, cached: true))
        XCTAssertThrowsError(try stale.selections([piece.id]))
        let duplicate = try changed(f.preview) { fields in
            var groups = fields["groups"] as! [[String: Any]]; let items = groups[0]["items"] as! [[String: Any]]
            groups[0]["items"] = items + items; fields["groups"] = groups; fields["inventory_count"] = 3
        }
        XCTAssertThrowsError(try duplicate.validate(f.preview.program))
        let count = try changed(f.preview) { $0["inventory_count"] = 0 }
        XCTAssertThrowsError(try count.validate(f.preview.program))
    }
    func testProgrammeRequiresExplicitSettingsAndProgressHasItsOwnConfirmation() throws {
        var program = try fixture().preview.program
        program.temperature_c = 0; XCTAssertNoThrow(try program.validate())
        program.temperature_c = nil; XCTAssertThrowsError(try program.validate())
        program.method("hand"); XCTAssertEqual(program.cycle, "unknown"); XCTAssertNoThrow(try program.validate())
        program.method("dry_clean"); XCTAssertNil(program.temperature_c); XCTAssertEqual(program.drying, "professional"); XCTAssertNoThrow(try program.validate())
        let f = try fixture()
        XCTAssertEqual(f.load.state, "planned"); XCTAssertEqual(f.load.progressTitle, "Confirm washing started")
        let invalid = try changed(f.load) { $0["state"] = "completed" }
        XCTAssertThrowsError(try invalid.validate(), "completion requires actual dated progress, not a state label")
        let wrong = try changed(f.load) { fields in
            var items = fields["items"] as! [[String: Any]]; items[0]["garment_id"] = "44444444-4444-4444-8444-444444444444"; fields["items"] = items
        }
        XCTAssertThrowsError(try wrong.validate())
    }
    func testLostLoadSaveKeepsFrozenBodyAndMandatoryRecoveryFields() async throws {
        let f = try fixture(); let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "writes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { _, _ in .retry("lost acknowledgement") }
        var fields = try WardrobeLaundryDraft(f.load).fields(); fields["id"] = f.load.id
        try queue.enqueue(operation: "laundry_create", entity: f.load.id, title: f.load.name, fields: fields)
        let original = try XCTUnwrap(queue.items.first); _ = await queue.drain()
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { operation, body in
            XCTAssertEqual(operation, "laundry_create"); XCTAssertEqual(body, original.body); return .ok(true)
        }
        let request = try XCTUnwrap(restored.items.first)
        XCTAssertEqual(try WardrobeLaundryDraft(request: request).items[0].expected_version, f.load.items[0].expected_version)
        let replayed = await restored.drain(force: true); XCTAssertTrue(replayed)
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: original.body) as? [String: Any]); body.removeValue(forKey: "program")
        let malformed = WardrobePending(id: original.id, entity: original.entity, operation: original.operation, title: original.title,
            body: try JSONSerialization.data(withJSONObject: body), createdAt: original.createdAt)
        XCTAssertThrowsError(try WardrobeLaundryDraft(request: malformed), "a missing programme must not become the default cold wash")
        let update = WardrobeWrites(file: file.deletingLastPathComponent().appending(path: "edit.json"), stillOwner: { true }) { _, _ in .retry("offline") }
        var edit = WardrobeDraftValidation.edit(id: f.load.id, version: f.load.version); edit["patch"] = ["name": "Reviewed name"]
        try update.enqueue(operation: "laundry_update", entity: f.load.id, title: f.load.name, fields: edit)
        let pending = try XCTUnwrap(update.items.first)
        XCTAssertThrowsError(try WardrobeLaundryDraft(request: pending))
        XCTAssertEqual(try WardrobeLaundryDraft(request: pending, current: f.load).name, "Reviewed name")
    }
    func testRejectedGarmentEditDoesNotPreventActiveLoadProgress() async throws {
        let f = try fixture(); let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "writes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var sent: [String] = []
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { operation, _ in
            sent.append(operation)
            return operation == "garments_update" ? .failed(code: "conflict", message: "Finish or cancel the active load before editing this garment.") : .ok(true)
        }
        let piece = f.load.items[0]
        var edit = WardrobeDraftValidation.edit(id: piece.id, version: piece.expected_version)
        edit["patch"] = ["name": "Saved for after laundry"]
        try queue.enqueue(operation: "garments_update", entity: piece.id, title: piece.snapshot.name, fields: edit)
        try queue.enqueue(operation: "laundry_progress", entity: f.load.id, title: f.load.name, fields: WardrobeDraftValidation.edit(id: f.load.id, version: f.load.version))
        let progressed = await queue.drain(); XCTAssertTrue(progressed)
        XCTAssertEqual(sent, ["garments_update", "laundry_progress"])
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.entity, piece.id)
        XCTAssertEqual(queue.items.first?.rejected, true, "The garment edit stays available for explicit review after laundry.")
        XCTAssertFalse(queue.contains(f.load.id))
    }
}
