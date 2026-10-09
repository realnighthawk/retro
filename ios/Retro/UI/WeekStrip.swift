import SwiftUI

/// The week so far: one cell per day, the bar in each showing how much of that day was kept.
///
/// This is a reading, not a score. A day with nothing kept draws a short bar rather than a red mark, and a day marked
/// void is hatched rather than blank, because the app does not pretend a day did not happen.
struct WeekStrip: View {
    let days: [DayMark]
    let today: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                cell(day)
            }
        }
    }

    // Split out of `body` deliberately: the whole strip in one expression is more than the type checker will solve.
    private func cell(_ day: DayMark) -> some View {
        let isToday = day.id == today
        return VStack(spacing: 7) {
            Text(day.letter)
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Tok.ink : Tok.faint)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Tok.raised)

                if day.void {
                    Text("–")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Tok.stamp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Tok.stamp.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else if day.kept > 0 {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Tok.good.opacity(0.55 + 0.45 * day.kept))
                        .frame(height: max(7, 44 * day.kept))
                }
            }
            .frame(height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isToday ? Tok.accent : Tok.rule, lineWidth: isToday ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(day.letter)
        .accessibilityValue(day.void ? "Marked void" : "\(Int(day.kept * 100)) percent kept")
    }
}

#Preview {
    WeekStrip(
        days: [
            DayMark(id: "0", letter: "M", kept: 1, void: false),
            DayMark(id: "1", letter: "T", kept: 0.5, void: false),
            DayMark(id: "2", letter: "W", kept: 0, void: true),
            DayMark(id: "3", letter: "T", kept: 0.75, void: false),
            DayMark(id: "4", letter: "F", kept: 0.25, void: false),
            DayMark(id: "5", letter: "S", kept: 0, void: false),
            DayMark(id: "6", letter: "S", kept: 0.5, void: false)
        ],
        today: "6"
    )
    .padding(20)
    .background(Tok.bg)
}
