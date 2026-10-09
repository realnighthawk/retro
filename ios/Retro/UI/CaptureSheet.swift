import SwiftUI

/// Capture: the three things worth interrupting yourself for, at most two taps from any surface.
///
/// Deliberately not a general-purpose composer. If recording something takes longer than the thought took, the app has
/// made the owner worse at their day, not better.
struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goals: [Goal]
    @Binding var day: Day
    let wardrobe: [Garment]

    @State private var note = ""
    @State private var mode: Mode = .choose
    @State private var picked: [UUID] = []

    private enum Mode { case choose, tick, note, wear }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .choose: chooser
                case .tick: ticker
                case .note: noter
                case .wear: wearer
                }
            }
            .background(Tok.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if mode != .choose {
                        Button("Back") { withAnimation(Motion.state) { mode = .choose } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch mode {
        case .choose: "Capture"
        case .tick: "Tick a goal"
        case .note: "Note the day"
        case .wear: "What I wore"
        }
    }

    private var chooser: some View {
        VStack(spacing: 12) {
            choice("Tick a goal", "checkmark.circle", .tick)
            choice("Note the day", "text.alignleft", .note)
            choice("Log what I wore", "hanger", .wear)
            Spacer()
        }
        .padding(20)
    }

    private func choice(_ label: String, _ symbol: String, _ next: Mode) -> some View {
        Button {
            withAnimation(Motion.state) { mode = next }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                Text(label).font(.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote)
            }
            .foregroundStyle(Tok.ink)
            .padding(16)
            .background(Tok.surface, in: RoundedRectangle(cornerRadius: Tok.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tok.radius, style: .continuous).strokeBorder(Tok.rule))
            .frame(minHeight: 44)
        }
        .buttonStyle(PressStyle())
    }

    private var ticker: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach($goals) { $goal in
                    Button {
                        withAnimation(Motion.state) { goal.done.toggle() }
                        if goal.done { Haptics.kept() }
                    } label: {
                        HStack(spacing: 14) {
                            TickBox(done: goal.done)
                            Text(goal.title)
                                .font(.body)
                                .foregroundStyle(goal.done ? Tok.faint : Tok.ink)
                                .strikethrough(goal.done, color: Tok.faint)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var noter: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("What happened today", text: $note, axis: .vertical)
                .lineLimit(5...12)
                .font(.body)
                .padding(14)
                .background(Tok.raised, in: RoundedRectangle(cornerRadius: Tok.radiusInner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tok.radiusInner, style: .continuous).strokeBorder(Tok.rule))

            Button("Add to today's record") {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                day.record = day.record.isEmpty ? trimmed : day.record + "\n" + trimmed
                note = ""
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(20)
    }

    private var wearer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Garment.Slot.allCases) { slot in
                    let items = wardrobe.filter { $0.slot == slot }
                    if !items.isEmpty {
                        Text(slot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tok.ink)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                            ForEach(items) { garment in
                                Button {
                                    if let index = picked.firstIndex(of: garment.id) {
                                        picked.remove(at: index)
                                    } else {
                                        picked.append(garment.id)
                                    }
                                } label: {
                                    GarmentTile(garment: garment, selected: picked.contains(garment.id))
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                }

                Button("Wear this") {
                    day.outfit.garmentIDs = picked
                    Haptics.kept()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(picked.isEmpty)
            }
            .padding(20)
        }
    }
}
