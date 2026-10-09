import SwiftUI

/// Review: how it is actually going. A widening lens — the week, then the patterns, then the days themselves.
///
/// This is the surface where a productivity app usually turns into a report card. It does not here: every reading is
/// stated as a fact about days that happened, and a day that went badly is drawn exactly like a day that did not
/// happen, because neither is a failure to be corrected.
struct ReviewView: View {
    @Binding var entries: [Entry]
    let day: Day

    @State private var editing: Entry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    weekPanel
                    patternPanel
                    entriesPanel
                    provenance
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("Review")
            .sheet(item: $editing) { entry in
                EntryEditor(entry: entry) { updated in
                    if let index = entries.firstIndex(where: { $0.id == updated.id }) {
                        entries[index] = updated
                    }
                }
            }
        }
    }

    private var weekPanel: some View {
        Panel {
            SectionTitle(text: "This week", trailing: "\(day.week.filter { $0.kept >= 1 }.count) of 7 days")
                .padding(.horizontal, 2)
            WeekStrip(days: day.week, today: day.week.last?.id ?? "")
        }
    }

    /// Which days of the week actually work, from the record rather than from an opinion about the record.
    private var patternPanel: some View {
        Panel {
            SectionTitle(text: "When it holds", trailing: nil).padding(.horizontal, 2)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(byWeekday.enumerated()), id: \.offset) { _, pair in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(pair.share > 0 ? Tok.good.opacity(0.45 + 0.55 * pair.share) : Tok.raised)
                            .frame(height: max(6, 64 * pair.share))
                        Text(pair.letter).font(.caption2).foregroundStyle(Tok.faint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84, alignment: .bottom)

            Text(reading)
                .font(.caption)
                .foregroundStyle(Tok.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var entriesPanel: some View {
        Panel {
            SectionTitle(text: "The days", trailing: "\(entries.filter { !$0.cancelled }.count) recorded")
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.weekday)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Tok.ink)
                                Text(entry.dayLabel)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(Tok.faint)
                            }
                            .frame(width: 46, alignment: .leading)

                            if entry.cancelled {
                                Text("Void — kept, not counted")
                                    .font(.subheadline)
                                    .foregroundStyle(Tok.stamp)
                            } else {
                                Text(entry.text.isEmpty ? "Nothing written." : entry.text)
                                    .font(.subheadline)
                                    .foregroundStyle(entry.text.isEmpty ? Tok.faint : Tok.ink)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 6)

                            if let mood = entry.mood { MoodDots(mood: mood) }
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())

                    if entry.id != entries.last?.id {
                        Rectangle().fill(Tok.rule).frame(height: 1).padding(.leading, 58)
                    }
                }
            }
        }
    }

    private var provenance: some View {
        Text("Example content. The /retro engine is not connected yet.")
            .font(.footnote)
            .foregroundStyle(Tok.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private var byWeekday: [(letter: String, share: Double)] {
        let calendar = Calendar.current
        // Calendar weekday numbers are Sunday-first; the strip is Monday-first like the rest of the app.
        let order = [2, 3, 4, 5, 6, 7, 1]
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let recorded = entries.filter { !$0.cancelled }
        return order.enumerated().map { index, weekday in
            let onThisDay = recorded.filter { calendar.component(.weekday, from: $0.date) == weekday }
            let share = onThisDay.isEmpty ? 0 : Double(onThisDay.filter { ($0.mood ?? 0) >= 3 }.count) / Double(onThisDay.count)
            return (letters[index], share)
        }
    }

    private var reading: String {
        let best = byWeekday.enumerated().max { $0.element.share < $1.element.share }
        guard let best, best.element.share > 0 else { return "Not enough recorded yet to see a shape." }
        return "\(fullName(best.offset)) is the day this tends to hold. The record says so, not the plan."
    }

    private func fullName(_ index: Int) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][index]
    }
}

/// How the day felt, as five marks rather than a number. Read at a glance, never scored.
struct MoodDots: View {
    let mood: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { step in
                Circle()
                    .fill(step <= mood ? Tok.accent : Tok.raised)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Mood \(mood) of 5")
    }
}

/// The record for one day. Writing it should feel like closing a loop, not filling in a form.
struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    let save: (Entry) -> Void

    @State private var text: String = ""
    @State private var mood: Int?
    @State private var cancelled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(.dateTime.weekday(.wide)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tok.accent)
                        Text(entry.date.formatted(.dateTime.day().month(.wide).year()))
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(Tok.ink)
                    }

                    TextField("What happened", text: $text, axis: .vertical)
                        .font(.body)
                        .lineLimit(6...16)
                        .padding(14)
                        .background(Tok.raised, in: RoundedRectangle(cornerRadius: Tok.radiusInner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tok.radiusInner, style: .continuous).strokeBorder(Tok.rule))

                    Panel {
                        SectionTitle(text: "How it felt", trailing: mood.map { "\($0) of 5" }).padding(.horizontal, 2)
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { step in
                                Button {
                                    mood = (mood == step) ? nil : step
                                    Haptics.select()
                                } label: {
                                    Circle()
                                        .fill(step <= (mood ?? 0) ? Tok.accent : Tok.raised)
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(Tok.rule))
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel("\(step) of 5")
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    Panel {
                        Toggle(isOn: $cancelled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mark this day void")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Tok.ink)
                                Text("The day is kept and will not count. Nothing is deleted.")
                                    .font(.caption)
                                    .foregroundStyle(Tok.faint)
                            }
                        }
                        .tint(Tok.stamp)
                        .frame(minHeight: 44)
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("The record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = entry
                        updated.text = text
                        updated.mood = mood
                        updated.cancelled = cancelled
                        save(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            text = entry.text
            mood = entry.mood
            cancelled = entry.cancelled
        }
    }
}
