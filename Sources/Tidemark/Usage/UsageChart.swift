import SwiftUI
import TidemarkCore

/// What's left through the week, drawn as the mockups' `tide_chart`: the level falls from 100% at the reset,
/// dashed on to empty if the pace holds, hatched red while locked, the hours used under it, the reset
/// as a line and the plan's own days along the foot. Last week is the same without now or a forecast.
struct TideChart: View {
    let chart: LeftChart
    let name: String
    let now: Date
    let formatting: Formatting
    var last = false
    var isOld = false
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 212

    var body: some View {
        let p = TidePalette.for(scheme)
        let tip = UsageCopy.chartTip(chart, now: now, formatting: formatting)
        Canvas { ctx, size in Self.draw(&ctx, size, p, chart: chart, tip: tip, now: now, formatting: formatting, last: last, isOld: isOld) }
            .frame(height: Self.height)
            .accessibilityElement()
            .accessibilityLabel(label(tip))
    }

    private func label(_ tip: UsageCopy.ChartTip?) -> String {
        var text = "\(name) \(last ? "last week" : "this week")"
        if let at = chart.now { text += ": \(Int((at.y * 100).rounded()))% left now" }
        if let tip { text += ". \(tip.title). \(tip.detail)." }
        return text
    }

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: TidePalette, chart: LeftChart,
                             tip: UsageCopy.ChartTip?, now: Date, formatting f: Formatting, last: Bool, isOld: Bool) {
        let L: CGFloat = 8, R: CGFloat = 52, T: CGFloat = 26, base: CGFloat = 150, bars0: CGFloat = 196
        let plot = size.width - L - R
        func x(_ share: Double) -> CGFloat { L + CGFloat(share) * plot }
        func y(_ left: Double) -> CGFloat { T + CGFloat(1 - left) * (base - T) }
        func text(_ s: String, _ at: CGPoint, size fs: CGFloat, color: Color, weight: Font.Weight = .regular, anchor: UnitPoint = .center) {
            ctx.draw(Text(s).font(.system(size: fs, weight: weight)).foregroundColor(color), at: at, anchor: anchor)
        }
        let fade = isOld ? 0.6 : 1.0
        let fg = p.fg.opacity(fade)

        // Header: what it is, now, the reset.
        text("Left \(last ? "that" : "this") week", CGPoint(x: L, y: 12), size: 11, color: p.dim, anchor: .leading)
        let resetText = "Reset \(f.dayTime(chart.reset, now: now))"
        text(resetText, CGPoint(x: x(1), y: 12), size: 11, color: p.fg, weight: .semibold, anchor: .trailing)
        if let at = chart.now, x(at.x) < x(1) - 120 {
            text("Now", CGPoint(x: x(at.x), y: 12), size: 11, color: p.fg, weight: .semibold)
        }

        // Grid and its percentages.
        for v in [1.0, 0.5, 0.0] {
            var line = Path(); line.move(to: CGPoint(x: x(0), y: y(v))); line.addLine(to: CGPoint(x: x(1), y: y(v)))
            ctx.stroke(line, with: .color(p.line), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 4]))
            text("\(Int(v * 100))%", CGPoint(x: size.width - R + 10, y: y(v)), size: 10.5, color: p.faint, anchor: .leading)
        }

        // Locked: hatched from the run-out to the reset.
        if let from = chart.lockedFrom {
            let rect = Path(CGRect(x: x(from), y: T, width: x(1) - x(from), height: bars0 - T))
            TideHatch.fill(&ctx, region: rect, spacing: 6, stripe: 1.4, stripeColor: p.redMark.opacity(0.8), base: p.redMark.opacity(0.14))
        }
        if let at = chart.now {
            var line = Path(); line.move(to: CGPoint(x: x(at.x), y: T - 6)); line.addLine(to: CGPoint(x: x(at.x), y: bars0))
            ctx.stroke(line, with: .color(p.line), lineWidth: 1)
        }

        // What's left: the area under it and the line.
        let points = chart.left.map { CGPoint(x: x($0.x), y: y($0.y)) }
        if let first = points.first, let end = points.last {
            var area = Path(); area.move(to: CGPoint(x: first.x, y: base))
            points.forEach { area.addLine(to: $0) }
            area.addLine(to: CGPoint(x: end.x, y: base)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [p.fg.opacity(0.55 * fade), p.fg.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: T), endPoint: CGPoint(x: 0, y: base)))
            var line = Path(); line.move(to: first)
            points.dropFirst().forEach { line.addLine(to: $0) }
            ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        // The forecast, dashed, and the empty line after it.
        if let at = chart.now, let end = chart.forecastEnd {
            var dash = Path(); dash.move(to: CGPoint(x: x(at.x), y: y(at.y))); dash.addLine(to: CGPoint(x: x(end.x), y: y(end.y)))
            ctx.stroke(dash, with: .color(fg), style: StrokeStyle(lineWidth: 1.8, dash: [5, 4]))
        }
        if let from = chart.lockedFrom {
            var empty = Path(); empty.move(to: CGPoint(x: x(from), y: y(0))); empty.addLine(to: CGPoint(x: x(1), y: y(0)))
            ctx.stroke(empty, with: .color(p.redMark), lineWidth: 2)
        }
        func dot(_ at: CGPoint, fill: Color, edge: Color) {
            let rect = CGRect(x: at.x - 4.5, y: at.y - 4.5, width: 9, height: 9)
            ctx.fill(Path(ellipseIn: rect), with: .color(fill)); ctx.stroke(Path(ellipseIn: rect), with: .color(edge), lineWidth: 2)
        }
        if let at = chart.now { dot(CGPoint(x: x(at.x), y: y(at.y)), fill: fg, edge: p.sky2) }
        if let from = chart.lockedFrom { dot(CGPoint(x: x(from), y: y(0)), fill: p.sky2, edge: p.redMark) }

        // The reset.
        var reset = Path(); reset.move(to: CGPoint(x: x(1), y: T - 4)); reset.addLine(to: CGPoint(x: x(1), y: bars0))
        ctx.stroke(reset, with: .color(p.fg), lineWidth: 2)

        // The tip beside the locked stretch.
        if let tip, let from = chart.lockedFrom {
            let box = CGRect(x: min(x(from) + 10, x(1) - 178), y: T + 6, width: 168, height: 40)
            ctx.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(p.sky2.opacity(0.95)))
            ctx.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color(p.line), lineWidth: 1)
            text(tip.title, CGPoint(x: box.minX + 10, y: box.minY + 13), size: 11.5, color: p.fg, anchor: .leading)
            text(tip.detail, CGPoint(x: box.minX + 10, y: box.minY + 28), size: 11, color: p.red, anchor: .leading)
        }

        // "Not known yet": the hours still to come.
        if let at = chart.now {
            let to = chart.lockedFrom ?? 1
            if (x(to) - x(at.x)) > 100 {
                text("Not known yet", CGPoint(x: (x(at.x) + x(to)) / 2, y: bars0 - 8), size: 11, color: p.faint)
            }
        }

        // Hours used.
        for hour in chart.hours {
            let h = min(CGFloat(hour.used) * 2.2, 44)
            ctx.fill(Path(roundedRect: CGRect(x: x(hour.x), y: bars0 - max(h, 1), width: max(CGFloat(hour.width) * plot - 0.8, 1), height: max(h, 1)), cornerRadius: 0.6),
                     with: .color(p.fg.opacity(0.62 * fade)))
        }

        // Days along the foot, today in bold.
        let today = chart.now.map { min(Int($0.x * 7), 6) }
        for (i, tick) in chart.days.enumerated() {
            let isToday = i == today
            text(f.weekday(tick.date), CGPoint(x: x(tick.x), y: size.height - 8), size: 11, color: isToday ? p.fg : p.faint,
                 weight: isToday ? .semibold : .regular)
        }
    }
}
