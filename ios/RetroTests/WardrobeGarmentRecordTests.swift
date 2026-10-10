import XCTest
@testable import Retro

@MainActor final class WardrobeGarmentRecordTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "wardrobe")))
    }

    func testOldRecordsStillDecodeAndNewFieldsRoundTrip() throws {
        let legacy = try JSONDecoder().decode(WardrobePage<WardrobeGarment>.self, from: fixture("inventory")).items[0]
        XCTAssertNil(legacy.purchase); XCTAssertNil(legacy.pattern); XCTAssertNil(legacy.fit)
        let record = try JSONDecoder().decode(WardrobeGarmentResult.self, from: fixture("garment-records")).garment
        XCTAssertEqual(record.version, 9007199254740993)
        XCTAssertEqual(record.purchase?.amountMinor, 19990)
        XCTAssertEqual(record.purchase?.amountText, "199.90")
        XCTAssertEqual(record.purchase?.summary, "2026-03-02 · 199.90 EUR · Receipt")
        let fields = try WardrobeGarmentDraft(record).fields()
        XCTAssertEqual(fields["pattern"] as? String, "herringbone")
        XCTAssertEqual(fields["style"] as? String, "field jacket")
        XCTAssertEqual(fields["fit"] as? String, "relaxed")
        let purchase = try XCTUnwrap(fields["purchase"] as? [String: Any])
        XCTAssertEqual(purchase["amount"] as? String, "199.90")
        XCTAssertEqual(purchase["currency"] as? String, "EUR")
        XCTAssertEqual(purchase["source"] as? String, "receipt")
        XCTAssertEqual(purchase["evidence"] as? String, "Receipt 2026-03-02, total 199,90 EUR")
        XCTAssertTrue(WardrobeDraftValidation.patch(fields, original: try WardrobeGarmentDraft(record).fields()).isEmpty)
    }

    func testMoneyUsesTheCurrencysExponentWithoutConversion() throws {
        func money(_ json: String) throws -> WardrobePurchase {
            try JSONDecoder().decode(WardrobePurchase.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try money(#"{"amount_minor": 12000, "currency": "JPY", "currency_exponent": 0}"#).amountSummary, "12000 JPY")
        XCTAssertEqual(try money(#"{"amount_minor": 1234, "currency": "KWD", "currency_exponent": 3}"#).amountSummary, "1.234 KWD")
        XCTAssertEqual(try money(#"{"amount_minor": 0, "currency": "USD", "currency_exponent": 2}"#).amountSummary, "0.00 USD")
        XCTAssertEqual(try money(#"{"currency": "USD", "currency_exponent": 2}"#).amountSummary, "USD")
        XCTAssertEqual(try money(#"{}"#).summary, "")
    }

    func testPurchaseDraftFieldsAreValidatedAndPatchIsSelective() throws {
        var draft = WardrobeGarmentDraft()
        draft.name = "Jacket"
        draft.purchaseDraft.currency = "usd"
        let currencyOnly = try draft.fields()
        XCTAssertEqual((currencyOnly["purchase"] as? [String: Any])?["currency"] as? String, "USD")
        XCTAssertNil((currencyOnly["purchase"] as? [String: Any])?["amount"] as? String, "No amount is recorded until one is given")
        draft.purchaseDraft.amount = "12.505"
        XCTAssertNoThrow(try draft.fields(), "Precision beyond the currency is the engine's check, not a guess here")
        draft.purchaseDraft.source = "receipt"
        XCTAssertThrowsError(try draft.fields(), "A receipt needs evidence text")
        draft.purchaseDraft.evidence = "Receipt text"
        draft.purchaseDraft.date = "2026-2-3"
        XCTAssertThrowsError(try draft.fields(), "Purchase dates are ISO dates")
        draft.purchaseDraft.date = "2026-02-03"
        let fields = try draft.fields()
        let purchase = try XCTUnwrap(fields["purchase"] as? [String: Any])
        XCTAssertEqual(purchase["currency"] as? String, "USD")
        XCTAssertEqual(purchase["amount"] as? String, "12.505")
        var record = try JSONDecoder().decode(WardrobeGarmentResult.self, from: fixture("garment-records")).garment
        var edited = WardrobeGarmentDraft(record)
        edited.purchaseDraft.amount = "149.00"
        let patch = WardrobeDraftValidation.patch(try edited.fields(), original: try WardrobeGarmentDraft(record).fields())
        XCTAssertEqual(patch.keys.sorted(), ["purchase"])
        edited.purchaseDraft.date = ""; edited.purchaseDraft.currency = ""; edited.purchaseDraft.amount = ""; edited.purchaseDraft.evidence = ""; edited.purchaseDraft.source = "manual"
        let cleared = WardrobeDraftValidation.patch(try edited.fields(), original: try WardrobeGarmentDraft(record).fields())
        XCTAssertEqual(cleared.keys.sorted(), ["purchase"])
        XCTAssertTrue(cleared["purchase"] is NSNull)
        record = try JSONDecoder().decode(WardrobeGarmentResult.self, from: fixture("garment-records")).garment
        var legacy = WardrobeGarmentDraft()
        legacy.name = "Tee"
        var legacyRecord = legacy
        legacyRecord.purchaseDraft.evidence = "Photo of the receipt"
        XCTAssertEqual(WardrobeDraftValidation.patch(try legacyRecord.fields(), original: try legacy.fields()).keys.sorted(), ["purchase"])
    }

    func testDraftStorageKeepsRecordsWithoutTheNewFieldsReadable() throws {
        let old = #"{"name": "Tee", "category": "top", "availability": "ready", "subtype": "", "colours": "", "warmth": "unknown", "seasons": "", "formality": "", "material": "", "brand": "", "notes": "", "favourite": false}"#
        let draft = try JSONDecoder().decode(WardrobeGarmentDraft.self, from: Data(old.utf8))
        XCTAssertNil(draft.pattern); XCTAssertNil(draft.purchase)
        XCTAssertEqual(draft.patternText, "")
        XCTAssertEqual(try draft.fields()["purchase"] as? NSNull, NSNull())
        let queued = try WardrobeGarmentDraft(createFields: [
            "name": "Queued tee", "category": "top", "colours": [], "seasons": [],
            "purchase": ["date": "2026-02-01", "currency": "GBP", "amount": "45", "evidence": "", "source": "manual"]
        ])
        XCTAssertEqual(queued.purchaseDraft.amount, "45")
        XCTAssertEqual(queued.purchaseDraft.currency, "GBP")
        XCTAssertTrue(WardrobeDraftValidation.patch(try queued.fields(), original: try queued.fields()).isEmpty)
    }
}
