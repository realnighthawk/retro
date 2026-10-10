import XCTest
@testable import Retro

final class WardrobeDuplicateTests: XCTestCase {
    private func candidate(_ index: Int, media: Bool = true) -> WardrobeDuplicateCandidate {
        WardrobeDuplicateCandidate(id: "00000000-0000-4000-8000-\(String(format: "%012d", index))", name: "Piece \(index)", version: Int64(index),
                                   mediaID: "11111111-1111-4111-8111-\(String(format: "%012d", index))")
    }
    private func scan(hints: Int, compared: Int, unchecked: Int, complete: Bool = true, total: Int64? = nil, source: Data = Data("photo".utf8)) -> WardrobeDuplicateScan {
        WardrobeDuplicateScan(hints: (0..<hints).map { WardrobeDuplicateHint(photo: WardrobeDuplicatePhoto(id: candidate($0).id, name: "Piece \($0)", version: 1, mediaID: candidate($0).mediaID, bytes: Data()), distance: Float($0)) },
                              sourceChecksum: WardrobeDuplicates.checksum(source), revision: WardrobeDuplicates.revision,
                              activeGarments: 400, indexedGarments: 400, totalMatches: total ?? 400, complete: complete,
                              compared: compared, missingPhotos: 200, unchecked: unchecked)
    }

    func testPlanPrefersCachedPhotosAndBoundsTheFetches() {
        let candidates = (0..<10).map { candidate($0) }
        let cached = { (media: String) in media.hasSuffix("000000000003") ? Data(repeating: 1, count: 1024) : nil }
        let plan = WardrobeDuplicates.plan(candidates, budget: 3, cached: cached)
        XCTAssertEqual(plan.ready.count, 1)
        XCTAssertEqual(plan.ready.first?.name, "Piece 3")
        XCTAssertEqual(plan.fetch.count, 3, "Only the bounded number of photos is fetched")
        XCTAssertEqual(plan.overBudget, 6, "Everything not checked is reported, never dropped silently")
        XCTAssertEqual(plan.planned, 4)
        let generous = WardrobeDuplicates.plan(candidates, budget: 50, cached: cached)
        XCTAssertEqual(generous.fetch.count, 9)
        XCTAssertEqual(generous.overBudget, 0)
        XCTAssertEqual(generous.planned, 10, "A cached photo is never also fetched")
    }

    func testPlanIgnoresOversizedCachedBytes() {
        let candidates = (0..<2).map { candidate($0) }
        let plan = WardrobeDuplicates.plan(candidates, budget: 5, cached: { _ in Data(repeating: 0, count: 17 * 1024 * 1024) })
        XCTAssertTrue(plan.ready.isEmpty, "An oversized cached thumbnail is not compared")
        XCTAssertEqual(plan.fetch.count, 2)
    }

    func testHintsOnlyApplyToTheSameSourcePhotoAndRevision() {
        let source = Data("selected photo".utf8)
        let value = scan(hints: 3, compared: 5, unchecked: 1, source: source)
        XCTAssertTrue(value.matches(source: source))
        XCTAssertFalse(value.matches(source: Data("a different photo".utf8)), "A hint from another photo cannot apply")
        let stale = WardrobeDuplicateScan(hints: value.hints, sourceChecksum: value.sourceChecksum, revision: WardrobeDuplicates.revision + 1,
                                          activeGarments: 1, indexedGarments: 1, totalMatches: 1, complete: true, compared: 1, missingPhotos: 0, unchecked: 0)
        XCTAssertFalse(stale.matches(source: source), "A comparison from another revision cannot apply")
    }

    func testUnreadableInventoryIsNotReportedAsCoverage() {
        var value = scan(hints: 0, compared: 0, unchecked: 0)
        value.readProblem = "Temporarily unavailable"
        XCTAssertEqual(value.summary, "The inventory could not be read, so nothing was compared. Temporarily unavailable You can still create a garment.")
        XCTAssertFalse(value.summary.contains("Compared 0 photos"), "A failed read is not a coverage claim")
    }

    func testSummaryDisclosesCoverageAndTruncation() {
        let complete = scan(hints: 3, compared: 137, unchecked: 65).summary
        XCTAssertTrue(complete.contains("Compared 137 photos from 400 of 400 active garments at this time."))
        XCTAssertTrue(complete.contains("200 garments have no photo and 65 were not checked in this scan."))
        XCTAssertTrue(complete.contains("never a duplicate verdict"))
        XCTAssertFalse(complete.contains("cut short"))
        let truncated = scan(hints: 3, compared: 10, unchecked: 0, complete: false, total: 900).summary
        XCTAssertTrue(truncated.contains("200 garments have no photo and 0 were not checked in this scan."))
        XCTAssertTrue(truncated.contains("The inventory index was cut short (400 of 900 garments), so other pages were not checked."))
    }
}
