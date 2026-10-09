import XCTest
@testable import Retro

@MainActor final class WardrobeSettingsTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    func testPreferencesKeepExactVersionsZeroAndFalse() throws {
        let p = try fixture("preferences", as: WardrobePreferencesResult.self).preferences
        XCTAssertEqual(p.version, 9_007_199_254_740_993)
        XCTAssertEqual(p.avoid_repeat_days, 0); XCTAssertFalse(p.prefer_underused_items)
        XCTAssertEqual(p.machine_presets[0].temperature_c, 0)
        let patch = WardrobeSettingFields.patch(try WardrobeSettingFields.object(p), keys: WardrobeSettingFields.preferences + ["machine_presets"])
        XCTAssertNil(patch["id"]); XCTAssertEqual(patch["avoid_repeat_days"] as? Int, 0)
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["cold_threshold_c": "bad"], keys: ["cold_threshold_c"]))
    }
    func testOptionalFeedbackAndExplicitReset() throws {
        let r = try fixture("feedback", as: WardrobeFeedbackResult.self)
        XCTAssertNil(r.feedback.rating); XCTAssertNotEqual(r.feedback.outfit_version, r.current_outfit_version)
        let patch = WardrobeSettingFields.patch(["warmth":"unknown"], keys: WardrobeSettingFields.feedback)
        XCTAssertTrue(patch["rating"] is NSNull)
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["rating": 0], keys: ["rating"]))
    }
    func testProposalsRequireEvidenceAndDoNotInferRatingsOrConfirmation() throws {
        let proposal = try WardrobeSettingsProposal(changes: [("max_temp_c", "30", "wash at 30 °C")], unhandled: [], allowed: WardrobeSettingFields.care, evidence: "wash at 30 °C")
        XCTAssertEqual(proposal.patch["max_temp_c"] as? Int, 30)
        XCTAssertThrowsError(try WardrobeSettingsProposal(changes: [("rating", "5", "felt good")], unhandled: [], allowed: WardrobeSettingFields.feedback, evidence: "felt good"))
        XCTAssertThrowsError(try WardrobeSettingsProposal(changes: [("confirmed", "true", "wash at 30")], unhandled: [], allowed: ["max_temp_c"], evidence: "wash at 30"))
        XCTAssertThrowsError(try WardrobeSettingsProposal(changes: [("max_temp_c", "30", "invented")], unhandled: [], allowed: WardrobeSettingFields.care, evidence: "wash at 30"))
        for text in ["wash cold", "wash at 30", "wash at 30 °F", "wash at 130 °C"] {
            XCTAssertThrowsError(try WardrobeSettingsProposal(changes: [("max_temp_c", "30", text)], unhandled: [], allowed: WardrobeSettingFields.care, evidence: text))
        }
    }
    func testCareAndPreferencesNeedExplicitConsistentValues() throws {
        let old = try fixture("inventory", as: WardrobePage<WardrobeGarment>.self)
        XCTAssertNil(old.items[0].care)
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["wash_method":"unknown", "confirmed":true], keys: WardrobeSettingFields.care))
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["wash_method":"dry_clean", "max_temp_c":30], keys: ["wash_method", "max_temp_c"]))
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["cold_threshold_c":25, "hot_threshold_c":25], keys: ["cold_threshold_c", "hot_threshold_c"]))
        XCTAssertThrowsError(try WardrobeSettingFields.validate(["preferred_styles":["Casual", "casual"]], keys: ["preferred_styles"]))
        XCTAssertNoThrow(try WardrobeSettingFields.validate(["wash_method":"machine", "max_temp_c":0, "cycle":"gentle", "confirmed":true], keys: ["wash_method", "max_temp_c", "confirmed", "cycle"]))
    }
    func testNewWritesSurviveReopeningWithFrozenReviewVersions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "writes.json")
        let writes = WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) })
        let id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        try writes.enqueue(operation: "outfits_feedback_update", entity: id, title: "Feedback", fields: ["id": id, "expected_version": 0, "outfit_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "expected_outfit_version": Int64(9_007_199_254_740_993), "patch": ["rating": NSNull()]])
        let restored = WardrobeWrites(file: file, stillOwner: { true }, send: { _, _ in .ok(true) })
        XCTAssertEqual(restored.items[0].body, writes.items[0].body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: restored.items[0].body) as? [String: Any])
        XCTAssertEqual((body["expected_outfit_version"] as? NSNumber)?.int64Value, 9_007_199_254_740_993)
        XCTAssertEqual(body["expected_version"] as? Int, 0)
    }
    func testContextRejectsWrongCoverageSourcesAndReviewedVersions() throws {
        let p = try fixture("preferences", as: WardrobePreferencesResult.self).preferences
        let g = try fixture("inventory", as: WardrobePage<WardrobeGarment>.self).items[0]
        let request = WardrobeContextInput(request_id: UUID().uuidString.lowercased(), garment_ids: [g.id], outfit_ids: [])
        let sources = [WardrobeContextSource(entity_type: "preferences", id: p.id, version: p.version, updated_at: p.updated_at), WardrobeContextSource(entity_type: "garment", id: g.id, version: g.version, updated_at: g.updatedAt)]
        let context = WardrobeContext(schema_version: 1, request_id: request.request_id, retrieved_at: p.updated_at, coverage: "explicit_records_only", capabilities: ["wardrobe_records", "preferences", "care", "feedback"], preferences: p, garments: [g], outfits: [], feedback: [], sources: sources)
        XCTAssertNoThrow(try context.validate(request, expected: ["garment:" + g.id: g.version]))
        XCTAssertThrowsError(try context.validate(request, expected: ["garment:" + g.id: g.version + 1]))
        XCTAssertThrowsError(try context.validate(WardrobeContextInput(request_id: request.request_id, garment_ids: [], outfit_ids: []), expected: ["garment:" + g.id: g.version]))
        var fields = try WardrobeSettingFields.object(context)
        fields["sources"] = [try WardrobeSettingFields.object(sources[0]), try WardrobeSettingFields.object(sources[0])]
        let duplicate = try JSONDecoder().decode(WardrobeContext.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertThrowsError(try duplicate.validate(request, expected: ["garment:" + g.id: g.version]))
        fields = try WardrobeSettingFields.object(context); fields["coverage"] = "complete_wardrobe"
        let overclaim = try JSONDecoder().decode(WardrobeContext.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertThrowsError(try overclaim.validate(request, expected: ["garment:" + g.id: g.version]))
    }
}
