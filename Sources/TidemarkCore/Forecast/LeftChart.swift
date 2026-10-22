import Foundation

/// One clock hour's use, as a bar under the left chart: x and width are shares of the window (0...1).
public struct HourBar: Equatable, Sendable {
    public var x: Double
    public var width: Double
    /// Week % used in the hour.
    public var used: Double

    public init(x: Double, width: Double, used: Double) {
        self.x = x
        self.width = width
        self.used = used
    }
}

/// What's left through the week, for the Usage page's chart and the details card's small one. x runs
/// 0...1 through the window; y is the share left (1 - % used / 100), like `ChartPoint` elsewhere.
public struct LeftChart: Equatable, Sendable {
    public var start: Date
    public var reset: Date
    /// What's left, from the window's start to now.
    public var left: [ChartPoint]
    /// nil for last week.
    public var now: ChartPoint?
    /// Where the dashed line ends: 0 at the run-out, or the reset's forecast. nil with no forecast
    /// (and once it is out).
    public var forecastEnd: ChartPoint?
    /// x where the hatch starts (the run-out, or when it ran out).
    public var lockedFrom: Double?
    /// From `HourlyUse`.
    public var hours: [HourBar]
    /// The plan's own days: start + 0...7 days.
    public var days: [AxisTick]

    private static func chart(window: WeekWindow, upTo end: Date, reading: Reading, history: [Reading], calendar: Calendar) -> LeftChart {
        let start = window.start
        func y(_ used: Double) -> Double { 1 - used / 100 }
        let left = [ChartPoint(x: 0, y: 1)]
            + window.points.filter { $0.time > start && $0.time <= end }.map { ChartPoint(x: window.x($0.time), y: y($0.value)) }
        let bars = HourlyUse.hours(reading: reading, history: history, now: end, calendar: calendar).compactMap { hour -> HourBar? in
            let from = max(hour.start.timeIntervalSince(start), 0)
            let to = min(hour.start.timeIntervalSince(start) + 3600, Pace.window)
            return to > from ? HourBar(x: from / Pace.window, width: (to - from) / Pace.window, used: hour.used) : nil
        }
        let days = (0...7).map { AxisTick(date: start.addingTimeInterval(Double($0) * WeekWindow.day), x: Double($0) / 7) }
        return LeftChart(start: start, reset: window.reset, left: left, now: nil, forecastEnd: nil, lockedFrom: nil,
                         hours: bars, days: days)
    }

    /// nil without an open week.
    public static func make(reading: Reading, history: [Reading], now: Date) -> LeftChart? {
        make(reading: reading, history: history, now: now, calendar: .autoupdatingCurrent)
    }

    static func make(reading: Reading, history: [Reading], now: Date, calendar: Calendar) -> LeftChart? {
        guard let reset = reading.weekResetsAt, reset > now,
              let window = WeekWindow(reading: reading, history: history, until: now) else { return nil }
        var chart = chart(window: window, upTo: now, reading: reading, history: history, calendar: calendar)
        let nowPoint = ChartPoint(x: window.x(now), y: 1 - reading.week / 100)
        if chart.left.last?.x != nowPoint.x { chart.left.append(nowPoint) } else { chart.left[chart.left.count - 1] = nowPoint }
        chart.now = nowPoint
        if reading.week >= 100 {
            chart.lockedFrom = window.x(window.reachedFull ?? reading.time)
        } else if let forecast = Pace.forecast(reading, history: history, now: now), !forecast.settling {
            // A week still settling has no pace of its own to draw ahead.
            if let out = forecast.runsOutAt, out < reset {
                chart.forecastEnd = ChartPoint(x: window.x(out), y: 0)
                chart.lockedFrom = window.x(out)
            } else {
                chart.forecastEnd = ChartPoint(x: 1, y: 1 - forecast.forecastAtReset / 100)
            }
        }
        return chart
    }

    /// The window before this one, read back from history: no now, no forecast. nil without readings in it.
    public static func lastWeek(reading: Reading, history: [Reading]) -> LeftChart? {
        lastWeek(reading: reading, history: history, calendar: .autoupdatingCurrent)
    }

    static func lastWeek(reading: Reading, history: [Reading], calendar: Calendar) -> LeftChart? {
        guard let reset = reading.weekResetsAt else { return nil }
        // The reset a week back, give or take: claude.ai's reset moves by a few seconds.
        let expected = reset.addingTimeInterval(-Pace.window)
        let earlier = history.filter { $0.org == reading.org }
            .filter { r in r.weekResetsAt.map { abs($0.timeIntervalSince(expected)) <= 3600 } ?? false }
        guard let priorReset = earlier.compactMap(\.weekResetsAt).max() else { return nil }
        let inWindow = earlier.filter { $0.weekResetsAt == priorReset && $0.time <= priorReset }
        guard let last = inWindow.max(by: { $0.time < $1.time }),
              let window = WeekWindow(reading: last, history: inWindow, until: priorReset) else { return nil }
        var chart = chart(window: window, upTo: priorReset, reading: last, history: inWindow, calendar: calendar)
        if let full = window.reachedFull { chart.lockedFrom = window.x(full) }
        return chart
    }
}
