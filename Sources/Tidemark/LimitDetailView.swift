import SwiftUI
import TidemarkCore

/// The pane beside the rows: the selected limit's window as a chart, three numbers, and its
/// recent days (or recent 5-hour windows).
struct LimitDetailView: View {
    let detail: LimitDetail
    let title: String
    let subtitle: String
    /// "As of 11:32 AM", on its own line, for an old reading (S3.10).
    var asOf: String? = nil
    /// The reading is old: its numbers go dim (never the whole view, which would fail contrast).
    var old = false
    let now: Date
    let formatting: Formatting
    let thresholds: Thresholds
    /// The "today" line under the chart's keys (week rows).
    var today: Copy.Today? = nil
    /// The panel's tabs already name the limit.
    var showsTitle = true
    @Environment(\.colorScheme) private var scheme
    private var p: TidePalette { .for(scheme) }

    var body: some View {
        let lead = UsageCopy.lead(detail)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if showsTitle { Text(title).font(Theme.font(16, .bold)).foregroundStyle(p.fg) }
                Text(subtitle).font(Theme.font(12)).foregroundStyle(p.dim)
                if let asOf { Text(asOf).font(Theme.font(12)).foregroundStyle(p.dim) }
            }
            Text(lead).font(Theme.font(13)).foregroundStyle(p.fg)
            DetailChart(detail: detail, now: now, formatting: formatting)
                .frame(height: 190)
                .accessibilityElement()
                .accessibilityLabel(lead)
            DetailLegend(detail: detail)
            if let today {
                let line = UsageCopy.todayLine(today)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.main).font(Theme.font(12)).foregroundStyle(p.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning = line.warning {
                        // Amber only means "runs out before it resets"; "would go unused" is words in a plain ink (D6).
                        Text(warning).font(Theme.font(12)).foregroundStyle(today.warningRunsOut ? Palette.amberInk : p.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(p.sel)
            }
            Rectangle().fill(p.line).frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                ForEach(UsageCopy.stats(detail, now: now, formatting: formatting, thresholds), id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.label).font(Theme.font(11)).fixedSize(horizontal: false, vertical: true).foregroundStyle(p.dim)
                        Text(stat.value).font(Theme.font(15, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(old ? p.dim : p.fg)
                        if let note = stat.note {
                            Text(note).font(Theme.font(11)).foregroundStyle(p.dim).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Rectangle().fill(p.line).frame(height: 1)
            let heading = UsageCopy.barsTitle(detail.id.kind)
            VStack(alignment: .leading, spacing: 2) {
                (Text(heading.title).fontWeight(.bold).foregroundColor(p.fg) + Text(" · \(heading.note)").foregroundColor(p.dim))
                    .font(Theme.font(12.5))
                if let caption = UsageCopy.barsCaption(detail) {
                    Text(caption).font(Theme.font(11.5)).foregroundStyle(p.dim)
                }
            }
            DetailBars(detail: detail, now: now, formatting: formatting).frame(height: 120)
                .accessibilityElement()
                .accessibilityLabel(UsageCopy.barsSummary(detail, now: now, formatting: formatting))
            BarsLegend(detail: detail)
            if let gap = UsageCopy.gapNote(detail, formatting: formatting) {
                Text(gap).font(Theme.font(11.5)).foregroundStyle(p.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The detail chart: used so far, use-it-all and your pace, run-out dot, locked hatching,
/// unused wedge, now line and reset bar.
private struct DetailChart: View {
    @Environment(\.colorScheme) private var scheme
    private var p: TidePalette { .for(scheme) }
    let detail: LimitDetail
    let now: Date
    let formatting: Formatting

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 32, y: 16, width: size.width - 36, height: size.height - 36)
            func pt(_ p: ChartPoint) -> CGPoint { CGPoint(x: plot.minX + p.x * plot.width, y: plot.maxY - p.y * plot.height) }
            func path(_ points: [ChartPoint]) -> Path {
                var path = Path()
                guard let first = points.first else { return path }
                path.move(to: pt(first))
                points.dropFirst().forEach { path.addLine(to: pt($0)) }
                return path
            }
            func vertical(_ x: Double, from top: CGFloat? = nil) -> Path {
                Path { p in
                    p.move(to: CGPoint(x: plot.minX + x * plot.width, y: top ?? plot.minY))
                    p.addLine(to: CGPoint(x: plot.minX + x * plot.width, y: plot.maxY))
                }
            }

            for (value, dashed) in [(0.0, false), (0.5, false), (1.0, true)] {
                ctx.stroke(path([ChartPoint(x: 0, y: value), ChartPoint(x: 1, y: value)]),
                           with: .color(p.line), style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 3] : []))
                ctx.draw(Text("\(Int(value * 100))%").font(Theme.font(10)).foregroundColor(p.dim),
                         at: CGPoint(x: plot.minX - 5, y: plot.maxY - value * plot.height), anchor: .trailing)
            }

            if let from = detail.lockedFromX {
                let rect = CGRect(x: plot.minX + from * plot.width, y: plot.minY, width: (1 - from) * plot.width, height: plot.height)
                ctx.fill(Path(rect), with: .color(p.redMark.opacity(0.14)))
                var stripes = ctx
                stripes.clip(to: Path(rect))
                var x = rect.minX - rect.height
                while x < rect.maxX {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: rect.maxY))
                    line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    stripes.stroke(line, with: .color(p.redMark), lineWidth: 2)
                    x += 6
                }
            }

            var area = path(detail.usedLine)
            area.addLine(to: pt(ChartPoint(x: detail.nowX, y: 0)))
            area.addLine(to: pt(ChartPoint(x: 0, y: 0)))
            area.closeSubpath()
            ctx.fill(area, with: .color(p.line.opacity(0.5)))

            if detail.unused.count >= 3 {
                var wedge = path(detail.unused)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(p.dim.opacity(0.28)))
            }
            ctx.stroke(path(detail.useItAll), with: .color(p.dim), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            ctx.stroke(path(detail.yourPace), with: .color(p.fg.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1.5, 3]))
            ctx.stroke(path(detail.usedLine), with: .color(p.fg), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            ctx.stroke(vertical(detail.nowX), with: .color(p.dim), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            let dot = pt(ChartPoint(x: detail.nowX, y: detail.used / 100))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 3.5, y: dot.y - 3.5, width: 7, height: 7)), with: .color(p.fg))
            // "Now" sits to the left of its line, so the line and the curves never run through it (S3.9).
            ctx.draw(Text("Now").font(Theme.font(10)).foregroundColor(p.dim),
                     at: CGPoint(x: dot.x - 6, y: detail.used < 50 ? dot.y - 11 : min(dot.y + 13, plot.maxY - 6)), anchor: .trailing)

            if let out = detail.runsOut, let outAt = detail.runsOutAt {
                let spot = pt(out)
                ctx.fill(Path(ellipseIn: CGRect(x: spot.x - 5, y: spot.y - 5, width: 10, height: 10)), with: .color(p.redMark))
                ctx.draw(Text(detail.used >= 100 ? "Out" : formatting.dayTime(outAt, now: now))
                            .font(Theme.font(10.5, .bold)).foregroundColor(p.fg),
                         at: CGPoint(x: min(max(spot.x, plot.minX + 24), plot.maxX - 24), y: plot.minY - 9))
            }
            ctx.stroke(vertical(1, from: plot.minY - 2), with: .color(p.fg), lineWidth: 2)

            for tick in detail.ticks {
                ctx.draw(Text(UsageCopy.tickLabel(tick, kind: detail.id.kind, formatting: formatting))
                            .font(Theme.font(10)).foregroundColor(p.dim),
                         at: CGPoint(x: plot.minX + tick.x * plot.width, y: size.height - 8))
            }
        }
    }
}

