import SwiftUI
import TidemarkCore

/// The week's days as columns of time: one block per session span, side by side where they overlap.
/// 09:00–18:00 unless a session runs outside it.
struct WeekGrid: View {
    let week: WeekModel
    let now: Date
    let calendar: Calendar
    var twentyFourHour = Formatting.prefers24Hour()

    private static let hourHeight: CGFloat = 44
    private static let axisWidth: CGFloat = 44

    /// The first and last hour shown.
    private var hours: (first: Int, last: Int) {
        var first = 9, last = 18
        for span in week.items.flatMap(\.spans) {
            first = min(first, calendar.component(.hour, from: span.start))
            var end = calendar.component(.hour, from: span.end)
            if calendar.component(.minute, from: span.end) > 0 || calendar.component(.second, from: span.end) > 0 { end += 1 }
            if !calendar.isDate(span.end, inSameDayAs: span.start) { end = 24 }
            last = max(last, end)
        }
        return (max(first, 0), min(max(last, first + 1), 24))
    }

    var body: some View {
        let range = hours
        let height = CGFloat(range.last - range.first) * Self.hourHeight
        let lanes = WeekLayout.lanes(week.items)
        let shared = WeekLayout.hiddenBehind(week.items)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.axisWidth)
                ForEach(0..<7, id: \.self) { d in
                    HStack(spacing: 3) {
                        Text(weekday(d)).foregroundStyle(Palette.dim)
                        Text(dayNumber(d)).fontWeight(.bold).foregroundStyle(Palette.bright)
                    }
                    .font(Theme.font(11))
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                axis(range)
                    .frame(width: Self.axisWidth, height: height, alignment: .top)
                ForEach(0..<7, id: \.self) { d in
                    column(d, range: range, height: height, lanes: lanes, shared: shared)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week calendar")
    }

    private func weekday(_ d: Int) -> String {
        WindowCopy.dayHeading(week, day: d, now: now, calendar: calendar).split(separator: " ").first.map(String.init) ?? ""
    }

    private func dayNumber(_ d: Int) -> String {
        WindowCopy.dayHeading(week, day: d, now: now, calendar: calendar).split(separator: " ").last.map(String.init) ?? ""
    }

    private func axis(_ range: (first: Int, last: Int)) -> some View {
        let clock = Formatting(calendar: calendar, twentyFourHour: twentyFourHour)
        return ZStack(alignment: .topTrailing) {
            ForEach(range.first..<range.last, id: \.self) { h in
                let date = calendar.date(bySettingHour: h, minute: 0, second: 0, of: week.start) ?? week.start
                Text(twentyFourHour ? String(format: "%02d:00", h) : clock.hour(date))
                    .font(Theme.font(10)).foregroundStyle(Palette.faint)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(h - range.first) * Self.hourHeight - 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ d: Int, range: (first: Int, last: Int), height: CGFloat,
                        lanes: [String: (lane: Int, lanes: Int)], shared: [String: [WeekItem]]) -> some View {
        let items = week.items.filter { $0.day == d }
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { order, item in
                    let place = lanes[item.id] ?? (0, 1)
                    let laneWidth = geo.size.width / CGFloat(place.lanes)
                    ForEach(Array(item.spans.enumerated()), id: \.offset) { index, span in
                        let top = offset(span.start, d, range) + 1
                        let h = max(offset(span.end, d, range) - offset(span.start, d, range) - 2, 16)
                        Block(item: item, height: h, narrow: laneWidth < 60)
                            .frame(width: max(laneWidth - 6, 8), height: h)
                            .offset(x: CGFloat(place.lane) * laneWidth + 3, y: top)
                            // Where sessions share the last lane, the earliest sits on top.
                            .zIndex(Double(items.count - order))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(index == 0
                                ? WindowCopy.voiceOver(item, sharing: (shared[item.id] ?? []).map(\.title), calendar: calendar, twentyFourHour: twentyFourHour)
                                : "\(item.title), a later part of the same session")
                    }
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
    }

    /// Points from the grid's top to `date` on day `d`, by the wall clock so a 23 or 25 hour day
    /// still lines up with its hour labels.
    private func offset(_ date: Date, _ d: Int, _ range: (first: Int, last: Int)) -> CGFloat {
        guard week.days.indices.contains(d) else { return 0 }
        let hours = WeekLayout.hourOffset(date, onDay: week.days[d], firstHour: range.first, calendar: calendar)
        return CGFloat(hours) * Self.hourHeight
    }

    /// One session's span: a bar in the project's colour, a tint, the title.
    private struct Block: View {
        let item: WeekItem
        let height: CGFloat
        var narrow = false

        var body: some View {
            let tone = Palette.c[min(item.colorIndex, 6)]
            let shape = RoundedRectangle(cornerRadius: 3)
            HStack(spacing: 0) {
                Rectangle().fill(tone).frame(width: 3)
                Text(item.title)
                    .font(Theme.font(10.5, .semibold))
                    .foregroundStyle(Palette.bright)
                    .lineLimit(height > 34 && !narrow ? 2 : 1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(tone.opacity(0.18))
            .background(Palette.tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.dim, style: StrokeStyle(lineWidth: item.noCommit ? 1 : 0, dash: [3, 2])))
        }
    }
}
