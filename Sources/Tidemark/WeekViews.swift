import SwiftUI
import TidemarkCore

/// Seven upright cells, Monday to Sunday (or as the calendar's week runs), each filled by its share
/// of the busiest day, today outlined.
struct DayCells: View {
    let levels: [Double]
    let today: Int?
    let k: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 2 * k) {
            ForEach(0..<max(levels.count, 7), id: \.self) { i in
                let shape = RoundedRectangle(cornerRadius: 1.5 * k)
                GlanceCell(shape: shape, track: Palette.track, color: Palette.blue,
                           fill: CGFloat(i < levels.count ? levels[i] : 0), hatched: false, k: k, vertical: true)
                    .overlay { if i == today { shape.stroke(Palette.bright.opacity(0.55), lineWidth: max(k, 1)) } }
            }
        }
        .frame(height: height)
    }
}

/// The week band at the end of the widget, when a week calendar is set up: this week's hours, a
/// cell per day and the project with the most time. Its numbers go dim (never the whole band, which
/// would fail contrast) when the calendar hasn't written lately or the week is over.
struct WeekBandView: View {
    let week: WeekSummary
    let now: Date
    let k: CGFloat
    /// "tide-tables · 10h": the top project with its hours, for the widget without plan limits.
    var showsTopHours = false
    let open: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let old = week.isStale(now: now) || week.isPast(now: now, calendar: calendar)
        VStack(alignment: .leading, spacing: 4 * k) {
            HStack(alignment: .firstTextBaseline, spacing: 5 * k) {
                Text("Week").font(Theme.font(11 * k)).foregroundStyle(Palette.faint)
                Text(WeekSummary.shortHours(week.week.seconds)).font(Theme.font(12.5 * k, .bold))
                    .foregroundStyle(old ? Palette.dim : Palette.bright)
                if !week.problems.isEmpty {
                    Text("!").font(Theme.font(11.5 * k, .bold)).foregroundStyle(Palette.amberInk)
                }
            }
            DayCells(levels: week.dayLevels, today: week.todayIndex(now: now, calendar: calendar), k: k, height: 14 * k)
            Text(topLine)
                .font(Theme.font(11 * k)).foregroundStyle(Palette.dim)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 8 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .orgButton(week.sentence, open: open)
    }

    /// The project with the most time, and with `showsTopHours` its hours.
    private var topLine: String {
        guard let top = week.week.projects.first else { return "No sessions yet" }
        return showsTopHours ? "\(top.name) · \(WeekSummary.shortHours(top.seconds))" : top.name
    }
}
