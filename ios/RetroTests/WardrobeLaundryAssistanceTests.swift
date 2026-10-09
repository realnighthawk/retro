import XCTest
@testable import Retro

@MainActor final class WardrobeLaundryAssistanceTests: XCTestCase {
    private func preferences() throws -> WardrobePreferences {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "preferences", withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(WardrobePreferencesResult.self, from: Data(contentsOf: url)).preferences
    }
    private func changed(_ value: WardrobePreferences, _ update: (inout [String: Any]) -> Void) throws -> WardrobePreferences {
        var fields = try WardrobeSettingFields.object(value); update(&fields)
        return try JSONDecoder().decode(WardrobePreferences.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testExplicitProgrammeRequiresCelsiusEvidenceAndKeepsUnsupportedConditionsForReview() throws {
        let text = "Machine wash at 0 °C, gentle, line dry tomorrow."
        let proposal = try WardrobeLaundryRequest(changes: [("wash_method", "machine", "Machine wash"), ("temperature_c", "0", "0 °C"), ("cycle", "gentle", "gentle"), ("drying", "line", "line dry")], unhandled: ["Choose tomorrow's date manually."], request: text)
        let keys = Set(proposal.patch.keys)
        XCTAssertThrowsError(try proposal.applying(keys, to: .init(), acceptedLimitations: false))
        let original = WardrobeLaundryProgram(wash_method: "dry_clean", temperature_c: nil, cycle: "unknown", drying: "professional")
        let result = try proposal.applying(keys, to: original, acceptedLimitations: true)
        XCTAssertEqual(result.temperature_c, 0); XCTAssertEqual(result.wash_method, "machine"); XCTAssertEqual(result.cycle, "gentle"); XCTAssertEqual(result.drying, "line")
        XCTAssertNoThrow(try result.validate())
        for text in ["cold", "20", "20 °F", "120 °C"] {
            XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("temperature_c", "20", text)], unhandled: [], request: text))
        }
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("temperature_c", "20", "20 °C")], unhandled: [], request: "cold"))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("confirmed", "true", "confirmed")], unhandled: [], request: "confirmed"))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("wash_method", "do_not_wash", "do not wash")], unhandled: [], request: "do not wash"))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("cycle", "gentle", "gentle"), ("cycle", "normal", "normal")], unhandled: [], request: "gentle normal"))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [], unhandled: [""], request: "cold"))
    }
    func testNamedPresetUsesExactNativeValuesAndRejectsStaleAmbiguousOrInventedSources() throws {
        let saved = try preferences()
        let proposal = try WardrobeLaundryRequest(changes: [("machine_preset", "p1", "Cold wash")], unhandled: [], request: "Prepare Cold wash", preferences: saved)
        XCTAssertEqual(proposal.source?.version, 9_007_199_254_740_993)
        let program = try proposal.applying(["machine_preset"], to: .init(), acceptedLimitations: false)
        XCTAssertEqual(program.temperature_c, 0, "A named cold preset copies its real zero setting rather than inventing 20 °C.")
        XCTAssertNoThrow(try proposal.checkPreset(saved, cached: false, pending: false))
        XCTAssertThrowsError(try proposal.checkPreset(saved, cached: true, pending: false))
        XCTAssertThrowsError(try proposal.checkPreset(saved, cached: false, pending: true))
        let newer = try changed(saved) { $0["version"] = Int64(9_007_199_254_740_994) }
        XCTAssertThrowsError(try proposal.checkPreset(newer, cached: false, pending: false))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("machine_preset", "p2", "Cold wash")], unhandled: [], request: "Cold wash", preferences: saved))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("machine_preset", "p1", "cold")], unhandled: [], request: "cold", preferences: saved))
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("machine_preset", "p1", "Cold wash")], unhandled: [], request: "Cold wash"))
        var duplicate = saved; var preset = saved.machine_presets[0]
        preset.id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"; duplicate.machine_presets.append(preset)
        XCTAssertThrowsError(try WardrobeLaundryRequest(changes: [("machine_preset", "p1", "Cold wash")], unhandled: [], request: "Cold wash", preferences: duplicate))
        var restricted = saved; restricted.machine_presets[0].drying = "do_not_tumble"
        let choice = try WardrobeLaundryRequest(changes: [("machine_preset", "p1", "Cold wash")], unhandled: [], request: "Cold wash", preferences: restricted)
        let incomplete = try choice.applying(["machine_preset"], to: .init(), acceptedLimitations: false)
        XCTAssertEqual(incomplete.drying, "do_not_tumble"); XCTAssertThrowsError(try incomplete.validate(), "The owner must choose an actual permitted drying method.")
    }
    func testPartialMethodChangesDoNotInventMissingProgrammeSettings() throws {
        let hand = try WardrobeLaundryRequest(changes: [("wash_method", "hand", "hand wash")], unhandled: [], request: "hand wash")
        let program = try hand.applying(["wash_method"], to: .init(), acceptedLimitations: false)
        XCTAssertEqual(program.cycle, "unknown"); XCTAssertEqual(program.temperature_c, 20, "An existing reviewed temperature remains unchanged.")
        let professional = try WardrobeLaundryRequest(changes: [("wash_method", "dry_clean", "dry clean")], unhandled: [], request: "dry clean")
        let cleaning = try professional.applying(["wash_method"], to: program, acceptedLimitations: false)
        XCTAssertNil(cleaning.temperature_c); XCTAssertEqual(cleaning.drying, "professional"); XCTAssertNoThrow(try cleaning.validate())
        let machine = try WardrobeLaundryRequest(changes: [("wash_method", "machine", "machine wash")], unhandled: [], request: "machine wash")
        let incomplete = try machine.applying(["wash_method"], to: cleaning, acceptedLimitations: false)
        XCTAssertNil(incomplete.temperature_c); XCTAssertEqual(incomplete.cycle, "unknown"); XCTAssertEqual(incomplete.drying, "unknown")
        XCTAssertThrowsError(try incomplete.validate())
        XCTAssertThrowsError(try machine.applying(["garment_ids"], to: cleaning, acceptedLimitations: false))
        let conflict = try WardrobeLaundryRequest(changes: [("wash_method", "hand", "hand wash"), ("cycle", "gentle", "gentle")], unhandled: [], request: "hand wash gentle")
        XCTAssertThrowsError(try conflict.applying(["wash_method", "cycle"], to: .init(), acceptedLimitations: false))
        let home = try WardrobeLaundryRequest(changes: [("temperature_c", "20", "20 °C")], unhandled: [], request: "20 °C")
        XCTAssertThrowsError(try home.applying(["temperature_c"], to: cleaning, acceptedLimitations: false))
    }
    func testReviewedOCRTextClearsConfirmationWithoutInferringCareOrOverwritingChangedForms() throws {
        let original: [String: Any] = ["id": "11111111-1111-4111-8111-111111111111", "version": Int64(9_007_199_254_740_993), "evidence": "Old label", "confirmed": true, "source": "manual", "max_temp_c": 20, "cycle": "gentle"]
        let scan = try WardrobeCareLabelReview(text: "Machine wash at 30 °C. Line dry.", values: original)
        let applied = try scan.applying(scan.text, to: original, owner: true)
        XCTAssertEqual(applied["confirmed"] as? Bool, false); XCTAssertEqual(applied["source"] as? String, "label")
        XCTAssertEqual(applied["evidence"] as? String, scan.text)
        XCTAssertEqual(applied["max_temp_c"] as? Int, 20, "Scanning evidence alone does not change existing care facts.")
        XCTAssertEqual((applied["version"] as? NSNumber)?.int64Value, 9_007_199_254_740_993)
        XCTAssertNil(applied["availability"])
        var edited = original; edited["cycle"] = "normal"
        XCTAssertThrowsError(try scan.applying(scan.text, to: edited, owner: true))
        XCTAssertThrowsError(try scan.applying(scan.text, to: original, owner: false))
        XCTAssertThrowsError(try scan.applying(" ", to: original, owner: true))
        XCTAssertThrowsError(try WardrobeCareLabelReview(text: String(repeating: "é", count: 1001), values: original))
    }
}
