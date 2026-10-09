import XCTest
@testable import Retro

@MainActor final class WardrobeWriteTests: XCTestCase {
    private func file() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "pending.json") }
    private let entity = "11111111-1111-4111-8111-111111111111"

    func testLostResponseRelaunchReusesFrozenPayloadAndRejectsStaleDiscard() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var firstBody: Data?
        let first = WardrobeWrites(file: file, stillOwner: { true }) { _, body in firstBody = body; return .retry("lost response") }
        try first.enqueue(operation: "garments_create", entity: entity, title: "Shirt", fields: ["id": entity, "name": "Shirt", "category": "top"])
        let staleUnsent = try XCTUnwrap(first.items.first)
        let failed = await first.drain()
        XCTAssertFalse(failed)
        XCTAssertThrowsError(try first.remove(staleUnsent))
        var replayBody: Data?
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { _, body in replayBody = body; return .ok(true) }
        XCTAssertTrue(restored.items[0].dispatched)
        let acknowledged = await restored.drain(force: true)
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(firstBody, replayBody)
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertTrue(WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) }).items.isEmpty)
    }

    func testPersistenceFailureDoesNotAcceptOrSendRequest() async {
        var sends = 0
        let queue = WardrobeWrites(file: file(), stillOwner: { true }, save: { _ in throw WardrobeWriteError("disk full") }) { _, _ in sends += 1; return .ok(true) }
        XCTAssertThrowsError(try queue.enqueue(operation: "garments_create", entity: entity, title: "Shirt", fields: ["id": entity]))
        XCTAssertTrue(queue.items.isEmpty)
        let changed = await queue.drain()
        XCTAssertFalse(changed)
        XCTAssertEqual(sends, 0)
    }

    func testAckPersistenceFailureRetainsOriginalRequestForReconciliation() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var saves = 0
        let queue = WardrobeWrites(file: file, stillOwner: { true }, save: { items in
            saves += 1
            if saves == 3 { throw WardrobeWriteError("disk full after acknowledgement") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
        }) { _, _ in .ok(true) }
        try queue.enqueue(operation: "garments_update", entity: entity, title: "Shirt", fields: ["id": entity, "expected_version": Int64(9007199254740993), "patch": ["name": "Shirt"]])
        let body = queue.items[0].body
        let changed = await queue.drain()
        XCTAssertFalse(changed)
        XCTAssertNotNil(queue.problem)
        let restored = WardrobeWrites(file: file, stillOwner: { true }) { _, replay in XCTAssertEqual(replay, body); return .ok(true) }
        XCTAssertEqual(restored.items[0].body, body)
        let replayed = await restored.drain(force: true)
        XCTAssertTrue(replayed)
    }

    func testConflictRequiresReviewAndDoesNotBlockUnrelatedRecord() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { op, _ in op == "garments_update" ? .failed(code: "conflict", message: "Version changed") : .ok(true) }
        try queue.enqueue(operation: "garments_update", entity: entity, title: "Shirt", fields: ["id": entity, "expected_version": 1, "patch": ["name": "New shirt"]])
        XCTAssertThrowsError(try queue.enqueue(operation: "garments_archive", entity: entity, title: "Shirt", fields: ["id": entity]))
        try queue.enqueue(operation: "outfits_create", entity: "22222222-2222-4222-8222-222222222222", title: "Other", fields: [:])
        let changed = await queue.drain()
        XCTAssertTrue(changed)
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertTrue(queue.items[0].rejected)
        XCTAssertTrue(queue.items[0].requestedSummary.contains("New shirt"))
        try queue.remove(queue.items[0])
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testAccountSwitchAndCancellationRetainDispatchedRequests() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var owner = true
        var sends = 0
        let queue = WardrobeWrites(file: file, stillOwner: { owner }) { _, _ in sends += 1; owner = false; return .ok(true) }
        try queue.enqueue(operation: "garments_create", entity: entity, title: "Shirt", fields: [:])
        let changed = await queue.drain()
        XCTAssertFalse(changed)
        XCTAssertTrue(queue.items[0].dispatched)
        let noSend = await queue.drain()
        XCTAssertFalse(noSend)
        XCTAssertEqual(sends, 1)
        let cancelled = WardrobeWrites(file: file, stillOwner: { true }) { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }; return .ok(true)
        }
        let task = Task { await cancelled.drain() }
        let cancelledResult = await task.value
        XCTAssertFalse(cancelledResult)
        XCTAssertTrue(cancelled.items[0].dispatched)
        XCTAssertFalse(cancelled.sending)
    }

    func testUnreadableQueueBlocksReplacement() throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: file)
        let queue = WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) })
        XCTAssertNotNil(queue.problem)
        XCTAssertThrowsError(try queue.enqueue(operation: "garments_create", entity: entity, title: "Shirt", fields: [:]))
        XCTAssertEqual(try String(contentsOf: file), "broken")
    }

    func testDraftValidationAndCorrectionPreserveUnchangedSnapshots() throws {
        var garment = WardrobeGarmentDraft()
        garment.name = String(repeating: "é", count: 51)
        XCTAssertThrowsError(try garment.fields())
        garment.name = "Shirt"; garment.colours = "blue, blue"
        XCTAssertThrowsError(try garment.fields())
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "day", withExtension: "json", subdirectory: "wardrobe"))
        let day = try JSONDecoder().decode(WardrobeDay.self, from: Data(contentsOf: url))
        var draft = WardrobeOutfitDraft(day.outfits[0])
        let original = try draft.fields()
        draft.label = "Corrected label"
        let patch = WardrobeDraftValidation.patch(try draft.fields(), original: original)
        XCTAssertEqual(patch.keys.sorted(), ["label"])
        draft.date = Date().addingTimeInterval(86400 * 3)
        XCTAssertThrowsError(try draft.fields())
        draft.state = "planned"
        XCTAssertNoThrow(try draft.fields())
        draft.items += draft.items
        XCTAssertThrowsError(try draft.fields())
    }
}
