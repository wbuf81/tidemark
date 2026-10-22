import SwiftUI
import TidemarkCore

/// The details card (the mockups' `fx_panel`) on the card sky: header, what's left with the forecast
/// pie, the locked line, pace, the week, the 5 hours, the busiest hours and "Open Usage…".
/// 300 pt wide; as tall as its contents.
struct PlanDetailsView: View {
    let name: String
    let details: PlanDetails
    let formatting: Formatting
    var isOld = false
    var openUsage: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        VStack(alignment: .leading, spacing: 10) {
            header(p)
            if let asOf = details.asOf {
                Text(asOf).font(.system(size: 11)).foregroundColor(p.dim).accessibilityLabel(asOf)
            }
            big(p)
            if let locked = details.locked { lockedLine(locked, p) }
            if let pace = details.pace { divider(p); paceBlock(pace, p) }
            divider(p)
            if details.hasHistory, let chart = details.chart {
                caption("This week", Self.legend(chart), p)
                DetailsChart(chart: chart, formatting: formatting)
                divider(p)
            }
            fiveHour(p)
            divider(p)
            if details.hasHistory {
                if details.busiest.isEmpty {
                    Text("No busy hours yet this week.").font(.system(size: 12)).foregroundColor(p.dim)
                    divider(p)
                } else {
                    caption("Busiest hours", "used that hour", p)
                    ForEach(Array(details.busiest.enumerated()), id: \.offset) { _, hour in
                        HStack {
                            Text(hour.range).foregroundColor(p.fg)
                            Spacer(minLength: 8)
                            Text(hour.used).fontWeight(.medium).foregroundColor(p.fg)
                        }
                        .font(.system(size: 12)).monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(hour.range), \(hour.used) used")
                    }
                    divider(p)
                }
            } else {
                Text("Not enough readings yet").font(.system(size: 12)).foregroundColor(p.dim)
                divider(p)
            }
            // A real button, so the keyboard and VoiceOver reach it.
            Button(action: openUsage) {
                Text("Open Usage…").font(.system(size: 12, weight: .semibold)).foregroundColor(p.fg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Usage for \(name)")
        }
        .padding(.init(top: 14, leading: 16, bottom: 12, trailing: 16))
        .frame(width: DetailsPlacement.width, alignment: .leading)
        .background(TideSky(.card))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.line, lineWidth: 1))
        .environment(\.layoutDirection, .leftToRight)
    }

    /// What the chart's legend names: only what is drawn (locked only when something is locked).
    static func legend(_ chart: LeftChart) -> String {
        var parts = ["used"]
        if chart.forecastEnd != nil { parts.append("if the pace holds") }
        if chart.lockedFrom != nil { parts.append("locked") }
        return parts.joined(separator: " · ")
    }

    private func header(_ p: TidePalette) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                StateShape(details.state, hollow: isOld, size: 9)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(p.fg)
            }
            Spacer(minLength: 8)
            Text("weekly limit").font(.system(size: 11)).foregroundColor(p.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(name) details, weekly limit")
    }

    private func big(_ p: TidePalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                (Text("\(details.left)").font(.system(size: 40, weight: .light))
                    + Text("% left").font(.system(size: 16, weight: .light)).foregroundColor(p.dim))
                    .foregroundColor(p.fg).tracking(-0.8).monospacedDigit().lineLimit(1)
                Text(details.sentence).font(.system(size: 12.5)).foregroundColor(p.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(details.left)% left. \(details.sentence)")
            Spacer(minLength: 0)
            if let pie = details.pie {
                ForecastPie(pie: pie, size: 64, isOld: isOld)
                    .accessibilityHidden(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week forecast, \(pie.used)% used")
            }
        }
    }

    private func lockedLine(_ text: String, _ p: TidePalette) -> some View {
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let box = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
                TideHatch.fill(&ctx, region: box, spacing: 4, stripe: 1.4, stripeColor: p.redMark, base: p.redMark.opacity(0.18))
            }
            .frame(width: 12, height: 12).accessibilityHidden(true)
            Text(text).font(.system(size: 11.5)).foregroundColor(p.red)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func paceBlock(_ pace: PaceReading, _ p: TidePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("Pace", pace.text, p)
            HStack(spacing: 4) {
                ForEach([PaceLevel.light, .even, .fast], id: \.self) { level in
                    let on = level == pace.level
                    VStack(spacing: 4) {
                        Capsule().fill(on ? p.fg : p.track).frame(height: 5)
                        Text(level.label).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                            .foregroundColor(on ? p.fg : p.faint)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pace: \(pace.level.label.lowercased()), \(pace.text)")
        }
    }

    private func fiveHour(_ p: TidePalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("5 hours", details.fiveHour.resets, p)
            HStack(spacing: 6) {
                Text("\(details.fiveHour.used)% used").font(.system(size: 10.5)).foregroundColor(p.dim).monospacedDigit()
                    .fixedSize()
                FiveHourLine(used: Double(details.fiveHour.used), now: details.fiveHour.now)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("5 hours: \(details.fiveHour.used)% used, \(details.fiveHour.resets)")
    }

    private func caption(_ left: String, _ right: String, _ p: TidePalette) -> some View {
        HStack {
            Text(left.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
            Spacer(minLength: 8)
            Text(right).font(.system(size: 9.5))
        }
        .foregroundColor(p.faint)
        .accessibilityHidden(true)
    }

    private func divider(_ p: TidePalette) -> some View {
        Rectangle().fill(p.line).frame(height: 1)
    }
}
