import XCTest
@testable import Retro

@MainActor final class WardrobeSearchTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe")))
    }

    func testPageDecodesCoverageAndStaysBackwardCompatible() throws {
        let page = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory"))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.totalMatches, 2, "A page shorter than the match count is not complete inventory")
        XCTAssertNotNil(page.nextCursor)
        XCTAssertTrue((page.totalMatches ?? 0) > Int64(page.items.count))
        let legacy = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: Data(#"{"items": [], "next_cursor": null}"#.utf8))
        XCTAssertNil(legacy.totalMatches, "An older response without coverage still decodes")
        XCTAssertEqual(WardrobePage<WardrobeGarment>(items: [], nextCursor: nil, totalMatches: 2).totalMatches, 2)
    }

    func testQueryEncodesEveryFilterWithTheWireNamesTheEngineExpects() throws {
        func fields(_ query: WardrobeInventoryQuery) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query)) as? [String: Any])
        }
        let plain = try fields(WardrobeInventoryQuery())
        XCTAssertEqual(plain["sort"] as? String, "id")
        XCTAssertNil(plain["favourite"]); XCTAssertNil(plain["care_confirmed"]); XCTAssertNil(plain["cursor"])
        var full = WardrobeInventoryQuery()
        full.search = "shirt"; full.brand = "Seaside"; full.notes = "waxed"; full.colour = "blue"; full.season = "autumn"
        full.favourite = false; full.washMethod = "dry_clean"; full.careConfirmed = true; full.includeArchived = true
        full.sort = "name"; full.cursor = "opaque"
        let encoded = try fields(full)
        XCTAssertEqual(encoded["wash_method"] as? String, "dry_clean")
        XCTAssertEqual(encoded["care_confirmed"] as? Bool, true)
        XCTAssertEqual(encoded["favourite"] as? Bool, false)
        XCTAssertEqual(encoded["include_archived"] as? Bool, true)
        XCTAssertEqual(encoded["brand"] as? String, "Seaside")
        XCTAssertEqual(encoded["colour"] as? String, "blue")
        XCTAssertEqual(encoded["season"] as? String, "autumn")
        XCTAssertEqual(encoded["notes"] as? String, "waxed")
        XCTAssertEqual(encoded["sort"] as? String, "name")
        XCTAssertEqual(encoded["cursor"] as? String, "opaque")
        XCTAssertEqual(Set(WardrobeInventoryQuery.sorts), Set(["id", "name", "recent", "added"]))
        XCTAssertEqual(WardrobeInventoryQuery(sort: "recent").sortTitle, "Recently updated")
    }

    func testQueryDescribesItsActiveFilters() {
        var query = WardrobeInventoryQuery()
        XCTAssertTrue(query.activeFilters.isEmpty)
        XCTAssertFalse(query.hasTextFilters)
        query.brand = "Seaside"; query.colour = "blue"; query.favourite = false; query.careConfirmed = true; query.washMethod = "hand"
        XCTAssertEqual(query.activeFilters, ["Brand: Seaside", "Colour: blue", "Wash: Hand", "Not favourite", "Care reviewed"])
        XCTAssertTrue(query.hasTextFilters)
        XCTAssertNotEqual(query, WardrobeInventoryQuery(), "Any active filter keeps the list out of its empty state")
    }

    func testLanguageDraftCarriesEditableSearchFiltersAndKeepsLimitations() throws {
        var draft = WardrobeLanguageDraft(occasion: nil, warmth: nil, requiredGarments: [], excludedGarments: [], nameQuery: "shirt",
                                         category: nil, availability: nil, includeArchived: nil, brandQuery: "Seaside", colour: "blue",
                                         season: "autumn", notesQuery: "waxed", favourite: false, washMethod: "hand", careConfirmed: true,
                                         unhandled: ["wear dates"])
        let query = try draft.searchQuery()
        XCTAssertEqual(query.brand, "Seaside"); XCTAssertEqual(query.colour, "blue"); XCTAssertEqual(query.season, "autumn")
        XCTAssertEqual(query.notes, "waxed"); XCTAssertEqual(query.washMethod, "hand"); XCTAssertEqual(query.careConfirmed, true)
        XCTAssertEqual(query.favourite, false); XCTAssertEqual(query.search, "shirt")
        XCTAssertEqual(draft.unhandled, ["wear dates"], "Unsupported conditions stay visible instead of being dropped")
        draft.washMethod = "tumble"
        XCTAssertThrowsError(try draft.searchQuery(), "An unsupported washing method is rejected, not silently ignored")
        draft.washMethod = "hand"
        draft.colour = String(repeating: "é", count: 51)
        XCTAssertThrowsError(try draft.searchQuery(), "An oversized filter value is rejected")
        draft.colour = "blue"
        draft.requiredGarments = ["the blue one"]
        XCTAssertThrowsError(try draft.searchQuery(), "Outfit constraints cannot be applied as wardrobe search")
        var search = draft
        search.requiredGarments = []
        search.occasion = "work"
        XCTAssertThrowsError(try search.searchQuery())
        search.occasion = nil
        var outfit = WardrobeLanguageDraft(occasion: nil, warmth: nil, requiredGarments: [], excludedGarments: [], nameQuery: nil,
                                           category: nil, availability: nil, includeArchived: nil, brandQuery: nil, colour: "blue",
                                           season: nil, notesQuery: nil, favourite: nil, washMethod: nil, careConfirmed: nil, unhandled: [])
        XCTAssertThrowsError(try outfit.validate(.outfit), "Search filters cannot leak into an outfit request")
        outfit.colour = nil
        XCTAssertNoThrow(try outfit.validate(.outfit))
    }
}
