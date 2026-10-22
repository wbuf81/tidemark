import SwiftUI
import TidemarkCore

/// The chosen plan under the cards: the Week panel (its tide chart, or a model or 5-hour limit's detail by
/// tab), then Pace and the busiest hours side by side.
struct UsageDetail: View {
    @ObservedObject var model: AppModel
    let org: Org
    let summary: UsageSummary
    @ObservedObject var chosen: UsageSelection
    @Environment(\.colorScheme) private var scheme

    /// The plan's limits that are shown, in row order.
    private var kinds: [LimitKind] { summary.limits.filter { $0.id.org == org.id }.map(\.id.kind) }

    var body: some View {
        // A limit that went away (a hidden model's) falls back to the week.
        let kind = kinds.contains(chosen.kind) ? chosen.kind : .week
        VStack(alignment: .leading, spacing: 12) {
            weekPanel(kind)
            if let raw = model.latest[org.id] {
                HStack(alignment: .top, spacing: 12) {
                    PacePanel(model: model, org: org, reading: raw.adjusted(to: model.now))
                    BusiestPanel(model: model, reading: raw.adjusted(to: model.now))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The Week panel

    private func weekPanel(_ kind: LimitKind) -> some View {
        let p = TidePalette.for(scheme)
        let now = model.now, f = model.formatting
        let raw = model.latest[org.id]
        let reading = raw?.adjusted(to: now)
        let previous = kind == .week ? reading.flatMap { LeftChart.lastWeek(reading: $0, history: model.history) } : nil
        let showsLast = previous != nil && chosen.lastWeek
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if kinds.count > 1 { tabs(kind, p) } else {
                        Text("Week").font(Theme.font(14, .bold)).foregroundStyle(p.fg).accessibilityAddTraits(.isHeader)
                    }
                    Text(subtitle(kind, last: showsLast)).font(Theme.font(11.5)).foregroundStyle(p.faint)
                }
                Spacer(minLength: 8)
                if previous != nil { segment(p) }
            }
            if let raw, let reading {
                if kind == .week {
                    if let chart = showsLast ? previous : LeftChart.make(reading: reading, history: model.history, now: now) {
                        if raw.isFresh(now: now) == false, !showsLast {
                            Text(UsageCopy.asOfLine(raw.time, now: now, formatting: f)).font(Theme.font(11.5)).foregroundStyle(p.dim)
                        }
                        TideChart(chart: chart, name: org.name, now: now, formatting: f, last: showsLast, isOld: !raw.isFresh(now: now))
                        chartLegend(chart, p)
                    } else {
                        note("Not started. It starts when you next use it.", p)
                    }
                } else {
                    limit(kind, raw: raw, reading: reading)
                }
            } else {
                note(UsageCopy.unreadLine(model.orgProblems[org.id]), p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func note(_ text: String, _ p: TidePalette) -> some View {
        Text(text).font(Theme.font(12)).foregroundStyle(p.dim)
    }

    private func subtitle(_ kind: LimitKind, last: Bool) -> String {
        switch kind {
        case .week: "\(org.name) · weekly limit · \(last ? "last week" : "this week and ahead")"
        case .model(let name): "\(org.name) · \(name) limit"
        case .session: "\(org.name) · 5-hour window"
        }
    }

    private func tabs(_ current: LimitKind, _ p: TidePalette) -> some View {
        HStack(spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                let on = kind == current
                Button { chosen.kind = kind } label: {
                    Text(Self.word(kind))
                        .font(Theme.font(12, on ? .semibold : .regular))
                        .foregroundStyle(on ? p.fg : p.dim)
                        .padding(.vertical, 3).padding(.horizontal, 10)
                        .background(on ? p.sel : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? p.fg.opacity(0.35) : p.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(org.name), \(Self.word(kind))")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Now / Last week.
    private func segment(_ p: TidePalette) -> some View {
        HStack(spacing: 2) {
            ForEach([("Now", false), ("Last week", true)], id: \.0) { label, last in
                let on = chosen.lastWeek == last
                Button { chosen.lastWeek = last } label: {
                    Text(label).font(Theme.font(11.5, on ? .semibold : .regular)).foregroundStyle(on ? p.fg : p.dim)
                        .padding(.vertical, 3).padding(.horizontal, 10)
                        .background(on ? p.sel : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
    }

    private func chartLegend(_ chart: LeftChart, _ p: TidePalette) -> some View {
        WrapLayout(spacing: 14) {
            key("\(org.name), what’s left") { Rectangle().fill(p.fg).frame(width: 14, height: 2) }
            if chart.forecastEnd != nil {
                key("If the pace holds") {
                    Canvas { ctx, size in
                        var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        ctx.stroke(line, with: .color(p.fg), style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))
                    }.frame(width: 14, height: 2)
                }
            }
            if chart.lockedFrom != nil { key("Locked") { LockedSwatch(size: 10) } }
            if !chart.hours.isEmpty {
                key("Used per hour") { RoundedRectangle(cornerRadius: 1).fill(p.fg.opacity(0.62)).frame(width: 4, height: 10) }
            }
        }
        .font(Theme.font(11.5)).foregroundStyle(p.dim)
    }

    private func key<S: View>(_ text: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 5) { swatch(); Text(text).fixedSize() }
    }

    private static func word(_ kind: LimitKind) -> String {
        switch kind {
        case .week: "Week"
        case .model(let name): name
        case .session: "5 hours"
        }
    }

    // MARK: Model and 5-hour limits

    @ViewBuilder private func limit(_ kind: LimitKind, raw: Reading, reading: Reading) -> some View {
        let id = LimitID(org: org.id, kind: kind)
        let now = model.now, f = model.formatting, t = model.settings.thresholds
        let p = TidePalette.for(scheme)
        let stale = !raw.isFresh(now: now)
        if let detail = LimitDetails.make(id, reading: reading, history: model.history, now: now, thresholds: t) {
            LimitDetailView(detail: detail, title: UsageCopy.detailTitle(kind, org: org.name), subtitle: resets(kind, now),
                            asOf: stale ? UsageCopy.asOfLine(raw.time, now: now, formatting: f) : nil,
                            old: stale, now: now, formatting: f, thresholds: t, today: nil, showsTitle: false)
        } else {
            note(kind == .session ? "Not started. It opens when you next use it." : "Not started. It starts when you next use it.", p)
        }
    }

    /// When this limit resets.
    private func resets(_ kind: LimitKind, _ now: Date) -> String {
        summary.limits.first { $0.id == LimitID(org: org.id, kind: kind) }?.resetsAt
            .map { (kind == .session ? "Window ends " : "Resets ") + model.formatting.dayTime($0, now: now) } ?? ""
    }
}

/// How the week's use compares with an even share: three segments, a knob in the one that fits, then what
/// that means for today.
private struct PacePanel: View {
    @ObservedObject var model: AppModel
    let org: Org
    let reading: Reading
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        let now = model.now, f = model.formatting
        let pace = PaceReading.make(reading: reading, now: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pace").font(Theme.font(11.5, .semibold))
                Spacer()
                Text(([org.name] + [pace?.text].compactMap { $0 }).joined(separator: " · ")).font(Theme.font(11.5))
            }
            .foregroundStyle(p.faint)
            if let pace {
                HStack(spacing: 6) {
                    ForEach([PaceLevel.light, .even, .fast], id: \.self) { level in
                        let on = level == pace.level
                        VStack(spacing: 5) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(p.track)
                                    if on {
                                        Circle().fill(p.fg).frame(width: 15, height: 15)
                                            .overlay(Circle().stroke(p.glass, lineWidth: 3))
                                            .offset(x: min(max(Self.position(pace) * geo.size.width - 7.5, 0), geo.size.width - 15))
                                    }
                                }
                                .frame(height: 7).frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 15)
                            Text(level.label).font(Theme.font(11.5, on ? .semibold : .regular)).foregroundStyle(on ? p.fg : p.faint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let lead = UsageCopy.paceLead(reading: reading, now: now) {
                    Text(lead).foregroundStyle(p.fg)
                }
                let today = Copy.today(reading, forecast: model.forecast(for: org), now: now, formatting: f, model.settings.thresholds)
                let line = UsageCopy.todayLine(today)
                Text(line.main).foregroundStyle(p.fg)
                if let warning = line.warning {
                    Text(warning).foregroundStyle(today.warningRunsOut ? p.red : p.dim)
                }
            }
            .font(Theme.font(12.5)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    /// Where the knob sits in its segment: Light runs to 0.85×, Even to 1.15×, Fast on to 2×.
    private static func position(_ pace: PaceReading) -> Double {
        let (lo, hi): (Double, Double) = switch pace.level {
        case .light: (0, 0.85)
        case .even: (0.85, 1.15)
        case .fast: (1.15, 2)
        }
        return min(max((pace.multiple - lo) / (hi - lo), 0.08), 0.92)
    }
}

/// The three hours that took the most of the week.
private struct BusiestPanel: View {
    @ObservedObject var model: AppModel
    let reading: Reading
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        let hours = HourlyUse.measuredBusiest(reading: reading, history: model.history, now: model.now)
        let rows = UsageCopy.busiestRows(hours, formatting: model.formatting)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Busiest hours").font(Theme.font(11.5, .semibold))
                Spacer()
                Text("used that hour").font(Theme.font(11.5))
            }
            .foregroundStyle(p.faint)
            if rows.isEmpty {
                Text("No busy hours yet this week.").font(Theme.font(12.5)).foregroundStyle(p.dim)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.hour).font(Theme.font(10, .bold)).foregroundStyle(p.dim)
                        .frame(width: 24).padding(.vertical, 2).background(p.sel, in: RoundedRectangle(cornerRadius: 4))
                    Text(row.range).font(Theme.font(12.5)).foregroundStyle(p.fg)
                    Spacer()
                    Text(row.used).font(Theme.font(12.5, .semibold)).foregroundStyle(p.fg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }
}
