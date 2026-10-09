import XCTest
@testable import Retro

/// The client's own logic: status classification, error shapes, and the two-tier file store. The engine's domain rules
/// are not tested here because they do not live here.
final class ApiTests: XCTestCase {
    private struct Nothing: Decodable {}

    private func classify(_ code: Int, _ body: String) -> Api<Nothing> {
        RetroAPI.classify(code, Data(body.utf8))
    }

    func testSuccessDecodes() {
        struct Row: Decodable { let kept: Int }
        let result: Api<Row> = RetroAPI.classify(200, Data(#"{"kept":3}"#.utf8))
        guard case .ok(let row) = result else { return XCTFail("expected ok, got \(result)") }
        XCTAssertEqual(row.kept, 3)
    }

    func testAuthAndProvisioningAreDistinct() {
        guard case .unauthorized = classify(401, "{}") else { return XCTFail("401 should be unauthorized") }
        guard case .unauthorized = classify(403, "{}") else { return XCTFail("403 should be unauthorized") }
        // A 404 is only "not provisioned" when the router says so; any other 404 is a real failure.
        guard case .notProvisioned = classify(404, #"{"error":"no_tenant"}"#) else {
            return XCTFail("404 no_tenant should be notProvisioned")
        }
        guard case .failed = classify(404, #"{"error":{"code":"not_found","message":"gone"}}"#) else {
            return XCTFail("a plain 404 should be a failure")
        }
    }

    func testTransientAndPermanentFailuresSeparate() {
        for code in [408, 429, 502, 503, 504] {
            guard case .retry = classify(code, "{}") else { return XCTFail("\(code) should be retryable") }
        }
        guard case .serverError = classify(500, "{}") else { return XCTFail("500 should be serverError") }
        guard case .retry = classify(200, "not json") else { return XCTFail("unreadable 200 should be retryable") }
    }

    func testBothErrorShapesAreRead() {
        let engine = RetroAPI.errorOf(Data(#"{"error":{"code":"conflict","message":"already there"}}"#.utf8))
        XCTAssertEqual(engine.code, "conflict")
        XCTAssertEqual(engine.message, "already there")

        let router = RetroAPI.errorOf(Data(#"{"error":"no route"}"#.utf8))
        XCTAssertNil(router.code)
        XCTAssertEqual(router.message, "no route")

        let nothing = RetroAPI.errorOf(Data("{}".utf8))
        XCTAssertNil(nothing.code)
        XCTAssertNil(nothing.message)
    }
}

/// Two accounts on one phone must never see each other's days.
@MainActor
final class EngineIsolationTests: XCTestCase {
    private struct In: Encodable { let n = 1 }
    private struct Out: Decodable { let n: Int }

    func testACallForAnotherUserSendsNothing() async {
        var sent = 0
        let engine = Engine(owner: "A", api: RetroAPI(baseURL: "https://router.test/retro/api/v1")) {
            "B"
        } token: { _ in
            sent += 1
            return "token-for-B"
        }

        guard case .unauthorized = await engine.call("day_get", In()) as Api<Out> else {
            return XCTFail("a mismatched owner must fail as unauthorized")
        }
        XCTAssertEqual(sent, 0, "no token should have been fetched, let alone a request sent")
    }
}

final class DiskCacheTests: XCTestCase {
    private struct Row: Codable, Equatable { let kept: Int }

    func testRoundTripsWithinOneOwnersFolder() {
        let owner = "user-\(UUID().uuidString)"
        let cache = DiskCache(owner: owner)
        defer { cache.wipeCaches(); try? FileManager.default.removeItem(at: durableRoot(owner)) }

        cache.save(Row(kept: 3), as: "day", durable: true)
        XCTAssertEqual(cache.load(Row.self, "day", durable: true), Row(kept: 3))

        // The two tiers are separate stores: writing durably must not make it readable as a cache.
        XCTAssertNil(cache.load(Row.self, "day", durable: false))
    }

    func testAnUnsafeOwnerIdIsHashedRatherThanUsedAsAFolder() throws {
        // A path-shaped id must never land on disk as a literal path component.
        let cache = DiskCache(owner: "../../etc")
        cache.save(Row(kept: 1), as: "day", durable: true)
        defer { try? FileManager.default.removeItem(at: durableRoot("unused")) }

        let folders = try FileManager.default.contentsOfDirectory(atPath: durableRoot("unused").path)
        XCTAssertFalse(folders.contains("etc"), "the id must not become a folder name")
        XCTAssertFalse(folders.contains(".."), "the id must not become a path traversal")
        XCTAssertTrue(
            folders.contains { $0.count == 64 && $0.allSatisfy(\.isHexDigit) },
            "an unsafe id should be stored under its SHA-256"
        )
    }

    private func durableRoot(_ owner: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "retro", directoryHint: .isDirectory)
    }
}
