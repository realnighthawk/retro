import XCTest
@testable import Retro

@MainActor final class WardrobeUsageReviewTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe")))
    }
    private func review() throws -> WardrobeAnalysis {
        try JSONDecoder().decode(WardrobeAnalysis.self, from: fixture("usage-review"))
    }
    private let query = WardrobeAnalysisQuery(from: "1999-03-01", to: "1999-03-07")

    func testRankedUsageUnwornListsAndMoneyDecode() throws {
        let value = try review()
        XCTAssertEqual(value.mostWorn?.count, 3)
        XCTAssertEqual(value.mostWorn?.first?.wearEvents, 3)
        XCTAssertEqual(value.mostWorn?.first?.costPerWear?.text, "10.00 USD")
        XCTAssertEqual(value.mostWorn?.last?.costPerWear?.text, "5.00 EUR")
        XCTAssertNil(value.leastWorn?.first?.costPerWear, "A garment without a recorded amount has no cost per wear")
        XCTAssertEqual(value.notWornInRangeTotal, 2)
        XCTAssertEqual(value.neverWornTotal, 1)
        let earlier = try XCTUnwrap(value.notWornInRange?.first)
        XCTAssertEqual(earlier.lastWornOn, "1999-02-20")
        XCTAssertFalse(earlier.neverWorn)
        XCTAssertTrue(try XCTUnwrap(value.neverWorn?.first).neverWorn)
        XCTAssertEqual(value.colours?.first?.colour, "blue")
        XCTAssertEqual(value.weeks?.first?.weekStart, "1999-03-01")
        XCTAssertEqual(value.feedback?.ratings.first?.feedback, 1)
        XCTAssertEqual(value.selections?.plannedOutfits, 2)
        XCTAssertEqual(WardrobeMoney.text(minor: 12000, exponent: 0, currency: "JPY"), "12000 JPY")
        XCTAssertEqual(WardrobeMoney.text(minor: 1234, exponent: 3, currency: "KWD"), "1.234 KWD")
    }

    func testOlderResponsesStillDecodeAndSummarizeUnchanged() throws {
        let legacy = try JSONDecoder().decode(WardrobeAnalysis.self, from: fixture("analysis"))
        XCTAssertNil(legacy.mostWorn); XCTAssertNil(legacy.neverWorn); XCTAssertNil(legacy.feedback)
        XCTAssertEqual(try legacy.periodSummary(WardrobeAnalysisQuery(from: "2026-10-07", to: "2026-10-07")),
                       "2 confirmed outfit events across 1 day. 0 of 1 garment had no confirmed wear in this period.")
    }

    func testSummaryStatesFactsAndDisclosesCoverage() throws {
        let summary = try review().periodSummary(query)
        XCTAssertTrue(summary.hasPrefix("5 confirmed outfit events across 3 days."))
        XCTAssertTrue(summary.contains("2 of 5 garments had no confirmed wear in this period."))
        XCTAssertTrue(summary.contains("1 garment has never been worn at all, not just in these dates."))
        XCTAssertTrue(summary.contains("Most worn: Anorak (3), Cardigan (1)."))
        XCTAssertTrue(summary.contains("Colours: blue (2 garments, 3 wears), red (2 garments, 1 wear)."))
        XCTAssertTrue(summary.contains("2 saved feedback records, 1 with an overall rating."))
        XCTAssertTrue(summary.contains("2 saved daily choices became 1 confirmed wear; 2 plans are still only planned."))
    }

    func testForgedOrStaleDetailsAreRejected() throws {
        // Forged figures are built on the wire shape, so decoding and validation are both exercised.
        func changed(_ mutate: (inout [String: Any]) -> Void) throws -> WardrobeAnalysis {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("usage-review")) as? [String: Any])
            mutate(&root)
            return try JSONDecoder().decode(WardrobeAnalysis.self, from: JSONSerialization.data(withJSONObject: root))
        }
        func ranked(_ root: inout [String: Any], _ apply: (inout [String: Any]) -> Void) {
            var list = root["most_worn"] as? [[String: Any]] ?? []
            apply(&list[0]); root["most_worn"] = list
        }
        let never = try changed { root in
            var list = root["never_worn"] as? [[String: Any]] ?? []
            list.append(["garment_id": "99999999-9999-4999-8999-999999999999", "name": "Ghost", "category": "top", "archived": false, "created_on": "1990-01-01", "wear_events": 0])
            root["never_worn"] = list
        }
        XCTAssertThrowsError(try never.periodSummary(query), "A never-worn entry outside the unworn list is not authoritative")
        XCTAssertThrowsError(try changed { $0["never_worn_total"] = 4 }.periodSummary(query))
        let cost = try changed { root in ranked(&root) { $0["cost_per_wear"] = ["currency": "USD", "amount_minor": 1000, "currency_exponent": 2, "wear_events": 1] } }
        XCTAssertThrowsError(try cost.periodSummary(query), "Cost per wear cannot use fewer wears than the range counted")
        let histogram = try changed { root in
            var feedback = root["feedback"] as? [String: Any] ?? [:]
            feedback["ratings"] = [["rating": 5, "feedback": 1], ["rating": 4, "feedback": 1]]
            root["feedback"] = feedback
        }
        XCTAssertThrowsError(try histogram.periodSummary(query), "Rating buckets must add up to the rated count")
        let colour = try changed { root in
            var list = root["colours"] as? [[String: Any]] ?? []
            list[0]["worn_garments"] = 9; root["colours"] = list
        }
        XCTAssertThrowsError(try colour.periodSummary(query))
        XCTAssertThrowsError(try changed { root in ranked(&root) { $0["wear_events"] = 0 } }.periodSummary(query))
        XCTAssertThrowsError(try review().periodSummary(WardrobeAnalysisQuery(from: "1999-03-02", to: "1999-03-07")),
                             "A review for another period is not explained with these dates")
        XCTAssertThrowsError(try changed { $0["unworn_garments"] = 3 }.periodSummary(query), "The unworn total must match the unworn list total")
    }
}