/// The chart's keys, only for what the chart shows.
private struct DetailLegend: View {
    @Environment(\.colorScheme) private var scheme
    private var p: TidePalette { .for(scheme) }
    let detail: LimitDetail

    var body: some View {
        WrapLayout(spacing: 12) {
            key("Used") { Rectangle().fill(p.fg).frame(width: 14, height: 2) }
            if !detail.useItAll.isEmpty {
                key("Use-it-all") { Line().stroke(p.dim, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])).frame(width: 14, height: 2) }
            }
            if !detail.yourPace.isEmpty {
                key("Your pace") { Line().stroke(p.fg.opacity(0.8), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1.5, 3])).frame(width: 14, height: 2) }
            }
            if detail.runsOut != nil { key("Runs out") { Circle().fill(p.redMark).frame(width: 8, height: 8) } }
            if detail.lockedFromX != nil { key("Locked") { RoundedRectangle(cornerRadius: 2).fill(p.redMark).frame(width: 10, height: 10) } }
            if !detail.unused.isEmpty { key("Would go unused") { RoundedRectangle(cornerRadius: 2).fill(p.dim.opacity(0.28)).frame(width: 10, height: 10) } }
        }
        .font(Theme.font(11))
        .foregroundStyle(p.dim)
    }

    private func key<S: View>(_ text: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 4) { swatch(); Text(text).fixedSize() }
    }
}

/// Seven days of use against the use-it-all pace a day, or recent 5-hour windows' peaks. A day
/// before the first reading has no bar, only a faint label (S3.1).
private struct DetailBars: View {
    @Environment(\.colorScheme) private var scheme
    private var p: TidePalette { .for(scheme) }
    let detail: LimitDetail
    let now: Date
    let formatting: Formatting

