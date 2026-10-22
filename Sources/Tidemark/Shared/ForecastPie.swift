import SwiftUI
import TidemarkCore

/// The week as seven day segments, clockwise from the reset at the top (the mockups' `fpie`). A day
/// that's over is as bold as it was heavy (opacity .22 to 1), today is bold up to now and track after,
/// days ahead are track, and time locked out is hatched red. A tick marks the reset, a red dot the
/// run-out, a dot now. The centre number is light with a small `%`; it shows from 24 pt up.
/// Colours come from `TidePalette`, so it reads on the sky (and on the notch's black in a dark scheme).
struct ForecastPie: View {
    let pie: WeekPie
    let size: CGFloat
    let isOld: Bool

    @Environment(\.colorScheme) private var scheme

    init(pie: WeekPie, size: CGFloat, isOld: Bool = false) {
        self.pie = pie
        self.size = size
        self.isOld = isOld
    }

    var body: some View {
        let p = TidePalette.for(scheme)
        let c = size / 2, w = max(3.5, size * 0.12), r = c - w / 2 - 2
        let seg = 360.0 / 7, gap = 5.0
        ZStack {
            Canvas { ctx, _ in
                func arc(_ a0: Double, _ a1: Double) -> Path { WeekRing.arc(c: c, r: r, from: a0, to: a1) }
                func solid(_ a0: Double, _ a1: Double, _ color: Color) {
                    ctx.stroke(arc(a0, a1), with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .butt))
                }
                func hatched(_ a0: Double, _ a1: Double) {
                    let band = arc(a0, a1).strokedPath(StrokeStyle(lineWidth: w, lineCap: .butt))
                    TideHatch.fill(&ctx, region: band, spacing: 3.4, stripe: 1.4, stripeColor: p.redMark, base: p.redMark.opacity(0.25))
                }
                for (i, segment) in pie.segments.enumerated() {
                    let a0 = Double(i) * seg + gap / 2, a1 = Double(i + 1) * seg - gap / 2
                    func at(_ f: Double) -> Double { a0 + (a1 - a0) * min(max(f, 0), 1) }
                    switch segment {
                    case .used(let heaviness):
                        solid(a0, a1, p.fg.opacity(0.22 + 0.78 * heaviness))
                    case .unseen:
                        solid(a0, a1, p.track)
                    case .today(let elapsed, _):
                        solid(a0, at(elapsed), p.fg); solid(at(elapsed), a1, p.track)
                    case .ahead:
                        solid(a0, a1, p.track)
                    case .runsOut(let when):
                        solid(a0, at(when), p.track); hatched(at(when), a1)
                    case .todayRunsOut(let elapsed, let when, _):
                        solid(a0, at(elapsed), p.fg); solid(at(elapsed), at(when), p.track); hatched(at(when), a1)
                    case .locked:
                        hatched(a0, a1)
                    case .ranOut(let when, _):
                        solid(a0, at(when), p.fg.opacity(0.85)); hatched(at(when), a1)
                    }
                }
                // The reset, at the top.
                var tick = Path()
                tick.move(to: CGPoint(x: c, y: c - r - w / 2 - 2.5)); tick.addLine(to: CGPoint(x: c, y: c - r + w / 2 + 1.5))
                ctx.stroke(tick, with: .color(p.fg), lineWidth: 1.6)
                func dot(_ point: WeekPie.Point, _ color: Color) {
                    let a = Double(point.day) * seg + gap / 2 + (seg - gap) * min(max(point.fraction, 0), 1)
                    let at = WeekRing.point(c: c, r: r, deg: a), d = w * 0.62
                    let rect = CGRect(x: at.x - d, y: at.y - d, width: d * 2, height: d * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(p.sky2), lineWidth: 1.5)
                }
                if let out = pie.runsOut { dot(out, p.redMark) }
                dot(pie.now, p.fg)
            }
            if size >= 24 {
                let fs = size * 0.3
                (Text("\(pie.used)").font(.system(size: fs, weight: .light)).foregroundColor(p.fg)
                    + Text("%").font(.system(size: fs * 0.45, weight: .regular)).foregroundColor(p.dim))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .opacity(isOld ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}
