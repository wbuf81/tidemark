import Foundation

/// Where a limit's usage is heading (the week's, a model limit's or the 5-hour window's). Percentages are of that limit.
public struct WeekForecast: Equatable, Sendable {
    var used: Double
    var hoursLeft: Double
    /// Share of the limit's window gone, 0...1.
    var elapsedFraction: Double
    var pacePerHour: Double
    var forecastAtReset: Double
    /// What would be left unused at reset at the current pace.
    var unused: Double
    /// Set when the current pace uses everything before reset.
    var runsOutEarlyByHours: Double?
    var runsOutAt: Date?
    /// The pace that uses exactly everything by reset.
    var useItAllPerHour: Double
    /// How much more to use before local midnight to stay on the use-it-all pace.
    var byMidnight: Double
    /// A week (or model limit) too new to forecast a run-out from: its first hours' pace says nothing about the week.
    /// While it settles nothing runs out early, so a fresh reset never shows red or sends a run-out notice.
    public internal(set) var settling = false

    var pacePerDay: Double { pacePerHour * 24 }
    var useItAllPerDay: Double { useItAllPerHour * 24 }
}

public enum Pace {
    public static let window: TimeInterval = 7 * 24 * 3600
    static let lookback: TimeInterval = 72 * 3600
    /// How long a new week settles before its pace can forecast a run-out; only windows longer than a day settle.
    static let settle: TimeInterval = 12 * 3600
    static let settleWindowsFrom: TimeInterval = 24 * 3600
    /// Half used during the settling hours is a real warning, so the forecast runs anyway.
    static let settleUnlessUsed = 50.0

    /// The week's forecast, counted from the reading's own time: the same reading read again
    /// later gives the same run-out time instead of one that slides later while the app is
    /// offline. nil when the week hasn't started or has already reset.
    public static func forecast(_ reading: Reading, history: [Reading], now: Date,
                                calendar: Calendar = .autoupdatingCurrent) -> WeekForecast? {
        guard let reset = reading.weekResetsAt else { return nil }
        let now = min(now, reading.time)
        let past = history
            .filter { $0.org == reading.org && $0.weekResetsAt == reset }
            .map { LimitPoint(time: $0.time, value: $0.week) }
        return forecast(used: reading.week, resetsAt: reset, window: window, lookback: lookback,
                        past: past, now: now, calendar: calendar)
    }

    /// Where any limit is heading: `used` % of it now, resetting at `reset` at the end of a
    /// window `window` long. The pace is measured from the newest point in `past` (this
    /// window's earlier readings) that is at least `lookback` old; without one, it's the
    /// average since the window started. nil when the window has already reset.
    static func forecast(used: Double, resetsAt reset: Date, window: TimeInterval, lookback: TimeInterval,
                                past: [LimitPoint], now: Date,
                                calendar: Calendar = .autoupdatingCurrent) -> WeekForecast? {
        guard reset > now else { return nil }
        let left = 100 - used
        let hoursLeft = reset.timeIntervalSince(now) / 3600
        let hoursElapsed = max(now.timeIntervalSince(reset.addingTimeInterval(-window)) / 3600, 1.0 / 60)

        var pace = used / hoursElapsed
        let cutoff = now.addingTimeInterval(-lookback)
        if let old = past.filter({ $0.time <= cutoff }).max(by: { $0.time < $1.time }) {
            pace = max((used - old.value) / (now.timeIntervalSince(old.time) / 3600), 0)
        }

        // A week's first hours say nothing about the week: forecast from the even pace until it settles,
        // unless half is already gone (a real warning). The 5-hour window is short enough to forecast at once.
        let settling = window > settleWindowsFrom && hoursElapsed * 3600 < settle && used < settleUnlessUsed
        if settling { pace = left / hoursLeft }

        var runsOutEarly: Double?
        var runsOutAt: Date?
        if !settling, pace > 0, pace * hoursLeft > left {
            let hoursToEmpty = left / pace
            runsOutEarly = hoursLeft - hoursToEmpty
            runsOutAt = now.addingTimeInterval(hoursToEmpty * 3600)
        }
        let forecast = min(100, used + pace * hoursLeft)
        let useItAll = left / hoursLeft
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let hoursToMidnight = min(midnight.timeIntervalSince(now) / 3600, hoursLeft)

        return WeekForecast(
            used: used,
            hoursLeft: hoursLeft,
            elapsedFraction: min(hoursElapsed * 3600 / window, 1),
            pacePerHour: pace,
            forecastAtReset: forecast,
            unused: 100 - forecast,
            runsOutEarlyByHours: runsOutEarly,
            runsOutAt: runsOutAt,
            useItAllPerHour: useItAll,
            byMidnight: useItAll * hoursToMidnight,
            settling: settling
        )
    }
}
