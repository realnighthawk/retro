import SwiftUI

/// The wardrobe: what you own, and what you are wearing today.
///
/// The top of the screen is the decision, not the inventory. A person opening this in the morning wants to be told
/// something, so the app proposes an outfit from the weather and what has not been worn lately, and leaves the full
/// rail underneath for when they disagree.
struct WardrobeView: View {
    @Binding var wardrobe: [Garment]
    @Binding var day: Day

    @State private var slot: Garment.Slot?
    @State private var composing = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    todayPanel
                    railPanel
                    provenance
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("Wardrobe")
            .sheet(isPresented: $composing) {
                OutfitComposer(wardrobe: wardrobe, day: $day)
            }
        }
    }

    // MARK: Today

    private var todayPanel: some View {
        let worn = day.outfit.garmentIDs.compactMap { id in wardrobe.first { $0.id == id } }
        return Panel(tint: worn.isEmpty ? Tok.accent : nil) {
            SectionTitle(text: "Today", trailing: day.outfit.summary).padding(.horizontal, 2)

            if worn.isEmpty {
                Text("Nothing picked yet.")
                    .font(.body)
                    .foregroundStyle(Tok.faint)
            } else {
                HStack(spacing: 10) {
                    ForEach(worn) { garment in
                        GarmentTile(garment: garment)
                    }
                    Spacer(minLength: 0)
                }
            }

            Button(worn.isEmpty ? "Pick something" : "Change it") {
                composing = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Rail

    private var railPanel: some View {
        Panel {
            SectionTitle(text: "The rail", trailing: "\(wardrobe.count) pieces").padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", active: slot == nil) { slot = nil }
                    ForEach(Garment.Slot.allCases) { candidate in
                        chip(candidate.title, active: slot == candidate) { slot = candidate }
                    }
                }
                .padding(.horizontal, 2)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(visible) { garment in
                    NavigationLink {
                        GarmentDetailView(garment: garment)
                    } label: {
                        GarmentTile(garment: garment, selected: day.outfit.garmentIDs.contains(garment.id))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.state) { action() }
        } label: {
            Text(label)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Tok.surface : Tok.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(active ? Tok.accent : Tok.raised, in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var visible: [Garment] {
        guard let slot else { return wardrobe }
        return wardrobe.filter { $0.slot == slot }
    }

    private var provenance: some View {
        Text("Example content. The /retro engine is not connected yet.")
            .font(.footnote)
            .foregroundStyle(Tok.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// One garment in full: how hard it works, and when it was last out.
struct GarmentDetailView: View {
    let garment: Garment

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GarmentTile(garment: garment)
                    .frame(maxWidth: 220)
                    .padding(.top, 8)

                Panel {
                    Text(garment.name)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Tok.ink)

                    HStack(spacing: 22) {
                        stat("\(garment.timesWorn)", "times worn")
                        stat(lastWorn, "last worn")
                        stat(garment.warmth.title, "warmth")
                    }
                }

                Panel {
                    SectionTitle(text: "Where it sits", trailing: nil).padding(.horizontal, 2)
                    Text("\(garment.slot.title) · \(garment.tone.title). It is one of \(garment.timesWorn) wears, which is \(verdict).")
                        .font(.body)
                        .foregroundStyle(Tok.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Tok.bg)
        .navigationTitle(garment.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).figures(.title3, weight: .semibold).foregroundStyle(Tok.ink)
            Text(label).font(.caption2).foregroundStyle(Tok.faint)
        }
    }

    private var lastWorn: String {
        guard let days = garment.lastWornDaysAgo else { return "never" }
        return days == 0 ? "today" : "\(days)d ago"
    }

    /// Described, never scored: a number of wears is a fact about a garment, not a grade for its owner.
    private var verdict: String {
        switch garment.timesWorn {
        case ..<10: "still finding its place"
        case ..<40: "in the regular rotation"
        default: "one of the ones you actually reach for"
        }
    }
}

/// The outfit composer. It leads with a proposal rather than an empty grid, because deciding is the hard part and the
/// app is supposed to be doing that.
struct OutfitComposer: View {
    @Environment(\.dismiss) private var dismiss
    let wardrobe: [Garment]
    @Binding var day: Day

    @State private var picked: [UUID] = []
    @State private var shuffles = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    proposal

                    ForEach(Garment.Slot.allCases) { slot in
                        let items = wardrobe.filter { $0.slot == slot }
                        if !items.isEmpty {
                            Text(slot.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Tok.ink)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                                ForEach(items) { garment in
                                    Button {
                                        toggle(garment)
                                    } label: {
                                        GarmentTile(garment: garment, selected: picked.contains(garment.id))
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Tok.bg)
            .navigationTitle("Wear today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Wear") { commit() }.fontWeight(.semibold).disabled(picked.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Shuffle the suggestion") {
                    withAnimation(Motion.state) { pick() }
                    shuffles += 1
                }
                .buttonStyle(QuietButtonStyle())
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
        }
        .onAppear { if picked.isEmpty { pick() } }
    }

    private var proposal: some View {
        Panel(tint: Tok.accent) {
            Text("\(day.outfit.summary) — suggested")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tok.accent)
            Text("One piece from each layer, leaning on what you have not worn this week.")
                .font(.subheadline)
                .foregroundStyle(Tok.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A suggestion, not an algorithm: one of each slot, preferring garments that have not been out for a while.
    private func pick() {
        var chosen: [UUID] = []
        for slot in Garment.Slot.allCases {
            let items = wardrobe
                .filter { $0.slot == slot }
                .sorted { ($0.lastWornDaysAgo ?? 99) > ($1.lastWornDaysAgo ?? 99) }
            // Warm pieces for the outer layer, since the summary is a cold morning.
            if slot == .outer, let warm = items.first(where: { $0.warmth == .warm }) {
                chosen.append(warm.id)
            } else if let first = items.first {
                chosen.append(first.id)
            }
        }
        picked = chosen
    }

    private func toggle(_ garment: Garment) {
        if let index = picked.firstIndex(of: garment.id) {
            picked.remove(at: index)
        } else {
            // One per slot: two hats is not an outfit.
            picked.removeAll { id in wardrobe.first { $0.id == id }?.slot == garment.slot }
            picked.append(garment.id)
        }
        Haptics.tap()
    }

    private func commit() {
        day.outfit.garmentIDs = picked
        day.outfit.pickedAt = Date.now.formatted(date: .omitted, time: .shortened)
        Haptics.kept()
        dismiss()
    }
}
