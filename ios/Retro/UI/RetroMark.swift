import SwiftUI

/// The app's mark: a rewind glyph, which is the one gesture everyone already reads as "go back over it". Drawn rather
/// than shipped as an image, so it takes the ink and accent colours and scales cleanly at any size.
struct RetroMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var size: CGFloat = 64

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Chevron()
                    .stroke(
                        index == 1 ? Tok.accent : Tok.ink.opacity(0.3),
                        style: StrokeStyle(lineWidth: size * 0.115, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: size * 0.4, height: size * 0.5)
                    .offset(x: (index == 1 ? 1 : -1) * size * 0.19)
                    .opacity(settled ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { settled = true; return }
            withAnimation(Motion.arc) { settled = true }
        }
        .accessibilityHidden(true)
    }
}

/// A left-pointing chevron, sized to its frame.
private struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

#Preview {
    RetroMark(size: 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tok.bg)
}
