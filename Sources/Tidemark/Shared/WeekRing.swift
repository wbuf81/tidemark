import SwiftUI
import TidemarkCore

/// The week as a ring of seven day segments, filled to `used` percent, with a tick at how much of
/// the week has `elapsed`. Geometry is the mockups' `ring()`. `used` nil (couldn't read) draws only
/// the track. Segments before `firstReadDay` (0 = first day) draw as track: the days before the
/// first reading are unknown.
struct WeekRing: View {
    let used: Double?
    let elapsed: Double
    let state: PlanState?
    let size: CGFloat
    let showsNumber: Bool
    let dimmed: Bool
    let firstReadDay: Int?

    init(used: Double?, elapsed: Double, state: PlanState?, size: CGFloat, showsNumber: Bool = true,
         dimmed: Bool = false, firstReadDay: Int? = nil) {
        self.used = used
        self.elapsed = elapsed
        self.state = state
        self.size = size
        self.showsNumber = showsNumber
        self.dimmed = dimmed
        self.firstReadDay = firstReadDay
    }

    private var width: CGFloat { max(3, size * 0.13) }
    private var radius: CGFloat { size / 2 - width / 2 - 1 }
    private var gap: Double { size >= 30 ? 5 : 7 }

    var body: some View {
        let c = size / 2
        let tone = used == nil ? Palette.faint : Palette.color(for: state)
        let filled = (used ?? 0) / 100 * 360
        let seg = 360.0 / 7
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let a0 = Double(i) * seg + gap / 2, a1 = Double(i + 1) * seg - gap / 2
                Self.arc(c: c, r: radius, from: a0, to: a1).stroke(Palette.track, style: StrokeStyle(lineWidth: width))
                let f1 = min(a1, filled)
                if f1 > a0, i >= (firstReadDay ?? 0) {
                    Self.arc(c: c, r: radius, from: a0, to: f1).stroke(tone, style: StrokeStyle(lineWidth: width))
                }
            }
            tick(c: c)
            if showsNumber, size >= 24, let used {
                Text("\(Int(used.rounded()))")
                    .font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(Palette.bright)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityHidden(true)
    }

    private func tick(c: CGFloat) -> some View {
        let e = elapsed / 100 * 360
        let from = Self.point(c: c, r: radius - width / 2 - 1.5, deg: e), to = Self.point(c: c, r: radius + width / 2 + 1.5, deg: e)
        return Path { $0.move(to: from); $0.addLine(to: to) }
            .stroke(Palette.bright.opacity(0.75), style: StrokeStyle(lineWidth: max(1.2, size / 30), lineCap: .round))
    }

    /// Degrees clockwise from twelve o'clock.
    static func point(c: CGFloat, r: CGFloat, deg: Double) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: c + r * CGFloat(cos(a)), y: c + r * CGFloat(sin(a)))
    }

    static func arc(c: CGFloat, r: CGFloat, from a0: Double, to a1: Double) -> Path {
        Path { $0.addRelativeArc(center: CGPoint(x: c, y: c), radius: r, startAngle: .degrees(a0 - 90), delta: .degrees(a1 - a0)) }
    }
}
