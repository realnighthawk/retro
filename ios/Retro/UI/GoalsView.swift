import SwiftUI

/// Goals: the long game. Grouped by the part of life they belong to, because that is how a person remembers them.
struct GoalsView: View {
    @Binding var goals: [Goal]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    summary
                    ForEach(Area.allCases) { area in
                        let inArea = goals.filter { $0.area == area }
                        if !inArea.isEmpty {
                            areaPanel(area, inArea)
                        }
                    }
                    provenance
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("Goals")
        }
    }

    private var summary: some View {
        Panel(tint: Tok.good) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(keptToday)").font(.hero(38)).foregroundStyle(Tok.ink)
                Text("/ \(goals.count) kept today").font(.subheadline).foregroundStyle(Tok.faint)
            }
            Text("\(longestRun) days is your longest run right now.")
                .font(.subheadline)
                .foregroundStyle(Tok.faint)
        }
    }

    private func areaPanel(_ area: Area, _ inArea: [Goal]) -> some View {
        Panel {
            SectionTitle(text: area.title, trailing: "\(inArea.filter(\.done).count) of \(inArea.count)")
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(inArea) { goal in
                    GoalRow(goal: goal, toggle: { toggle(goal) }) {
                        GoalDetailView(goal: binding(for: goal))
                    }

                    if goal.id != inArea.last?.id {
                        Rectangle().fill(Tok.rule).frame(height: 1).padding(.leading, 44)
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

    private var keptToday: Int { goals.filter(\.done).count }
    private var longestRun: Int { goals.map(\.streak).max() ?? 0 }

    private func binding(for goal: Goal) -> Binding<Goal> {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else {
            return .constant(goal)
        }
        return $goals[index]
    }

    private func toggle(_ goal: Goal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        withAnimation(Motion.state) { goals[index].done.toggle() }
        if goals[index].done {
            goals[index].streak += 1
            goals[index].history.append(true)
            Haptics.kept()
        } else {
            goals[index].streak = max(0, goals[index].streak - 1)
            if !goals[index].history.isEmpty { goals[index].history.removeLast() }
        }
    }
}

/// One goal, in full: the whole run rather than the last two weeks, what it is for, and how often it is meant to happen.
struct GoalDetailView: View {
    @Binding var goal: Goal

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 8)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                runPanel
                if !goal.note.isEmpty { notePanel }
                cadencePanel
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Tok.bg)
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        Panel(tint: goal.done ? Tok.good : Tok.accent) {
            Text(goal.title)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Tok.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 22) {
                stat("\(goal.streak)", "days running")
                stat("\(goal.keptRecently)", "of last 30")
                stat(goal.cadence.title, "cadence")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).figures(.title3, weight: .semibold).foregroundStyle(Tok.ink)
            Text(label).font(.caption2).foregroundStyle(Tok.faint)
        }
    }

    /// Eight weeks of days, oldest week first. A gap is a gap: it is drawn recessed, never as a failure.
    private var runPanel: some View {
        Panel {
            SectionTitle(text: "The run", trailing: "8 weeks")
                .padding(.horizontal, 2)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(goal.history.suffix(56).enumerated()), id: \.offset) { _, kept in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(kept ? Tok.good : Tok.raised)
                        .frame(height: 26)
                }
            }
            .accessibilityHidden(true)

            Text("\(goal.keptRecently) of the last 30 days. The grey squares are days that did not happen, which is different from days that went badly.")
                .font(.caption)
                .foregroundStyle(Tok.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notePanel: some View {
        Panel {
            SectionTitle(text: "Why", trailing: nil).padding(.horizontal, 2)
            TextField("Why this matters", text: $goal.note, axis: .vertical)
                .font(.body)
                .lineLimit(3...10)
                .foregroundStyle(Tok.ink)
        }
    }

    private var cadencePanel: some View {
        Panel {
            SectionTitle(text: "How often", trailing: nil).padding(.horizontal, 2)
            Picker("Cadence", selection: cadenceBinding) {
                Text("Every day").tag(Cadence.daily)
                Text("Weekdays").tag(Cadence.weekdays)
                Text("3× a week").tag(Cadence.timesPerWeek(3))
                Text("2× a week").tag(Cadence.timesPerWeek(2))
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var cadenceBinding: Binding<Cadence> {
        Binding(get: { goal.cadence }, set: { goal.cadence = $0 })
    }
}
