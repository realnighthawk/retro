import XCTest
@testable import Retro

@MainActor final class WardrobeBatchTests: XCTestCase {
    private func garment(_ index: Int, availability: String = "ready", archived: Bool = false, favourite: Bool = false) -> WardrobeBatchItem {
        WardrobeGarment(id: "00000000-0000-4000-8000-\(String(format: "%012d", index))", version: Int64(index + 1), name: "Piece \(index)", category: "top",
                        availability: availability, subtype: nil, colours: nil, warmth: nil, seasons: nil, formality: nil, material: nil, brand: nil,
                        pattern: nil, style: nil, fit: nil, notes: nil, favourite: favourite, mediaIDs: nil,
                        archivedAt: archived ? "2026-01-01T00:00:00Z" : nil, createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z",
                        wearDays: 0, wearEvents: 0, lastWornOn: nil).batchItem
    }

    func testPlanLeavesOutNoOpsPendingRecordsAndReservedRoom() {
        let selected = [garment(0), garment(1, availability: "needs_wash"), garment(2, archived: true), garment(3), garment(4)]
        let plan = WardrobeBatchPlan.build(action: .available, selected: selected, pending: [selected[3].id], pendingCount: 0)
        XCTAssertEqual(plan.items.map(\.name), ["Piece 0", "Piece 4"])
        XCTAssertEqual(plan.skipped.count, 3)
        XCTAssertTrue(plan.skipped.contains { $0.hasPrefix("Piece 1") && $0.contains("already available") })
        XCTAssertTrue(plan.skipped.contains { $0.hasPrefix("Piece 2") && $0.contains("restore it first") })
        XCTAssertTrue(plan.skipped.contains { $0.hasPrefix("Piece 3") && $0.contains("pending save") })
        // Restoring only ever offers archived garments, and only when there is room in the queue.
        let restore = WardrobeBatchPlan.build(action: .restore, selected: [garment(0), garment(2, archived: true)], pending: [], pendingCount: 0)
        XCTAssertEqual(restore.items.map(\.name), ["Piece 2"])
        XCTAssertEqual(restore.skipped, ["Piece 0: is not archived"])
        let full = WardrobeBatchPlan.build(action: .available, selected: [garment(0), garment(4)], pending: [], pendingCount: 99)
        XCTAssertEqual(full.items.count, 1)
        XCTAssertTrue(full.skipped.contains { $0.contains("pending saves are full") })
        XCTAssertEqual(WardrobeBatchPlan.build(action: .favourite, selected: [garment(0, favourite: true)], pending: [], pendingCount: 0).skipped,
                       ["Piece 0: is already a favourite"])
    }

    func testEachItemFreezesItsOwnVersionAndChange() {
        let item = garment(7, availability: "needs_wash")
        let plan = WardrobeBatchPlan.build(action: .available, selected: [item], pending: [], pendingCount: 0)
        var fields = plan.fields(item)
        XCTAssertEqual(fields["id"] as? String, item.id)
        XCTAssertEqual(fields["expected_version"] as? Int64, item.version)
        XCTAssertEqual((fields["patch"] as? [String: Any])?["availability"] as? String, "ready")
        XCTAssertEqual(plan.action.operation, "garments_update")
        fields["patch"] = ["availability": "unavailable"]
        XCTAssertEqual((plan.fields(item)["patch"] as? [String: Any])?["availability"] as? String, "ready", "The frozen intent cannot be edited afterwards")
        let archive = WardrobeBatchPlan.build(action: .archive, selected: [garment(1)], pending: [], pendingCount: 0)
        XCTAssertNil(archive.fields(garment(1))["patch"], "Archive and restore carry no patch")
        XCTAssertEqual(archive.action.operation, "garments_archive")
        XCTAssertTrue(archive.action.isDestructive)
        XCTAssertEqual(archive.summary, "1 garment will be queued as one frozen request, each with the version it was reviewed at.")
    }

