import SwiftUI

/// The hero: the day drawn as an arc from waking to now, the way the sun actually crosses it.
///
/// This is the one authored moment in the app, and it is doing work — it answers "where am I in this day" at a glance,
/// which is the question the Today board exists for. It draws once when the screen opens and then stays still, because
/// a working screen that keeps moving is a working screen you cannot read. Under Reduce Motion it arrives already drawn.
struct DayArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 at waking, 1 at the end of the waking day.
    let progress: Double
    let nowLabel: String
    let startLabel: String
    let endLabel: String

    @State private var drawn: Double = 0

    private let lineWidth: CGFloat = 10
    private var target: Double { max(0, min(1, progress)) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Canvas { context, size in
                    let radius = min(size.width, size.height * 2) / 2 - lineWidth - 10
                    let centre = CGPoint(x: size.width / 2, y: size.height)
                    let start = Angle.degrees(180)
                    let sweep = Angle.degrees(180)

                    // The whole day, recessed.
                    var track = Path()
                    track.addArc(center: centre, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: false)
                    context.stroke(
                        track,
                        with: .color(Tok.raised),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                    // Hour ticks, every sixth taller, so the arc reads as a day and not a progress bar.
                    for hour in 0...24 {
                        let fraction = Double(hour) / 24
                        let angle = Double.pi * (1 + fraction)
                        let outer = radius + lineWidth / 2 + 4
                        let inner = outer + (hour % 6 == 0 ? 6 : 3)
                        var tick = Path()
                        tick.move(to: CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer))
                        tick.addLine(to: CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
                        context.stroke(tick, with: .color(Tok.rule), lineWidth: 1)
                    }

                    // Elapsed, in the colour of the thing you acted on.
                    guard drawn > 0 else { return }
                    var elapsed = Path()
                    elapsed.addArc(
                        center: centre,
                        radius: radius,
                        startAngle: start,
                        endAngle: start + Angle.degrees(180 * drawn),
                        clockwise: false
                    )
                    context.stroke(
                        elapsed,
                        with: .linearGradient(
                            Gradient(colors: [Tok.accent.opacity(0.72), Tok.accent]),
                            startPoint: CGPoint(x: 0, y: size.height),
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                    // Now: a dot on the arc with a soft halo, so it reads as a position rather than an end cap.
                    let angle = Double.pi * (1 + drawn)
                    let point = CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)),
                        with: .color(Tok.accent.opacity(0.16))
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 7.5, y: point.y - 7.5, width: 15, height: 15)),
                        with: .color(Tok.accent)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                        with: .color(Tok.surface)
                    )
                }
                .frame(height: 150)

                VStack(spacing: 1) {
                    Text(nowLabel).figures(.title3, weight: .semibold).foregroundStyle(Tok.ink)
                    Text("now").font(.caption2).foregroundStyle(Tok.faint)
                }
                .padding(.top, 30)
            }
            .frame(height: 150)

            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Tok.faint)
        }
        .task {
            drawn = 0
            guard !reduceMotion else { drawn = target; return }
            // A task rather than onAppear: inside a List the view can be built before it is in the hierarchy, and an
            // animation started there is dropped, leaving the arc stranded at zero for the screen's whole life.
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(Motion.arc) { drawn = target }
        }
        .accessibilityElement()
        .accessibilityLabel("Day elapsed")
        .accessibilityValue("\(Int(target * 100)) percent, \(nowLabel)")
    }
}

#Preview {
    VStack(spacing: 30) {
        DayArc(progress: 0.53, nowLabel: "15:00", startLabel: "06:00", endLabel: "23:00")
        DayArc(progress: 0.9, nowLabel: "21:18", startLabel: "06:00", endLabel: "23:00")
    }
    .padding(24)
    .background(Tok.bg)
}
