import SwiftUI
import TidemarkCore

/// One plan on the sky (the mockups' `tdcard`): its mark and name, what's left in big light numbers beside
/// the forecast pie, what the week comes to, the lock, the pace and the 5-hour line. A plan that couldn't be
/// read says why in place of the numbers. The whole card is a button that selects the plan.
struct UsagePlanCard: View {
    @ObservedObject var model: AppModel
    let org: Org
    let plan: UsageSummary.Plan
    let selected: Bool
    let choose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: choose) { content }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plan.voiceOver)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var content: some View {
        let p = TidePalette.for(scheme)
        let now = model.now, f = model.formatting, t = model.settings.thresholds
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StateShape(plan.state, hollow: plan.stale, size: 9)
                Text(org.name).font(Theme.font(13, .semibold)).foregroundStyle(p.fg).lineLimit(1)
                Spacer(minLength: 4)
                Text("week").font(Theme.font(11.5)).foregroundStyle(p.faint)
            }
            if let raw = model.latest[org.id] {
                let r = raw.adjusted(to: now)
                let old = plan.stale
                let forecast = model.forecast(for: org)
                let state = plan.state ?? .fine
                let verdict = PlanVerdict.make(reading: r, forecast: forecast, state: state, now: now, formatting: f, thresholds: t)
                HStack(alignment: .center) {
                    (Text("\(Int(max(100 - r.week, 0).rounded()))").font(.system(size: 44, weight: .light))
                        + Text("% left").font(.system(size: 17.6)))
                        .monospacedDigit().foregroundStyle(old ? p.dim : p.fg).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    if let pie = WeekPie.make(reading: r, history: model.history, now: now) {
                        ForecastPie(pie: pie, size: 64, isOld: old)
                    }
                }
                if old {
                    Text(UsageCopy.asOfLine(raw.time, now: now, formatting: f)).font(Theme.font(12.5)).foregroundStyle(p.dim)
                }
                Text(UsageCopy.lastsLine(reading: r, forecast: forecast, now: now, formatting: f, thresholds: t) ?? verdict.untilEmpty ?? verdict.line)
                    .font(Theme.font(12.5)).foregroundStyle(p.fg).fixedSize(horizontal: false, vertical: true)
                if let locked = verdict.locked {
                    HStack(spacing: 6) {
                        LockedSwatch()
                        Text(locked).font(Theme.font(12.5)).foregroundStyle(p.red)
                    }
                }
                if state != .out, let pace = PaceReading.make(reading: r, now: now) {
                    Text(UsageCopy.paceLine(pace)).font(Theme.font(12.5)).foregroundStyle(p.dim)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text("5h").font(Theme.font(11.5)).foregroundStyle(p.faint)
                    FiveHourLine(used: r.session)
                    Text("\(Int(r.session.rounded()))%").font(Theme.font(11.5, .semibold)).foregroundStyle(p.fg)
                    Text(r.sessionResetsAt.map { f.dayTime($0, now: now) } ?? "not started")
                        .font(Theme.font(11.5)).foregroundStyle(p.faint).lineLimit(1)
                }
            } else {
                Text("—").font(.system(size: 44, weight: .light)).foregroundStyle(p.dim)
                Text(plan.end).font(Theme.font(12.5)).foregroundStyle(p.dim).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(selected: selected)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// "Claude Code is on" and the plan it is on, with its status and today's switch advice.
struct UsageCodeCard: View {
    @ObservedObject var model: AppModel
    let org: Org
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Claude Code is on").font(Theme.font(13, .semibold)).foregroundStyle(p.fg)
                Spacer(minLength: 4)
                if let mood = model.codeMood { StatusChip(mood: mood, compact: false) }
            }
            Text(org.name).font(.system(size: 26, weight: .light)).foregroundStyle(p.fg).lineLimit(1).minimumScaleFactor(0.6)
            if let advice = model.advice {
                advise(UsageCopy.switchHow(to: advice.target.name, reason: advice.reason), p)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    /// The advice, with `/login` set as code.
    private func advise(_ text: String, _ p: TidePalette) -> some View {
        let parts = text.components(separatedBy: "/login")
        var t = Text(parts[0])
        for part in parts.dropFirst() {
            t = t + Text("/login").font(.system(size: 12, design: .monospaced)) + Text(part)
        }
        return t.font(Theme.font(12.5)).foregroundStyle(p.dim).fixedSize(horizontal: false, vertical: true)
    }
}
