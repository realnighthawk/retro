import SwiftUI

/// Today: what the day is, and the one thing in it.
///
/// The screen's job is to remove a decision. A person cannot hold four priorities at once, so the app picks the one
/// that matters most this morning and gives it the weight — everything else is available but deliberately quieter.
struct TodayView: View {
    @Binding var day: Day
    let wardrobe: [Garment]
    let open: (ProductivityDemoShell.Destination) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    VStack(spacing: 18) {
                        if let focus = day.focus { focusPanel(focus) }
                        agendaPanel
                        wearingPanel
                        recordPanel
                        provenance
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(day.date.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tok.accent)
                Text(day.date.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Tok.ink)
            }

            DayArc(
                progress: day.progress,
                nowLabel: day.nowLabel,
                startLabel: "06:00",
                endLabel: "23:00"
            )
            .padding(.horizontal, 8)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(day.kept)").font(.hero()).foregroundStyle(Tok.ink)
                Text("/ \(day.total) kept").font(.subheadline).foregroundStyle(Tok.faint)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Tok.heroTop, Tok.heroBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: The one thing

    private func focusPanel(_ goal: Goal) -> some View {
        Panel(tint: Tok.accent) {
            HStack(alignment: .top, spacing: 6) {
                Text("The one thing").font(.subheadline.weight(.semibold)).foregroundStyle(Tok.accent)
                Spacer()
                Text(goal.cadence.title).font(.caption).foregroundStyle(Tok.faint)
            }

            Text(goal.title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(goal.done ? Tok.faint : Tok.ink)
                .strikethrough(goal.done, color: Tok.faint)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("\(goal.streak) days running")
                    .figures(.caption, weight: .medium)
                    .foregroundStyle(goal.done ? Tok.good : Tok.faint)
                HistoryRow(history: goal.history, days: 12)
            }

            Button {
                toggleFocus()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: goal.done ? "arrow.uturn.backward" : "checkmark")
                        .font(.system(size: 15, weight: .bold))
                    Text(goal.done ? "Undo" : "Done for today")
                        .font(.headline)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 2)
        }
    }

    // MARK: Agenda

    private var agendaPanel: some View {
        Panel {
            SectionTitle(text: "The day", trailing: "\(day.agenda.filter(\.done).count) of \(day.agenda.count)")
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach($day.agenda) { $item in
                    Button {
                        withAnimation(Motion.state) { item.done.toggle() }
                        if item.done { Haptics.tap() }
                    } label: {
                        HStack(spacing: 12) {
                            Text(item.time)
                                .figures(.footnote, weight: .medium)
                                .foregroundStyle(Tok.faint)
                                .frame(width: 48, alignment: .leading)

                            Circle()
                                .fill(item.kind.color)
                                .frame(width: 7, height: 7)

                            Text(item.title)
                                .font(.body)
                                .foregroundStyle(item.done ? Tok.faint : Tok.ink)
                                .strikethrough(item.done, color: Tok.faint)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())

                    if item.id != day.agenda.last?.id {
                        Rectangle().fill(Tok.rule).frame(height: 1).padding(.leading, 67)
                    }
                }
            }
        }
    }

    // MARK: Wearing

    private var wearingPanel: some View {
        let worn = wornGarments
        return Button {
            open(.wardrobe)
        } label: {
            Panel {
                SectionTitle(text: "Wearing", trailing: day.outfit.summary).padding(.horizontal, 2)
                if worn.isEmpty {
                    Text("Nothing picked yet. The wardrobe will suggest something.")
                        .font(.subheadline)
                        .foregroundStyle(Tok.faint)
                } else {
                    HStack(spacing: 10) {
                        ForEach(worn) { garment in
                            GarmentTile(garment: garment)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Text("Picked at \(day.outfit.pickedAt)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Tok.faint)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Tok.faint)
                    .padding(18)
            }
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Record

    private var recordPanel: some View {
        Button {
            open(.review)
        } label: {
            Panel {
                SectionTitle(text: "Record", trailing: nil).padding(.horizontal, 2)
                Text(day.record.isEmpty ? "Nothing written yet." : day.record)
                    .font(.body)
                    .foregroundStyle(day.record.isEmpty ? Tok.faint : Tok.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "square.and.pencil")
                    .font(.footnote)
                    .foregroundStyle(Tok.faint)
                    .padding(18)
            }
        }
        .buttonStyle(PressStyle())
    }

    private var provenance: some View {
        Text("Example content. The /retro engine is not connected yet.")
            .font(.footnote)
            .foregroundStyle(Tok.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: Actions

    private var wornGarments: [Garment] {
        day.outfit.garmentIDs.compactMap { id in wardrobe.first { $0.id == id } }
    }

    private func toggleFocus() {
        guard let id = day.focusGoalID, let index = day.goals.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.state) { day.goals[index].done.toggle() }
        if day.goals[index].done {
            day.goals[index].streak += 1
            day.goals[index].history.append(true)
            Haptics.kept()
        } else {
            day.goals[index].streak = max(0, day.goals[index].streak - 1)
            if !day.goals[index].history.isEmpty { day.goals[index].history.removeLast() }
        }
    }
}
