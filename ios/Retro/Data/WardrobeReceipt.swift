import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// A purchase read from a receipt or a label. Everything here is a proposal the owner reviews: the
// amount is a plain decimal in major units, the currency must be stated, and the recognized text
// becomes the evidence the saved record keeps.
struct WardrobeReceiptDraft: Equatable {
    var date: String?
    var amount: String?
    var currency: String?
    var merchant: String?
    var dropped: [String] = []

    // Only currencies a receipt can spell out unambiguously; a bare "dollar" or "$" is never guessed.
    static let currencyNames = ["us dollar": "USD", "us dollars": "USD", "euro": "EUR", "euros": "EUR",
                                "british pound": "GBP", "pound sterling": "GBP", "japanese yen": "JPY", "yen": "JPY"]

    var isEmpty: Bool { date == nil && amount == nil && currency == nil }
    // The one validation both readers run, so a connected answer cannot contain a figure the on-device
    // path would have refused.
    func validate() throws {
        if let date, WardrobeDraftValidation.date(date) == nil { throw WardrobeWriteError("The purchase date is not a calendar date. Read the receipt again.") }
        if let amount, Self.literalAmount(amount) != amount { throw WardrobeWriteError("The total is not a plain amount. Read the receipt again.") }
        if let currency, currency.count != 3 || !currency.allSatisfy({ $0.isASCII && $0.isUppercase }) { throw WardrobeWriteError("The currency is not a three-letter code. Read the receipt again.") }
        if let merchant, merchant.utf8.count > 100 { throw WardrobeWriteError("The merchant name is too long. Read the receipt again.") }
        guard currency == nil || amount != nil else { throw WardrobeWriteError("A currency without a total cannot be applied.") }
        guard dropped.count <= 10, dropped.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 200 }) else { throw WardrobeWriteError("Too many unreadable figures. Read the receipt again.") }
    }
    var summary: String {
        var parts: [String] = []
        if let date { parts.append("Date: \(date)") }
        if let amount, let currency { parts.append("Total: \(amount) \(currency)") }
        else if let amount { parts.append("Total: \(amount) (no currency read — choose it yourself)") }
        if let merchant, !merchant.isEmpty { parts.append("From: \(merchant)") }
        return parts.isEmpty ? "Nothing readable was found in this text." : parts.joined(separator: " · ")
    }

    // Only figures the supplied text actually shows are proposed. A symbol-only currency, a numeric
    // date that could be read two ways, or a total in another number format is reported instead of guessed.
    func onlyStated(in text: String) -> WardrobeReceiptDraft {
        var value = WardrobeReceiptDraft(merchant: merchant)
        let lower = text.lowercased()
        if let amount {
            if let normalized = Self.literalAmount(amount), Self.digitsAppear(amount: normalized, in: text) {
                value.amount = normalized
            } else {
                value.dropped.append("Total: \(amount)")
            }
        }
        if let currency {
            let code = Self.literalCurrency(currency, text: lower)
            if let code { value.currency = code } else { value.dropped.append("\(currency) — choose the currency yourself") }
        }
        if let date {
            if let normalized = Self.literalDate(date, text: lower) { value.date = normalized } else { value.dropped.append("Date \(date) — could not be read unambiguously") }
        }
        if let merchant, !merchant.isEmpty, !lower.contains(merchant.lowercased()) { value.merchant = nil }
        if value.amount == nil { value.currency = nil }
        return value
    }

    // "1,234.56" is normalized. A comma is only ever a grouping separator when a decimal point
    // follows it, because "1,50" and "12,345" read differently in different countries.
    static func literalAmount(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard !parts[0].isEmpty, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              groups.count == 1 || parts.count == 2 && (1...3).contains(groups[0].count) && groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        if parts.count == 2, parts[1].isEmpty || parts[1].count > 3 || !parts[1].allSatisfy(\.isNumber) { return nil }
        let digits = groups.joined()
        return parts.count == 2 ? "\(digits).\(parts[1])" : String(digits)
    }
    static func digitsAppear(amount: String, in text: String) -> Bool {
        text.replacingOccurrences(of: ",", with: "").contains(amount)
    }
    static func literalCurrency(_ candidate: String, text: String) -> String? {
        let code = candidate.trimmingCharacters(in: .whitespaces).uppercased()
        if code.count == 3, code.allSatisfy({ $0.isASCII && $0.isUppercase }), text.contains(code.lowercased()) {
            return code
        }
        // A spelled-out currency is only accepted when the text names it unambiguously.
        for (name, mapped) in currencyNames where text.contains(name) { return mapped }
        return nil
    }
    // Returns the record's ISO date, and only when the receipt itself shows that date: either an ISO
    // date or a date spelled with a month name. An all-numeric date is never converted, because
    // 03/02/2026 reads as two different days in different countries.
    static func literalDate(_ candidate: String, text: String) -> String? {
        let value = candidate.trimmingCharacters(in: .whitespaces)
        if WardrobeDraftValidation.date(value) != nil { return text.contains(value) ? value : nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["d MMMM yyyy", "d MMM yyyy", "MMMM d, yyyy", "MMM d, yyyy"] {
            formatter.dateFormat = format
            guard let date = formatter.date(from: value), text.contains(formatter.string(from: date).lowercased()) else { continue }
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *) @Generable
struct AssistedReceiptDetails {
    @Guide(description: "The purchase date exactly as the receipt shows it, or nil when it is unreadable. Never reformat an all-numeric date; copy it as printed.") var date: String?
    @Guide(description: "The final total as printed, digits only with its decimal point, for example 49.99. Nil for anything else.") var total: String?
    @Guide(description: "A three-letter currency code printed on the receipt, or a currency it names in full. Nil if only a symbol such as $ appears.") var currency: String?
    @Guide(description: "The shop or merchant name printed on the receipt, copied as written, or nil.") var merchant: String?
}
#endif

struct WardrobeReceiptReply: Codable {
    var date: String?
    var total: String?
    var currency: String?
    var merchant: String?
}
enum WardrobeReceiptAssistance {
    // Reviewed receipt text, read by whichever executor is allowed and available under one validator.
    static func read(_ text: String, agent: WardrobeLanguageExecutor? = nil) async throws -> (draft: WardrobeReceiptDraft, route: WardrobeLanguageRoute) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 6000 else { throw WardrobeWriteError("Scan or type the receipt first (up to 6000 UTF-8 bytes).") }
        let answer = try await WardrobeLanguageDispatcher.run(WardrobeLanguageTasks.readReceipt(), input: trimmed, agent: agent)
        return (answer.draft, answer.route)
    }
    // Used by the task's on-device executor and by tests; it does no validation of its own.
    static func deviceDraft(_ text: String) async throws -> WardrobeReceiptDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = GarmentAssistance.unavailableReason { throw WardrobeWriteError(problem) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: WardrobeLanguageTasks.receiptInstructions)
            let response = try await session.respond(to: "Receipt text (may contain OCR errors):\n\(trimmed)", generating: AssistedReceiptDetails.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 200))
            try Task.checkCancellation()
            let details = response.content
            return WardrobeReceiptDraft(date: details.date, amount: details.total, currency: details.currency, merchant: details.merchant)
                .onlyStated(in: trimmed)
        }
        #endif
        throw WardrobeWriteError("On-device receipt reading needs iOS 26 and an eligible Apple Intelligence device. Enter the purchase details yourself.")
    }
}