    var body: some View {
        Canvas { ctx, size in
            let bars = detail.bars
            guard !bars.isEmpty else { return }
            let base = size.height - 18
            let top: CGFloat = 16
            let maxValue = max(bars.compactMap(\.value).max() ?? 0, detail.perDayLine ?? 0, 1)
            let k = (base - top) / maxValue
            let slot = size.width / CGFloat(bars.count)
            let width = min(slot * 0.56, 30)
            if let line = detail.perDayLine {
                let y = base - CGFloat(line) * k
                ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(p.dim), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
            let lineY = detail.perDayLine.map { base - CGFloat($0) * k }
            for (i, bar) in bars.enumerated() {
                let x = slot * (CGFloat(i) + 0.5) - width / 2
                let label = UsageCopy.barLabel(bar, kind: detail.id.kind, now: now, formatting: formatting)
                let current = bar.tone == .today || bar.tone == .openWindow
                ctx.draw(Text(label).font(Theme.font(10.5, current ? .bold : .regular))
                            .foregroundColor(current ? p.fg : bar.value == nil ? p.faint : p.dim),
                         at: CGPoint(x: x + width / 2, y: size.height - 6))
                guard let value = bar.value else { continue }
                let h = CGFloat(value) * k
                BarMark.draw(ctx, CGRect(x: x, y: base - h, width: width, height: max(h, 1)), tone: bar.tone, p)
                // What's still to come in a day or window that hasn't ended, dashed.
                if bar.tone == .today, let line = detail.perDayLine, line > value {
                    let rest = CGRect(x: x, y: base - CGFloat(line) * k, width: width, height: CGFloat(line - value) * k)
                    ctx.stroke(Path(roundedRect: rest, cornerRadius: 3), with: .color(p.dim), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else if bar.tone == .openWindow, h < base - top {
                    let rest = CGRect(x: x, y: top, width: width, height: base - top - h)
                    ctx.stroke(Path(roundedRect: rest, cornerRadius: 3), with: .color(p.dim), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                // The value sits on top of what's filled; off the dashed line if it would sit on it.
                var valueY = base - h - 7
                if let lineY, abs(valueY - lineY) < 7 { valueY = lineY - 8 }
                ctx.draw(Text("\(Int(value.rounded()))").font(Theme.font(10.5)).foregroundColor(p.fg),
                         at: CGPoint(x: x + width / 2, y: valueY))
            }
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: base)); p.addLine(to: CGPoint(x: size.width, y: base)) },
                       with: .color(p.line), lineWidth: 1)
        }
    }
}

/// The bar chart's keys, from `UsageCopy.barKeys`.
private struct BarsLegend: View {
    @Environment(\.colorScheme) private var scheme
    private var p: TidePalette { .for(scheme) }
    let detail: LimitDetail

    var body: some View {
        WrapLayout(spacing: 12) {
            ForEach(UsageCopy.barKeys(detail), id: \.self) { name in
                HStack(spacing: 4) {
                    swatch(name)
                    Text(name).fixedSize()
                }
            }
        }
        .font(Theme.font(11))
        .foregroundStyle(p.dim)
    }

    @ViewBuilder private func swatch(_ name: String) -> some View {
        if name == "Use-it-all/day" {
            Line().stroke(p.dim, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).frame(width: 14, height: 2)
        } else {
            Canvas { ctx, size in BarMark.draw(ctx, CGRect(origin: .zero, size: size), tone: Self.tone(name), p) }
                .frame(width: 14, height: 10)
        }
    }

    /// The bar tone a key stands for.
    private static func tone(_ name: String) -> DetailBar.Tone {
        switch name {
        case "Under": .under
        case "Over": .over
        case "Reached 100%": .hitLimit
        case "Today so far", "Open window": .today
        default: .plain
        }
    }
}

/// A bar's mark by tone. Every tone has its own shape or pattern, so none rests on colour alone (D12):
/// a solid bar is on pace, plain or within the limit; an outline is under the use-it-all pace; stripes over
/// it are over it (grey) or at 100% (red). Amber is never used: it only means "runs out before it resets".
enum BarMark {
    static func draw(_ ctx: GraphicsContext, _ rect: CGRect, tone: DetailBar.Tone, _ p: TidePalette) {
        let shape = Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2))
        switch tone {
        case .under:
            ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: min(3, rect.width / 2)),
                       with: .color(p.dim), lineWidth: 1.5)
        case .over, .hitLimit:
            ctx.fill(shape, with: .color(tone == .hitLimit ? p.redMark : p.dim))
            var stripes = ctx
            stripes.clip(to: shape)
            var x = rect.minX - rect.height
            while x < rect.maxX {
                var line = Path()
                line.move(to: CGPoint(x: x, y: rect.maxY))
                line.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                stripes.stroke(line, with: .color(p.sky2), lineWidth: 1.5)
                x += 4.5
            }
        case .today, .openWindow:
            ctx.fill(shape, with: .color(p.fg))
        case .onPace, .plain, .withinLimit, .noData:
            ctx.fill(shape, with: .color(p.dim))
        }
    }
}

/// Lays its children left to right and starts a new line when one doesn't fit.
struct WrapLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return (origins, CGSize(width: maxX, height: y + lineHeight))
    }
}

/// A horizontal line through the middle of its frame (the legend keys).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}
