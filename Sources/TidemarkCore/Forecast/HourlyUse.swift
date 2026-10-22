import Foundation

/// The week % used in one clock hour.
public struct HourUse: Equatable, Sendable {
    public var start: Date
    public var used: Double

    public init(start: Date, used: Double) {
        self.start = start
        self.used = used
    }
}

public enum HourlyUse {
    /// Week % used in each clock hour of the plan's current window, up to now, spread evenly over the
    /// time between readings; hours with nothing used are left out. Before the first reading it spreads
    /// from 0 at the window's start. Same window rules as `WeekPie`.
    ///
    /// `measuredOnly` leaves out what was never seen: the stretch before the first reading (whatever was used
    /// before Tidemark looked is not known to have been used then) and any gap between readings longer than
    /// `longestGap` (the Mac asleep). Use it for "busiest hours"; the chart's bars take everything.
    public static func hours(reading: Reading, history: [Reading], now: Date,
                             calendar: Calendar = .autoupdatingCurrent, measuredOnly: Bool = false) -> [HourUse] {
        guard let window = WeekWindow(reading: reading, history: history, until: now) else { return [] }
        var used: [Date: Double] = [:]
        for (index, (a, b)) in zip(window.line, window.line.dropFirst()).enumerated() {
            let span = b.time.timeIntervalSince(a.time)
            let rise = b.value - a.value
            guard span > 0, rise > 0, a.time < now else { continue }
            // The line's first segment runs from an invented zero at the window's start.
            if measuredOnly, index == 0 || span > longestGap { continue }
            let end = min(b.time, now)
            var t = a.time
            while t < end, let hour = calendar.dateInterval(of: .hour, for: t) {
                let to = min(hour.end, end)
                used[hour.start, default: 0] += rise * to.timeIntervalSince(t) / span
                t = to
            }
        }
        return used.map { HourUse(start: $0.key, used: $0.value) }.filter { $0.used > 0 }.sorted { $0.start < $1.start }
    }

    /// The longest stretch between two readings that still counts as measured (3 hours).
    public static let longestGap: TimeInterval = 3 * 3600

    /// The busiest hours of the plan's week from what was really measured: none before two readings of this
    /// week, and never the stretch before the first or a long gap.
    public static func measuredBusiest(reading: Reading, history: [Reading], now: Date,
                                       calendar: Calendar = .autoupdatingCurrent, count: Int = 3) -> [HourUse] {
        guard (WeekWindow(reading: reading, history: history, until: now)?.points.count ?? 0) >= 2 else { return [] }
        return busiest(hours(reading: reading, history: history, now: now, calendar: calendar, measuredOnly: true), count: count)
    }

    /// The `count` busiest, most first; ties go to the earlier hour; only hours of at least 0.1%.
    public static func busiest(_ hours: [HourUse], count: Int = 3) -> [HourUse] {
        Array(hours.filter { $0.used >= 0.1 }
            .sorted { $0.used != $1.used ? $0.used > $1.used : $0.start < $1.start }
            .prefix(max(count, 0)))
    }
}

extension UsageCopy {
    /// An hour as a range: "Tue 4–5 PM", "Tue 11 AM–12 PM"; on a 24-hour clock "Tue 16:00–17:00".
    public static func hourRange(_ start: Date, formatting: Formatting) -> String {
        let from = formatting.hour(start)
        let to = formatting.hour(start.addingTimeInterval(3600))
        let day = formatting.weekday(start)
        if formatting.twentyFourHour { return "\(day) \(from)–\(to)" }
        let a = from.split(separator: " "), b = to.split(separator: " ")
        if a.count == 2, b.count == 2, a[1] == b[1] { return "\(day) \(a[0])–\(to)" }
        return "\(day) \(from)–\(to)"
    }
}