    func testBatchQueuesOneFrozenRequestPerItemAndNeverDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "writes.json")
        var sent: [String] = []
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { _, body in
            let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            sent.append((fields?["id"] as? String) ?? "?")
            return .ok(true)
        }
        let selected = [garment(0), garment(1, availability: "needs_wash"), garment(2)]
        let plan = WardrobeBatchPlan.build(action: .needsWash, selected: selected, pending: [], pendingCount: 0)
        XCTAssertEqual(plan.items.count, 2)
        var queued: [String] = []
        for item in plan.items { try queue.enqueue(operation: plan.action.operation, entity: item.id, title: item.name, fields: plan.fields(item)) }
        queued = plan.items.map(\.id)
        XCTAssertEqual(queue.items.count, 2, "One frozen request per selected garment")
        XCTAssertEqual(Set(queue.items.map(\.entity)), Set(queued))
        XCTAssertEqual(queue.items.map(\.body.count).filter { $0 > 0 }.count, 2)
        // A second run over the same items is refused per item: no duplicate intent, no missing record.
        var refused: [String] = []
        for item in plan.items {
            do { try queue.enqueue(operation: plan.action.operation, entity: item.id, title: item.name, fields: plan.fields(item)) }
            catch { refused.append(item.name) }
        }
        XCTAssertEqual(refused.count, 2)
        XCTAssertEqual(queue.items.count, 2)
        _ = await queue.drain(force: true)
        XCTAssertEqual(Set(sent), Set(queued))
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testPartialResultsReportPerItemAndSurviveRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "writes.json")
        let good = garment(0, availability: "needs_wash"), bad = garment(1, availability: "needs_wash"), offline = garment(2, availability: "needs_wash")
        let plan = WardrobeBatchPlan.build(action: .available, selected: [good, bad, offline], pending: [], pendingCount: 0)
        let queue = WardrobeWrites(file: file, stillOwner: { true }) { _, body in
            let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            switch fields?["id"] as? String {
            case good.id: return .ok(true)
            case bad.id: return .failed(code: "conflict", message: "Stale version: someone changed this garment.")
            default: return .failed(code: nil, message: "Offline")
            }
        }
        for item in plan.items { try queue.enqueue(operation: plan.action.operation, entity: item.id, title: item.name, fields: plan.fields(item)) }
        _ = await queue.drain()
        let queued = Set(plan.items.map(\.id))
        XCTAssertEqual(WardrobeBatchReport.outcome(good.id, pending: queue.items, acknowledged: queue.acknowledgedIDs, queued: queued), .acknowledged)
        guard case .rejected(let message) = WardrobeBatchReport.outcome(bad.id, pending: queue.items, acknowledged: queue.acknowledgedIDs, queued: queued) else {
            XCTFail("A refused item must report its own reason"); return
        }
        XCTAssertTrue(message.contains("Stale version"))
        XCTAssertEqual(WardrobeBatchReport.outcome(offline.id, pending: queue.items, acknowledged: queue.acknowledgedIDs, queued: queued), .retrying)
        XCTAssertEqual(WardrobeBatchReport.outcome("00000000-0000-4000-8000-000000000099", pending: queue.items, acknowledged: queue.acknowledgedIDs, queued: queued), .unknown)
        XCTAssertFalse(WardrobeBatchOutcome.retrying.isFailure, "Still queued is never a failure or a success")
        // Relaunch keeps the refused and retrying items with their original identities.
        let reopened = WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) })
        XCTAssertEqual(Set(reopened.items.map(\.id)), Set(queue.items.map(\.id)))
        XCTAssertEqual(reopened.items.first { $0.entity == bad.id }?.rejected, true)
        XCTAssertNil(reopened.items.first { $0.entity == good.id })
        // A signed-out client cannot send, so no outcome may be reported as saved.
        let offlineOwner = WardrobeWrites(file: file, stillOwner: { false }, send: { _, _ in .ok(true) })
        _ = await offlineOwner.drain(force: true)
        XCTAssertEqual(offlineOwner.items.count, 2)
        XCTAssertTrue(offlineOwner.acknowledgedIDs.isEmpty)
    }
}

private extension WardrobeGarment {
    var batchItem: WardrobeBatchItem { WardrobeBatchItem(self) }
}
