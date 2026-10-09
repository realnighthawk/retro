package org.nighthawklabs.retro.data

import java.time.LocalDate

fun WardrobeAnalysisQuery.validatePeriod() {
    val day = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")
    require(day.matches(from) && day.matches(to) && runCatching { LocalDate.parse(from).toString() == from && LocalDate.parse(to).toString() == to }.getOrDefault(false) && from <= to) { "Choose valid dates with From before or equal to Through." }
}
fun WardrobeAnalysis.periodSummary(query: WardrobeAnalysisQuery): String {
    query.validatePeriod()
    require(from == query.from && to == query.to && outfitEvents >= 0 && wearDays in 0..outfitEvents && garments >= 0 && unwornGarments in 0..garments && categories.map { it.category }.distinct().size == categories.size) { "The review counts do not match this period. Refresh the review." }
    var total = 0L; var unused = 0L
    for (category in categories) {
        require(category.category in WardrobeVocabulary.categories && category.garments >= 0 && category.wornGarments in 0..category.garments && category.wearEvents >= category.wornGarments) { "Invalid category counts." }
        total = Math.addExact(total, category.garments); unused = Math.addExact(unused, category.garments - category.wornGarments)
    }
    require(total == garments && unused == unwornGarments) { "Category totals do not match the review." }
    return "$outfitEvents confirmed outfit ${if (outfitEvents == 1L) "event" else "events"} across $wearDays ${if (wearDays == 1L) "day" else "days"}. $unwornGarments of $garments ${if (garments == 1L) "garment" else "garments"} had no confirmed wear in this period."
}
