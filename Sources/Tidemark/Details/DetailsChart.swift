import SwiftUI
import TidemarkCore

/// The details card's week chart (the mockup's `pchart`), drawn from a `LeftChart`: what's used rising
/// as a line over a soft fill, the dashed forecast to where it runs out or the reset, the hatched time
/// locked, a dotted even pace, the reset line at the right and a day label under each day.
struct DetailsChart: View {
    let chart: LeftChart
    let formatting: Formatting
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 92

    var body: some View {
        let p = TidePalette.for(scheme)
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func x(_ share: Double) -> CGFloat { 6 + CGFloat(share) * (w - 12) }
            // `used` is 0...1.
            func y(_ used: Double) -> CGFloat { 8 + CGFloat(1 - used) * (h - 26) }
            let ink = p.fg

            if let from = chart.lockedFrom {
                let region = Path(CGRect(x: x(from), y: y(1), width: x(1) - x(from), height: y(0) - y(1)))
                TideHatch.fill(&ctx, region: region, spacing: 4, stripe: 1.4, stripeColor: p.redMark, base: p.redMark.opacity(0.18))
            }
            var top = Path(); top.move(to: CGPoint(x: x(0), y: y(1))); top.addLine(to: CGPoint(x: x(1), y: y(1)))
            ctx.stroke(top, with: .color(p.faint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            var base = Path(); base.move(to: CGPoint(x: x(0), y: y(0))); base.addLine(to: CGPoint(x: x(1), y: y(0)))
            ctx.stroke(base, with: .color(p.line), lineWidth: 1)
            var even = Path(); even.move(to: CGPoint(x: x(0), y: y(0))); even.addLine(to: CGPoint(x: x(1), y: y(1)))
            ctx.stroke(even, with: .color(p.faint), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))

            let used = chart.left.map { CGPoint(x: x($0.x), y: y(1 - $0.y)) }
            if let first = used.first, let last = used.last {
                var area = Path(); area.move(to: CGPoint(x: first.x, y: y(0)))
                for point in used { area.addLine(to: point) }
                area.addLine(to: CGPoint(x: last.x, y: y(0))); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [ink.opacity(0.28), ink.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: y(1)), endPoint: CGPoint(x: 0, y: y(0))))
                var line = Path(); line.move(to: first)
                for point in used.dropFirst() { line.addLine(to: point) }
                ctx.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }

            func dot(_ at: CGPoint, _ color: Color) {
                let rect = CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(p.sky2), lineWidth: 1.5)
            }
            if let now = chart.now {
                let from = CGPoint(x: x(now.x), y: y(1 - now.y))
                if let end = chart.forecastEnd {
                    let to = CGPoint(x: x(end.x), y: y(1 - end.y))
                    var dash = Path(); dash.move(to: from); dash.addLine(to: to)
                    ctx.stroke(dash, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    if chart.lockedFrom != nil { dot(to, p.redMark) }
                }
                dot(from, ink)
            }
            // Out already (or last week's run-out): the red dot sits at the top where it filled.
            if chart.forecastEnd == nil, let out = chart.lockedFrom { dot(CGPoint(x: x(out), y: y(1)), p.redMark) }

            var reset = Path(); reset.move(to: CGPoint(x: x(1), y: y(1) - 4)); reset.addLine(to: CGPoint(x: x(1), y: y(0)))
            ctx.stroke(reset, with: .color(ink), lineWidth: 1.6)

            for (i, tick) in chart.days.dropLast().enumerated() {
                let label = Text(formatting.weekday(tick.date)).font(.system(size: 9)).foregroundColor(p.faint)
                ctx.draw(label, at: CGPoint(x: x((Double(i) + 0.5) / 7), y: h - 6), anchor: .center)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}
