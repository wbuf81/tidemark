import Foundation

/// One plan's week window read off its readings: the week % at any moment, linear between readings
/// and, before the first one, linear from 0 at the window's start. Shared by the week pie, the hourly
/// use and the left chart so they agree.
struct WeekWindow {
    var start: Date
    var reset: Date
    /// This window's readings, oldest first, one per moment; `reading` wins a tie.
    var points: [LimitPoint]

    static let day: TimeInterval = 86_400

    /// nil when `reading` has no week yet. Readings count when they have the same org and reset and
    /// were taken by `until` (the reading itself always counts).
    init?(reading: Reading, history: [Reading], until: Date) {
        guard let reset = reading.weekResetsAt else { return nil }
        self.reset = reset
        start = reset.addingTimeInterval(-Pace.window)
        var byTime: [Date: Double] = [:]
        for r in history where r.org == reading.org && r.weekResetsAt == reset && r.time <= until {
            byTime[r.time] = r.week
        }
        byTime[reading.time] = reading.week
        points = byTime.map { LimitPoint(time: $0.key, value: $0.value) }.sorted { $0.time < $1.time }
    }

    /// Week % used at `date`.
    func value(at date: Date) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if date >= last.time { return last.value }
        if date <= first.time {
            let span = first.time.timeIntervalSince(start)
            guard span > 0, date > start else { return date >= first.time ? first.value : 0 }
            return first.value * date.timeIntervalSince(start) / span
        }
        for (a, b) in zip(points, points.dropFirst()) where date <= b.time {
            let span = b.time.timeIntervalSince(a.time)
            return span > 0 ? a.value + (b.value - a.value) * date.timeIntervalSince(a.time) / span : b.value
        }
        return last.value
    }

    /// When a reading first showed 100%.
    var reachedFull: Date? { points.first { $0.value >= 100 }?.time }

    /// Share of the window gone at `date`, 0...1.
    func x(_ date: Date) -> Double { min(max(date.timeIntervalSince(start) / Pace.window, 0), 1) }

    /// The plan's own day (0...6) and how much of it had gone at `date`.
    func dayPoint(_ date: Date) -> (day: Int, fraction: Double) {
        let days = date.timeIntervalSince(start) / Self.day
        let day = min(max(Int(days.rounded(.down)), 0), 6)
        return (day, min(max(days - Double(day), 0), 1))
    }

    /// `(start, 0)` then this window's readings after it: the line the hourly use is read from.
    var line: [LimitPoint] { [LimitPoint(time: start, value: 0)] + points.filter { $0.time > start } }
}
