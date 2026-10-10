import XCTest
@testable import Retro

@MainActor final class WardrobeReceiptTests: XCTestCase {
    private let receipt = """
        ACME OUTFITTERS
        2 Mar 2026
        Field jacket      149.00
        Total EUR 149.00
        Card ending 4242
        """

    func testAmountsAreNormalizedOnlyWhenTheyReadOneWay() {
        XCTAssertEqual(WardrobeReceiptDraft.literalAmount("149.00"), "149.00")
        XCTAssertEqual(WardrobeReceiptDraft.literalAmount("1,234.56"), "1234.56", "A grouping comma with a decimal point is unambiguous")
        XCTAssertEqual(WardrobeReceiptDraft.literalAmount("1200"), "1200")
        XCTAssertEqual(WardrobeReceiptDraft.literalAmount(" 49.9 "), "49.9")
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("1,50"), "A comma decimal is not guessed")
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("12,345"), "A bare grouping comma reads differently in different countries")
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("1.234.56"))
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("49.9999"))
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("-5"))
        XCTAssertNil(WardrobeReceiptDraft.literalAmount("€49.99"))
    }

    func testCurrenciesAndDatesNeedTheReceiptsOwnWords() {
        XCTAssertEqual(WardrobeReceiptDraft.literalCurrency("EUR", text: "total eur 149.00"), "EUR")
        XCTAssertEqual(WardrobeReceiptDraft.literalCurrency("USD", text: "total 149.00 us dollars"), "USD", "A spelled-out currency is read from its name")
        XCTAssertNil(WardrobeReceiptDraft.literalCurrency("USD", text: "total $149.00"), "A symbol alone never picks a currency")
        XCTAssertNil(WardrobeReceiptDraft.literalCurrency("$", text: "total $149.00"))
        XCTAssertNil(WardrobeReceiptDraft.literalCurrency("USD", text: "total 149.00 dollars"), "A bare dollar is ambiguous")
        XCTAssertEqual(WardrobeReceiptDraft.literalDate("2026-03-02", text: "purchased 2026-03-02"), "2026-03-02")
        XCTAssertEqual(WardrobeReceiptDraft.literalDate("2 Mar 2026", text: "acme\n2 mar 2026\ntotal"), "2026-03-02", "A spelled date is normalized for the record")
        XCTAssertEqual(WardrobeReceiptDraft.literalDate("March 2, 2026", text: "acme\nmarch 2, 2026\ntotal"), "2026-03-02")
        XCTAssertNil(WardrobeReceiptDraft.literalDate("03/02/2026", text: "acme\n03/02/2026\ntotal"), "An all-numeric date is never guessed")
        XCTAssertNil(WardrobeReceiptDraft.literalDate("2026-03-02", text: "no date here"), "A date the receipt does not show is not proposed")
    }

    func testProposalKeepsOnlyWhatTheReceiptShowsAndReportsTheRest() {
        let read = WardrobeReceiptDraft(date: "2 Mar 2026", amount: "149.00", currency: "EUR", merchant: "ACME Outfitters").onlyStated(in: receipt)
        XCTAssertEqual(read.date, "2026-03-02")
        XCTAssertEqual(read.amount, "149.00")
        XCTAssertEqual(read.currency, "EUR")
        XCTAssertEqual(read.merchant, "ACME Outfitters")
        XCTAssertTrue(read.dropped.isEmpty)
        XCTAssertEqual(read.summary, "Date: 2026-03-02 · Total: 149.00 EUR · From: ACME Outfitters")
        XCTAssertFalse(read.isEmpty)

        let priceTag = WardrobeReceiptDraft(date: "03/02/2026", amount: "1,50", currency: "GBP", merchant: "ACME").onlyStated(in: "ACME £1,50")
        XCTAssertNil(priceTag.date); XCTAssertNil(priceTag.amount); XCTAssertNil(priceTag.currency)
        XCTAssertEqual(priceTag.merchant, "ACME", "The merchant is in the text, so it is still proposed")
        XCTAssertEqual(priceTag.dropped.count, 3)
        XCTAssertTrue(priceTag.dropped.contains { $0.hasPrefix("Total: 1,50") })
        XCTAssertTrue(priceTag.dropped.contains { $0.hasPrefix("Date 03/02/2026") })
        XCTAssertTrue(priceTag.isEmpty, "A total with no currency is not applicable")
        let nameless = WardrobeReceiptDraft(date: nil, amount: nil, currency: nil, merchant: "Some Shop").onlyStated(in: "ACME £1,50")
        XCTAssertNil(nameless.merchant, "A merchant the text does not name is not proposed")

        let symbolOnly = WardrobeReceiptDraft(date: nil, amount: "149.00", currency: "USD", merchant: nil).onlyStated(in: "Total $149.00")
        XCTAssertEqual(symbolOnly.amount, "149.00")
        XCTAssertNil(symbolOnly.currency, "The amount stays, the guessed currency does not")
        XCTAssertTrue(symbolOnly.summary.contains("no currency read — choose it yourself"))
        let invented = WardrobeReceiptDraft(date: nil, amount: "999.00", currency: nil, merchant: nil).onlyStated(in: "Total $149.00")
        XCTAssertNil(invented.amount, "A total the text does not show is not proposed")
        XCTAssertTrue(invented.isEmpty)
    }

    func testApplyingFillsOnlyThePurchaseRecordAndKeepsRetriesFreeOfDuplicates() throws {
        let open = try JSONDecoder().decode(WardrobeGarmentResult.self, from: Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "garment-records", withExtension: "json", subdirectory: "wardrobe")))).garment
        var draft = WardrobeGarmentDraft(open)
        let read = WardrobeReceiptDraft(date: "2 Mar 2026", amount: "149.00", currency: "EUR", merchant: "ACME Outfitters").onlyStated(in: receipt)
        draft.purchaseDraft.date = read.date ?? ""; draft.purchaseDraft.amount = read.amount ?? ""; draft.purchaseDraft.currency = read.currency ?? ""
        draft.purchaseDraft.evidence = "ACME OUTFITTERS 2 Mar 2026"          // the reviewed text, as the sheet stores it
        draft.purchaseDraft.source = "receipt"
        let fields = try draft.fields()
        let purchase = try XCTUnwrap(fields["purchase"] as? [String: Any])
        XCTAssertEqual(purchase["amount"] as? String, "149.00"); XCTAssertEqual(purchase["currency"] as? String, "EUR")
        XCTAssertEqual(purchase["date"] as? String, "2026-03-02"); XCTAssertEqual(purchase["source"] as? String, "receipt")
        XCTAssertNotNil(purchase["evidence"] as? String)
        XCTAssertEqual(fields["name"] as? String, open.name, "Reading a receipt changes no other field")
        XCTAssertTrue(fields["colours"] != nil && draft.colours == (open.colours ?? []).joined(separator: ", "))
        // Applying the same receipt twice produces the same fields, so a retry cannot add a second
        // purchase: the record is one field on the garment and the ordinary save is versioned.
        var again = draft
        again.purchaseDraft.amount = "149.00"; again.purchaseDraft.source = "receipt"
        let repeated = try XCTUnwrap(try again.fields()["purchase"] as? [String: Any])
        XCTAssertEqual(purchase as NSDictionary, repeated as NSDictionary)
        XCTAssertTrue(WardrobeDraftValidation.patch(try again.fields(), original: fields).isEmpty, "Re-applying the same receipt changes nothing")
        // A receipt-sourced purchase always keeps evidence; a labelled source without it is refused.
        var unlabelled = WardrobeGarmentDraft(open)
        unlabelled.purchaseDraft.amount = "149.00"; unlabelled.purchaseDraft.currency = "EUR"; unlabelled.purchaseDraft.source = "receipt"
        XCTAssertThrowsError(try unlabelled.fields(), "A recorded source needs its evidence")
    }

    func testConnectedReadingIsHeldToTheSameTextAndValidator() async throws {
        let task = WardrobeLanguageTasks.readReceipt()
        let text = "ACME OUTFITTERS\n2 Mar 2026\nTotal EUR 149.00\n"
        let draft = try task.parseAgent(#"{"date":"2 Mar 2026","total":"149.00","currency":"EUR","merchant":"ACME Outfitters"}"#, text)
        XCTAssertEqual(draft.date, "2026-03-02"); XCTAssertEqual(draft.amount, "149.00"); XCTAssertEqual(draft.currency, "EUR")
        XCTAssertNoThrow(try task.validate(draft))
        let invented = try task.parseAgent(#"{"total":"999.00","currency":"USD","merchant":"Somewhere Else"}"#, text)
        XCTAssertNil(invented.amount, "A total the receipt does not show cannot come from the agent")
        XCTAssertNil(invented.currency)
        XCTAssertNil(invented.merchant)
        XCTAssertTrue(invented.isEmpty)
        XCTAssertNoThrow(try task.validate(invented), "Reporting dropped figures is not an invalid reading")
        // The validator is what refuses a figure the gate would have let through.
        XCTAssertThrowsError(try task.validate(WardrobeReceiptDraft(date: nil, amount: "1,234.56", currency: "EUR", merchant: nil)),
                             "Only a normalized total passes")
        XCTAssertThrowsError(try task.validate(WardrobeReceiptDraft(date: nil, amount: nil, currency: "EUR", merchant: nil)),
                             "A currency without a total cannot be applied")
        XCTAssertThrowsError(try task.validate(WardrobeReceiptDraft(date: "2026-02-30", amount: nil, currency: nil, merchant: nil)))
        XCTAssertThrowsError(try task.validate(WardrobeReceiptDraft(date: nil, amount: nil, currency: nil, merchant: String(repeating: "é", count: 51))))
        XCTAssertEqual(try task.agentQuery(input: text).contains("ONLY JSON"), true, "The delegation carries the contract")
        XCTAssertThrowsError(try task.agentQuery(input: "   "))
    }
}
