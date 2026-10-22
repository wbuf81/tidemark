import Foundation

/// The words the Usage page adds to the forecast pieces: a plan card's fine line, the pace line and note,
/// the chart's tip and the busiest hours' rows.
extension UsageCopy {
    /// "Lasts to reset Fri 4 AM, about 20% to spare", or "..., on pace to use it all". nil without an open
    /// week, or when the week runs out before it resets or is out.
    public static func lastsLine(reading r: Reading, forecast: WeekForecast?, now: Date, formatting: Formatting,
                                 thresholds: Thresholds = Thresholds()) -> String? {
        guard let reset = r.weekResetsAt, reset > now, r.week < 100, let f = forecast else { return nil }
        if f.runsOutEarlyByHours != nil { return nil }
        let head = "Lasts to reset \(formatting.dayTime(reset, now: now))"
        return f.unused >= thresholds.onPaceUnused
            ? "\(head), about \(Formatting.percent(f.unused)) to spare"
            : "\(head), on pace to use it all"
    }

    /// "Light pace: 0.8× even"
    public static func paceLine(_ pace: PaceReading) -> String { "\(pace.level.label) pace: \(pace.text)" }

    /// "Used 81% in 44% of the week."; nil without an open week.
    public static func paceLead(reading r: Reading, now: Date) -> String? {
        guard let reset = r.weekResetsAt, reset > now else { return nil }
        let elapsed = (Pace.window - reset.timeIntervalSince(now)) / Pace.window * 100
        return "Used \(Formatting.percent(r.week)) in \(Formatting.percent(min(max(elapsed, 0), 100))) of the week."
    }

    /// The two lines in the chart's tip beside the locked stretch.
    public struct ChartTip: Equatable, Sendable {
        public var title: String
        public var detail: String
    }

    /// "Empty Thu 10 PM" and "Locked 59 h until Sun 9 AM" for a week that runs out; "Ran out Thu 10 PM" when it
    /// already has (this week or last). nil when nothing is locked.
    public static func chartTip(_ chart: LeftChart, now: Date, formatting: Formatting) -> ChartTip? {
        guard let from = chart.lockedFrom else { return nil }
        let out = chart.start.addingTimeInterval(from * Pace.window)
        let ahead = chart.now != nil && chart.forecastEnd != nil && out > now
        let hours = Int((max(chart.reset.timeIntervalSince(out), 0) / 3600).rounded())
        return ChartTip(title: (ahead ? "Empty " : "Ran out ") + formatting.dayTime(out, now: now),
                        detail: "Locked \(hours) h until \(formatting.dayTime(chart.reset, now: now))")
    }

    /// One of the busiest hours: the start hour on 24 hours ("16"), its range and its use.
    public struct BusiestRow: Equatable, Sendable {
        public var hour: String
        public var range: String
        public var used: String

        public init(hour: String, range: String, used: String) {
            self.hour = hour
            self.range = range
            self.used = used
        }
    }

    public static func busiestRows(_ hours: [HourUse], formatting: Formatting,
                                   calendar: Calendar = .autoupdatingCurrent) -> [BusiestRow] {
        hours.map { hour in
            BusiestRow(hour: String(format: "%02d", calendar.component(.hour, from: hour.start)),
                       range: hourRange(hour.start, formatting: formatting),
                       used: String(format: "%.1f%%", hour.used))
        }
    }
}
