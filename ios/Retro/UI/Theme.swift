import SwiftUI
import UIKit

// MARK: - Palette

/// "Tranquil Earth / Sage & Clay": linen ground, unglazed pottery, and a garden.
///
/// The palette is deliberately small. Neutrals do all the structure — `bone` is the page, `paper` is anything that
/// sits on it, `sand` is anything recessed into it, `moss ink` is all text. Three colours carry meaning and nothing
/// else is coloured: **clay** is where you act, **sage** is what you kept, **rust** is a day marked void. Because
/// action and outcome are different colours, a screen can say both at once without either shouting.
///
/// Contrast, measured with the WCAG 2.1 relative-luminance formula, against the surface each token is used on.
/// Base appearances: ink 13.8-16.1:1, stone 4.6-7.5:1, clay 4.8-7.3:1, sage 5.3-8.5:1, rust 6.5-8.0:1.
/// Increased-contrast variants are carried by the token, so the system setting needs no per-view work.
enum Tok {
    static let bg = adaptive(0xF4F1EA, 0x131410, 0xFFFFFF, 0x000000)
    static let surface = adaptive(0xFFFDF8, 0x1B1D17, 0xFFFFFF, 0x12140F)
    static let raised = adaptive(0xEAE5DA, 0x252820, 0xE4DED0, 0x1E211A)
    static let rule = adaptive(0xDDD6C7, 0x33372D, 0xBDB5A3, 0x454A3E)
    static let ink = adaptive(0x22251E, 0xF2EFE6, 0x000000, 0xFFFFFF)
    static let faint = adaptive(0x6B6F62, 0xA3A79A, 0x4E5245, 0xC8CCBF)
    static let accent = adaptive(0xA2543A, 0xD9926F, 0x843F27, 0xEEB08D)
    static let good = adaptive(0x4F6B3A, 0x93BB74, 0x3B5229, 0xB0D492)
    static let stamp = adaptive(0x8E2F22, 0xE08A72, 0x71201A, 0xF2A894)

    /// The atmosphere behind the hero: sunrise over linen, and lamplight in a dark room.
    static let heroTop = adaptive(0xF9F6EF, 0x1C1F17, 0xFFFFFF, 0x16180F)
    static let heroBottom = adaptive(0xEFE9DB, 0x131410, 0xEFEADE, 0x000000)

    /// A tint of whichever colour is in charge of a surface.
    static func wash(_ colour: Color, _ amount: Double = 0.10) -> Color { colour.opacity(amount) }

    static let radius: CGFloat = 18
    static let radiusInner: CGFloat = 12
}

private extension Tok {
    /// Four variants each. Handling contrast in the token rather than the view is what stops the system setting from
    /// being a per-screen afterthought.
    static func adaptive(_ light: UInt32, _ dark: UInt32, _ lightContrast: UInt32, _ darkContrast: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            switch (traits.userInterfaceStyle == .dark, traits.accessibilityContrast == .high) {
            case (false, false): UIColor(hex: light)
            case (true, false): UIColor(hex: dark)
            case (false, true): UIColor(hex: lightContrast)
            case (true, true): UIColor(hex: darkContrast)
            }
        })
    }
}

extension Color {
    /// For colours that are content rather than chrome — a garment's own colour. These carry no meaning, so they need
    /// no increased-contrast variant; what sits on them does, and that is handled by the glyph colour.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Motion

/// Motion is orchestrated, not scattered: one rehearsed sequence when the day opens, then feedback only.
///
/// The focal moment is the day arc drawing itself to the current hour — the app explaining what it is showing. The
/// figure beside it counts up once, in step. The sections below arrive in a single staggered pass with the total
/// delay capped, so nothing is waiting to be read. Everything after that is feedback: a press, a tick, a sheet.
enum Motion {
    /// The hero sequence. Long enough to be watched, short enough not to be waited for.
    static let arc = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 1.05)
    /// Routine state change.
    static let state = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// A control acknowledging the finger.
    static let press = Animation.easeOut(duration: 0.14)
    /// Siblings arriving in order.
    static let stagger = 0.05
    /// Caps the total wait however long the list gets.
    static let staggerCap = 0.30
}

/// Tap feedback, in one place so no two controls feel different.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func kept() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Type

extension Font {
    /// The one large figure a screen is about. Tabular, so it does not jitter as it counts.
    static func hero(_ size: CGFloat = 46) -> Font { .system(size: size, weight: .semibold, design: .default) }
}

extension View {
    /// Numerals that read as measurements: aligned columns, no jitter.
    func figures(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> some View {
        font(.system(style, weight: weight)).monospacedDigit()
    }

    /// Assembles a screen in one staggered pass. Does nothing under Reduce Motion, which is the setting people turn
    /// on because movement makes them ill.
    func arrive(_ index: Int) -> some View { modifier(Arrive(index: index)) }
}

private struct Arrive: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .task {
                guard !reduceMotion else { shown = true; return }
                try? await Task.sleep(for: .seconds(min(Double(index) * Motion.stagger, Motion.staggerCap)))
                withAnimation(Motion.state) { shown = true }
            }
    }
}

// MARK: - Surfaces

/// The one panel. Warm multi-layer depth with a real offset, so it sits above the page instead of being drawn on it.
///
/// The content goes inside a `VStack` rather than being modified directly: a `@ViewBuilder` tuple is transparent, so
/// `.background` on it lands on every child separately and a section turns into a stack of loose boxes.
struct Panel<Content: View>: View {
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Tok.radius, style: .continuous)
                .fill(Tok.surface)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: Tok.radius, style: .continuous).fill(Tok.wash(tint))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Tok.radius, style: .continuous)
                .strokeBorder(tint?.opacity(0.28) ?? Tok.rule, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}

/// A section title. The heading carries its own weight — there is no label above it.
struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tok.ink)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).figures(.subheadline).foregroundStyle(Tok.faint)
            }
        }
    }
}

// MARK: - Controls

extension AgendaItem.Kind {
    /// The dot beside an agenda item. Focus is the colour you act in, a fixed commitment is neutral, and personal is
    /// the garden — so a glance down the day shows how much of it is yours.
    var color: Color {
        switch self {
        case .focus: Tok.accent
        case .fixed: Tok.faint
        case .personal: Tok.good
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

/// The one filled control. At most one per screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Tok.surface)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(colors: [Tok.accent, Tok.accent.opacity(0.86)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .shadow(color: Tok.accent.opacity(0.28), radius: 12, y: 5)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

/// The secondary action: recessed into the page rather than sitting on it, so it never competes with the one filled
/// control on the screen.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Tok.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Tok.raised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Tok.rule))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}
