import XCTest
@testable import Retro

@MainActor
final class WardrobeReadTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try Data(contentsOf: url)
    }

    func testWireRecordsPreserveVersionsColoursAndWearSnapshots() throws {
        let page = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory"))
        XCTAssertEqual(page.items[0].version, 9_007_199_254_740_993)
        XCTAssertEqual(page.items[0].colours, ["chartreuse", "navy"])
        XCTAssertNil(page.items[0].material)
        XCTAssertEqual(page.items[0].wearDays, 1)
        XCTAssertEqual(page.items[0].wearEvents, 2)
        let day = try JSONDecoder().decode(WardrobeDay.self, from: fixture("day"))
        XCTAssertEqual(day.outfits.count, 2)
        XCTAssertEqual(Set(day.outfits.map(\.day)), ["2026-10-07"])
        XCTAssertEqual(day.outfits[0].timeZone, "America/Los_Angeles")
        XCTAssertEqual(day.outfits[0].items[0].role, "one_piece")
        XCTAssertEqual(day.outfits[0].items[0].snapshot?.name, "Blue dress")
        XCTAssertNotEqual(day.outfits[0].items[0].snapshot?.name, page.items[0].name)
    }

    func testOutdatedQueryCannotReplaceOrCacheTheNewQuery() async throws {
        let owner = "test-\(UUID().uuidString)"
        defer { DiskCache(owner: owner).wipeCaches(); WardrobeReadProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WardrobeReadProtocol.self]
        let api = RetroAPI(baseURL: "https://wardrobe.test/api/v1", session: URLSession(configuration: config))
        let store = WardrobeStore(engine: Engine(owner: owner, api: api, currentUser: { owner }, token: { _ in "token" }))
        let started = expectation(description: "first query started")
        var held: WardrobeReadProtocol?
        var count = 0
        WardrobeReadProtocol.handle = { request in
            Task { @MainActor in
                count += 1
                if count == 1 { held = request; started.fulfill() }
                else { request.finish(200, Data(#"{"items":[],"next_cursor":null}"#.utf8)) }
            }
        }
        let first = Task { await store.refreshInventory(WardrobeInventoryQuery(category: "top")) }
        await fulfillment(of: [started], timeout: 3)
        await store.refreshInventory(WardrobeInventoryQuery(category: "bottom"))
        held?.finish(200, try fixture("inventory"))
        await first.value
        XCTAssertEqual(store.inventory.value?.items.count, 0)

        WardrobeReadProtocol.handle = { $0.finish(503, Data("{}".utf8)) }
        await store.refreshInventory(WardrobeInventoryQuery(category: "top"))
        XCTAssertNil(store.inventory.value, "The superseded top query must not have populated its disk cache")
        XCTAssertNotNil(store.inventory.problem)
    }

    func testSwitchingAccountsRejectsResponseAndReadCache() async throws {
        let owner = "test-\(UUID().uuidString)"
        var current = owner
        defer { DiskCache(owner: owner).wipeCaches(); WardrobeReadProtocol.handle = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WardrobeReadProtocol.self]
        let api = RetroAPI(baseURL: "https://wardrobe.test/api/v1", session: URLSession(configuration: config))
        let engine = Engine(owner: owner, api: api, currentUser: { current }, token: { _ in "token" })
        let data = try fixture("inventory")
        WardrobeReadProtocol.handle = { request in
            Task { @MainActor in current = "another-account"; request.finish(200, data) }
        }
        let store = WardrobeStore(engine: engine)
        await store.refreshInventory(WardrobeInventoryQuery())
        XCTAssertNil(store.inventory.value)
        current = owner
        WardrobeReadProtocol.handle = { $0.finish(503, Data("{}".utf8)) }
        await store.refreshInventory(WardrobeInventoryQuery())
        XCTAssertNil(store.inventory.value, "The response from an abandoned account session must not have been cached")
    }
}

private final class WardrobeReadProtocol: URLProtocol {
    static var handle: ((WardrobeReadProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handle?(self) }
    override func stopLoading() {}
    func finish(_ status: Int, _ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
