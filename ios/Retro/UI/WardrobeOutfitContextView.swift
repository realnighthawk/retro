import SwiftUI

struct WardrobeOutfitContextSections: View {
    let facts: WardrobeOutfitContext
    var body: some View {
        Section("Connected coverage") {
            Text("Read \(facts.retrievedAt.formatted(date: .abbreviated, time: .shortened)) · expires \(facts.expiresAt.formatted(date: .omitted, time: .shortened))").font(.footnote)
            if Date() >= facts.expiresAt { Text("Expired. Retrieve fresh context before using it.").foregroundStyle(Tok.stamp) }
            Text("The agent maps a bounded selection of provider values. Review the context before using it. Empty lists do not establish no events or no travel. Travel entries do not prove a booking.").font(.footnote)
            ForEach(facts.coverage, id: \.kind) { coverage in
                VStack(alignment: .leading, spacing: 4) {
                    Text(WardrobeVocabulary.title(coverage.kind) + " · " + WardrobeVocabulary.title(coverage.status)).font(.headline)
                    if !coverage.reason.isEmpty { Text(coverage.reason).font(.footnote) }
                }
            }
        }
        if let weather = facts.weather {
            Section("Weather · \(weather.location)") {
                Text("\(weather.day) · \(weather.timeZone)").font(.footnote)
                if let low = weather.lowC { LabeledContent("Low", value: String(format: "%.1f °C", low)) }
                if let high = weather.highC { LabeledContent("High", value: String(format: "%.1f °C", high)) }
                if let condition = weather.condition { Text(condition).textSelection(.enabled) }
                if let issued = weather.issuedAt { Text("Issued \(issued.formatted(date: .abbreviated, time: .shortened))").font(.footnote) }
                else { Text("Provider issue time is unknown. The source read time does not establish the forecast's cache age.").font(.footnote).foregroundStyle(.secondary) }
                source(weather.source)
            }
        }
        ForEach(facts.calendar + facts.travel) { event in
            Section(event.id.hasPrefix("t") ? "Agent-selected travel context" : "Calendar context") {
                Text(event.title).font(.headline).textSelection(.enabled)
                Text(eventTime(event)).font(.footnote)
                if let location = event.location { Text(location) }
                source(event.source)
            }
        }
    }
    private func source(_ value: WardrobeOutfitContext.Source) -> some View {
        DisclosureGroup("Source · " + value.connection) {
            Text(value.tool).font(.footnote)
            Text("Read \(value.readAt.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
            Text(value.id).font(.caption).textSelection(.enabled)
            ForEach(value.pointers.keys.sorted(), id: \.self) { key in Text(WardrobeVocabulary.title(key) + " → " + value.pointers[key]!).font(.caption).textSelection(.enabled) }
        }
    }
    private func eventTime(_ event: WardrobeOutfitContext.Event) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = event.allDay ? .none : .short; f.timeZone = TimeZone(identifier: event.timeZone)
        return "\(f.string(from: event.start)) – \(f.string(from: event.end)) · \(event.timeZone)" + (event.allDay ? " · all-day, end exclusive" : "")
    }
}
