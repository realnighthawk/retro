import Foundation

extension WardrobeAnalysisQuery {
    func validatePeriod() throws {
        guard WardrobeDraftValidation.date(from) != nil, WardrobeDraftValidation.date(to) != nil, from <= to else { throw WardrobeWriteError("Choose valid dates with From before or equal to Through.") }
    }
}
extension WardrobeAnalysis {
    func periodSummary(_ query: WardrobeAnalysisQuery) throws -> String {
        try query.validatePeriod()
        guard from == query.from, to == query.to, outfitEvents >= 0, wearDays >= 0, wearDays <= outfitEvents, garments >= 0, unwornGarments >= 0, unwornGarments <= garments,
              Set(categories.map(\.category)).count == categories.count else { throw WardrobeWriteError("The review counts do not match this period. Refresh the review.") }
        var total: Int64 = 0, unused: Int64 = 0
        for category in categories {
            guard WardrobeVocabulary.categories.contains(category.category), category.garments >= 0, category.wornGarments >= 0, category.wornGarments <= category.garments, category.wearEvents >= category.wornGarments else { throw WardrobeWriteError("Invalid category counts.") }
            let count = total.addingReportingOverflow(category.garments)
            let unworn = unused.addingReportingOverflow(category.garments - category.wornGarments)
            guard !count.overflow, !unworn.overflow else { throw WardrobeWriteError("Review counts exceed their limit.") }
            total = count.partialValue; unused = unworn.partialValue
        }
        guard total == garments, unused == unwornGarments else { throw WardrobeWriteError("Category totals do not match the review.") }
        return "\(outfitEvents) confirmed outfit \(outfitEvents == 1 ? "event" : "events") across \(wearDays) \(wearDays == 1 ? "day" : "days"). \(unwornGarments) of \(garments) \(garments == 1 ? "garment" : "garments") had no confirmed wear in this period."
    }
}
