import SwiftUI

/// A drawn tick, not a glyph from a font: a rounded square that fills with sage and draws its own checkmark, so the
/// one action on this screen lands as a single authored motion rather than a symbol swap.
struct TickBox: View {
    let done: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(done ? Tok.good : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(done ? Tok.good : Tok.faint, lineWidth: 1.5)
                }
                .frame(width: 30, height: 30)

            Checkmark()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Tok.surface, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 11)
        }
        .shadow(color: done ? Tok.good.opacity(0.3) : .clear, radius: 6, y: 2)
    }
}

private struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// The recent run at a glance. Real recorded days, so a gap is information rather than a reproach.
///
/// A day that was not kept is `raised`, never a warning colour: the app describes what happened and is not allowed to
/// be disappointed about it. The only state colour here is sage, and it means the day was kept.
///
/// The count is capped here rather than at the call site, so a goal carrying a long history cannot push a row wider
/// than the screen.
struct HistoryRow: View {
    let history: [Bool]
    var days = 14

    var body: some View {
        let shown = Array(history.suffix(days))
        HStack(spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, kept in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(kept ? Tok.good : Tok.raised)
                    .frame(width: 4, height: 20)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One goal in a list: a tick you can hit without leaving the list, and a row you can open.
///
/// The two are separate controls rather than a button inside a link. Nested inside a `NavigationLink`, an inner button
/// swallows the tap and the row silently stops opening, which is exactly the kind of thing you only notice by driving
/// the real screen.
struct GoalRow<Destination: View>: View {
    let goal: Goal
    let toggle: () -> Void
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                TickBox(done: goal.done)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            // Named for the action, not the goal: the row beside it already carries the title, and two controls
            // sharing one accessible name is how VoiceOver ends up with a button nobody can predict.
            .accessibilityLabel(goal.done ? "Mark \(goal.title) as not kept" : "Mark \(goal.title) as kept")

            NavigationLink {
                destination()
            } label: {
                summary
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("goal-row-\(goal.title)")
        }
        .padding(.vertical, 6)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(goal.done ? Tok.faint : Tok.ink)
                    .strikethrough(goal.done, color: Tok.faint)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Text("\(goal.streak) days running")
                        .figures(.caption, weight: .medium)
                        .foregroundStyle(goal.done ? Tok.good : Tok.faint)
                    HistoryRow(history: goal.history, days: 10)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Tok.faint)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        VStack(spacing: 0) {
            GoalRow(
                goal: Goal(title: "Read 20 pages", done: true, streak: 12, history: [true, true, false, true, true, true, true, false, true, true, true, true, true, true]),
                toggle: {}
            ) { Text("detail") }
            GoalRow(
                goal: Goal(title: "Walk 8,000 steps", done: false, streak: 31, history: [true, true, true, false, true, true, true, true, true, true, false, true, true, true]),
                toggle: {}
            ) { Text("detail") }
        }
        .background(Tok.surface)
    }
}
