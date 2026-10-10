import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *) @Generable
enum AssistedGarmentCategory {
    case top, bottom, one_piece, outerwear, footwear, accessory, other
    var wire: String {
        switch self {
        case .top: "top"
        case .bottom: "bottom"
        case .one_piece: "one_piece"
        case .outerwear: "outerwear"
        case .footwear: "footwear"
        case .accessory: "accessory"
        case .other: "other"
        }
    }
}

@available(iOS 26.0, *) @Generable
struct AssistedGarmentDetails {
    @Guide(description: "A short garment name supported by the owner's input; nil if unclear.") var name: String?
    @Guide(description: "A category supported by the owner's input; nil if unclear.") var category: AssistedGarmentCategory?
    @Guide(description: "An explicitly described subtype, otherwise nil.") var subtype: String?
    @Guide(description: "A brand written in the owner's description or printed on the label, copied as written. Never guess a brand. Otherwise nil.") var brand: String?
    @Guide(description: "A material the text states, copied in its own words, for example cotton or wool. Otherwise nil.") var material: String?
    @Guide(description: "A pattern the text states, for example striped or herringbone. Otherwise nil.") var pattern: String?
    @Guide(description: "A style or garment type the text states, for example blazer or trench. Otherwise nil.") var style: String?
    @Guide(description: "A fit the text or label states, for example slim or oversized. Otherwise nil.") var fit: String?
    @Guide(description: "Only garment colours the text states, at most five, copied as written.") var colours: [String]
    @Guide(description: "Only seasons the text states, at most four, for example winter or summer.") var seasons: [String]
    @Guide(description: "A short factual description from the input, no styling advice or care instructions.") var description: String?
}
#endif

struct WardrobeAssistedDraft {
    let name: String?
    let category: String?
    let subtype: String?
    var colours: [String]
    let notes: String?
    var brand: String? = nil
    var material: String? = nil
    var pattern: String? = nil
    var style: String? = nil
    var fit: String? = nil
    var seasons: [String] = []
    // Values the model returned that the supplied text does not actually contain. They are reported to
    // the owner instead of being proposed, so a suggestion can never invent a brand or a material.
    var dropped: [String] = []

    func validate() throws {
        if let category, !WardrobeVocabulary.categories.contains(category) { throw WardrobeWriteError("The suggestion has an unsupported category.") }
        try WardrobeDraftValidation.strings(["name": name ?? "", "subtype": subtype ?? "", "notes": notes ?? "",
                                             "brand": brand ?? "", "material": material ?? "", "pattern": pattern ?? "", "style": style ?? "", "fit": fit ?? ""])
        guard colours.count <= 5, Set(colours).count == colours.count, colours.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 100 }),
              seasons.count <= 10, Set(seasons).count == seasons.count, seasons.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 100 }),
              dropped.count <= 20, dropped.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 300 }) else { throw WardrobeWriteError("The suggested details are not valid.") }
    }
    // Only values the owner's own text contains are proposed. Everything else is dropped and reported:
    // a label can state a brand, a material or a fit, but a suggestion may not infer one.
    func onlyStated(in evidence: String) -> WardrobeAssistedDraft {
        var value = self
        let text = evidence.lowercased()
        func stated(_ field: String, _ candidate: String?) -> String? {
            guard let candidate, !candidate.isEmpty else { return nil }
            guard text.contains(candidate.lowercased()) else {
                value.dropped.append("\(field): \(candidate)")
                return nil
            }
            return candidate
        }
        value.brand = stated("Brand", brand); value.material = stated("Material", material)
        value.pattern = stated("Pattern", pattern); value.style = stated("Style", style); value.fit = stated("Fit", fit)
        let keptColours = colours.filter { colour in
            guard text.contains(colour.lowercased()) else { value.dropped.append("Colour: \(colour)"); return false }
            return true
        }
        let keptSeasons = seasons.filter { season in
            guard text.contains(season.lowercased()) else { value.dropped.append("Season: \(season)"); return false }
            return true
        }
        value.colours = keptColours; value.seasons = keptSeasons
        return value
    }
}

enum GarmentAssistance {
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: return model.supportsLocale() ? nil : "Apple's on-device model does not support this language. Manual entry still works."
            case .unavailable(.deviceNotEligible): return "This device does not support Apple Intelligence. Manual entry still works."
            case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in Settings to use on-device assistance. Manual entry still works."
            case .unavailable(.modelNotReady): return "Apple's on-device model is not ready. Manual entry still works."
            default: return "On-device suggestions are unavailable. Manual entry still works."
            }
        }
        #endif
        return "On-device text suggestions need iOS 26 and an eligible Apple Intelligence device. Manual entry still works."
    }
    // The text the owner supplied is read by whichever executor is allowed and available. Both paths
    // run the same literal check and the same bounds, so a connected answer cannot invent a brand.
    static func suggest(description: String, label: String, agent: WardrobeLanguageExecutor? = nil) async throws -> (draft: WardrobeAssistedDraft, route: WardrobeLanguageRoute) {
        guard description.utf8.count + label.utf8.count <= 6000, !(description + label).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WardrobeWriteError("Use a short description or scanned label (up to 6000 UTF-8 bytes).") }
        let input = "Owner description:\n\(description)\nRecognized label text (may contain OCR errors):\n\(label)"
        let answer = try await WardrobeLanguageDispatcher.run(WardrobeLanguageTasks.extractGarment(), input: input, agent: agent)
        return (answer.draft, answer.route)
    }
    // Used by the task's on-device executor and by tests; it does no bounds check of its own.
    static func deviceDraft(_ input: String) async throws -> WardrobeAssistedDraft {
        if let problem = unavailableReason { throw WardrobeWriteError(problem) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: WardrobeLanguageTasks.extractInstructions)
            let response = try await session.respond(to: input, generating: AssistedGarmentDetails.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 400))
            try Task.checkCancellation()
            let details = response.content
            return WardrobeAssistedDraft(name: details.name, category: details.category?.wire, subtype: details.subtype, colours: details.colours, notes: details.description,
                                         brand: details.brand, material: details.material, pattern: details.pattern, style: details.style, fit: details.fit, seasons: details.seasons)
                .onlyStated(in: input)
        }
        #endif
        throw WardrobeWriteError("On-device suggestions are unavailable.")
    }
}
