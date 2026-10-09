import SwiftUI

/// A garment drawn as its tone. Photographs arrive with the wardrobe domain; nothing here depends on them, so the
/// layout will not change when they do.
struct GarmentTile: View {
    let garment: Garment
    var selected = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [garment.tone.color, garment.tone.color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: garment.slot.symbol)
                    .font(.title3)
                    .foregroundStyle(garment.tone.onColor)
            }
            .frame(height: 74)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Tok.accent : Tok.rule, lineWidth: selected ? 2 : 1)
            }

            Text(garment.name)
                .font(.caption2)
                .foregroundStyle(Tok.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 44)
    }
}

extension Garment.Tone {
    /// Garment colour is content, so it may sit outside the UI palette — but it still has to hold up in both
    /// appearances and against its own glyph.
    var color: Color {
        Color(light: lightHex, dark: darkHex)
    }

    var onColor: Color {
        // Light garments take ink glyphs, dark garments take bone, in both appearances.
        switch self {
        case .bone, .sand: Color(light: 0x22251E, dark: 0x22251E)
        default: Color(light: 0xF7F5EF, dark: 0xF7F5EF)
        }
    }

    private var lightHex: UInt32 {
        switch self {
        case .ink: 0x2A2D26
        case .bone: 0xE8E3D6
        case .sand: 0xCBB894
        case .olive: 0x5E6B3C
        case .clay: 0xA2543A
        case .indigo: 0x33405E
        case .rust: 0x8E4A2A
        case .moss: 0x4F6B3A
        }
    }

    private var darkHex: UInt32 {
        switch self {
        case .ink: 0x3A3E34
        case .bone: 0xD8D2C2
        case .sand: 0xB8A382
        case .olive: 0x76874B
        case .clay: 0xB96A4C
        case .indigo: 0x4A5A80
        case .rust: 0xA85C38
        case .moss: 0x648A4A
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
        ForEach(DemoData.wardrobe) { garment in
            GarmentTile(garment: garment, selected: garment.slot == .outer)
        }
    }
    .padding(20)
    .background(Tok.bg)
}
