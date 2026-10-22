import Foundation

/// A point on a week chart: x is the share of the limit's window (0...1), y is % used / 100.
public struct ChartPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A tick on the detail chart's time axis: a local noon (week windows) or a whole hour
/// (5-hour windows).
public struct AxisTick: Equatable, Sendable {
    public var date: Date
    public var x: Double
}

/// A bar under the detail chart: a day's use, or a 5-hour window's peak.
public struct DetailBar: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        /// Within 25% of the use-it-all pace a day.
        case onPace
        /// Below it: heading for some going unused.
        case under
        /// Above it: heading for running out.
        case over
        /// Today, still going.
        case today
        /// A window or model limit that reached 100%.
        case hitLimit
        /// A 5-hour window that didn't.
        case plain
        /// A model limit's day: a cap to stay under, not something to use up.
        case withinLimit
        /// The 5-hour window still open now.
        case openWindow
        /// A day before the first reading: nothing was measured, so nothing is drawn.
        case noData
    }

    /// The local day (daily bars) or the window's start (5-hour windows).
    public var date: Date
    /// nil when nothing was measured that day (before the first reading).
    public var value: Double?
    public var tone: Tone
    /// How many days of use the bar holds: more than one when nothing was read on the days before it, so
    /// the whole rise since the last reading lands on this day (no verdict is drawn for it).
    public var includesDays = 1
}

/// Everything the detail pane draws for one limit, in unit coordinates (x 0...1 across the
/// limit's window, y = % used / 100), so the view only scales and strokes.
public struct LimitDetail: Equatable, Sendable {
    public var id: LimitID
    var windowStart: Date
    var resetsAt: Date
    public var used: Double
    var elapsedFraction: Double
    var forecast: WeekForecast?
    /// Now when used up, else the forecast's run-out time; nil when it lasts.
    public var runsOutAt: Date?
    /// From 0% at the window's start through this window's readings to now.
    public var usedLine: [ChartPoint]
    public var nowX: Double
    /// From now to 100% at the reset.
    public var useItAll: [ChartPoint]
    /// From now at the forecast pace: to the reset, or to 100% and then flat.
    public var yourPace: [ChartPoint]
    public var runsOut: ChartPoint?
    /// Locked from here to the reset.
    public var lockedFromX: Double?
    /// The "would go unused" wedge; empty unless the threshold's worth would.
    public var unused: [ChartPoint]
    public var ticks: [AxisTick]
    /// Seven days of use (week and model limits) or recent 5-hour windows.
    public var bars: [DetailBar]
    /// The use-it-all pace a day the daily bars are measured against; nil for 5-hour windows.
    public var perDayLine: Double?

    /// The forecast pace over the use-it-all pace; nil when nothing is left.
    var paceMultiple: Double? {
        guard let f = forecast, f.useItAllPerHour > 0 else { return nil }
        return f.pacePerHour / f.useItAllPerHour
    }
}

/// Works out the detail pane.
public enum LimitDetails {
    /// The detail for one limit; nil when its window hasn't started. `reading` should already
    /// be adjusted to `now`.
    public static func make(_ id: LimitID, reading: Reading, history: [Reading], now: Date,
                            thresholds: Thresholds = Thresholds(), calendar: Calendar = .autoupdatingCurrent) -> LimitDetail? {
        guard let state = Limits.state(id, reading: reading, history: history, now: now),
              let reset = state.resetsAt else { return nil }
        let start = reset.addingTimeInterval(-state.window)
        func x(_ date: Date) -> Double { min(max(date.timeIntervalSince(start) / state.window, 0), 1) }
        let forecast = Limits.forecast(state, now: now, calendar: calendar)
        let out = state.used >= 100 ? now : forecast?.runsOutAt
        let nowPoint = ChartPoint(x: x(now), y: state.used / 100)

        var detail = LimitDetail(
            id: id, windowStart: start, resetsAt: reset, used: state.used, elapsedFraction: x(now),
            forecast: forecast, runsOutAt: out,
            usedLine: [ChartPoint(x: 0, y: 0)]
                + state.past.filter { $0.time > start }.map { ChartPoint(x: x($0.time), y: $0.value / 100) }
                + [nowPoint],
            nowX: x(now), useItAll: [], yourPace: [], runsOut: nil, lockedFromX: nil, unused: [],
            ticks: ticks(start: start, reset: reset, session: id.kind == .session, calendar: calendar).map { AxisTick(date: $0, x: x($0)) },
            bars: [], perDayLine: nil)

        if let f = forecast {
            detail.useItAll = [nowPoint, ChartPoint(x: 1, y: 1)]
            if let out {
                detail.yourPace = [nowPoint, ChartPoint(x: x(out), y: 1), ChartPoint(x: 1, y: 1)]
                detail.runsOut = ChartPoint(x: x(out), y: 1)
                detail.lockedFromX = x(out)
            } else {
                detail.yourPace = [nowPoint, ChartPoint(x: 1, y: f.forecastAtReset / 100)]
                if id.kind == .week, f.unused >= thresholds.onPaceUnused {
                    detail.unused = [nowPoint, ChartPoint(x: 1, y: f.forecastAtReset / 100), ChartPoint(x: 1, y: 1)]
                }
            }
        }

        let series = Limits.series(id, history: history)
        if id.kind == .session {
            detail.bars = recentWindows(series, now: now)
        } else {
            let line = forecast?.useItAllPerDay ?? 100.0 / 7
            // A model limit is a cap, not something to use up: no use-it-all pace for it (S3.4).
            let isModel = { if case .model = id.kind { true } else { false } }()
            if isModel {
                detail.useItAll = []
            } else {
                detail.perDayLine = line
            }
            let days = dailyRises(series, now: now, calendar: calendar)
            // Days before the first reading measured nothing: no bar, no tone (S3.1).
            let first = series.first.map { calendar.startOfDay(for: $0.time) }
            // A day with no reading measured nothing (the Mac slept): no bar, and the next day holds its use (M4).
            let read = Set(series.map { calendar.startOfDay(for: $0.time) })
            var quiet = 0
            detail.bars = days.enumerated().map { i, day in
                let isToday = i == days.count - 1
                if let first, day.day < first { return DetailBar(date: day.day, value: nil, tone: .noData) }
                if !read.contains(day.day), !isToday {
                    quiet += 1
                    return DetailBar(date: day.day, value: nil, tone: .noData)
                }
                defer { quiet = 0 }
                // After a gap the week's bar carries no verdict (over/under): it holds more than a day's use.
                let verdict = tone(day.value, line: line, today: isToday, kind: id.kind)
                var bar = DetailBar(date: day.day, value: day.value,
                                    tone: quiet > 0 && !isToday && id.kind == .week ? .plain : verdict)
                bar.includesDays = quiet + 1
                return bar
            }
        }
        return detail
    }

    /// What was used on each of the last seven local days (six before today, then today): the
    /// sum of rises between consecutive readings, each counted on the later reading's day. A
    /// reading in a new window counts its whole value, the use since that reset; a drop
    /// within a window counts nothing.
    static func dailyRises(_ series: [SeriesPoint], now: Date, calendar: Calendar) -> [(day: Date, value: Double)] {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).map { calendar.date(byAdding: .day, value: $0 - 6, to: today)! }
        var totals = Array(repeating: 0.0, count: days.count)
        for (prev, cur) in zip(series, series.dropFirst()) where cur.time >= days[0] && cur.time <= now {
            let rise = cur.resetsAt == prev.resetsAt ? max(cur.value - prev.value, 0) : cur.value
            if let i = days.lastIndex(where: { $0 <= cur.time }) { totals[i] += rise }
        }
        return Array(zip(days, totals)).map { (day: $0.0, value: $0.1) }
    }

    /// The last `count` 5-hour windows in `series`, oldest first: when each opened and its
    /// highest reading.
    static func recentWindows(_ series: [SeriesPoint], count: Int = 8, now: Date? = nil) -> [DetailBar] {
        var peaks: [Date: Double] = [:]
        for point in series {
            guard let reset = point.resetsAt else { continue }
            peaks[reset] = max(peaks[reset] ?? 0, point.value)
        }
        return peaks.keys.sorted().suffix(count).map { reset in
            let peak = peaks[reset]!
            let tone: DetailBar.Tone = peak >= 100 ? .hitLimit : (now.map { reset > $0 } ?? false) ? .openWindow : .plain
            return DetailBar(date: reset.addingTimeInterval(-Limits.sessionWindow), value: peak, tone: tone)
        }
    }

    /// A day's bar against the use-it-all pace a day: within 25% is on pace. A model limit is a
    /// cap, not something to use up, so it has no pace: within the limit, or at 100%.
    static func tone(_ value: Double, line: Double, today: Bool, kind: LimitKind) -> DetailBar.Tone {
        if today { return .today }
        if case .model = kind { return value >= 100 ? .hitLimit : .withinLimit }
        if value < line * 0.75 { return kind == .week ? .under : .onPace }
        return value > line * 1.25 ? .over : .onPace
    }

    /// Local noons inside a week window, or whole hours inside a 5-hour window.
    static func ticks(start: Date, reset: Date, session: Bool, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        if session {
            var t = calendar.dateInterval(of: .hour, for: start)!.end
            while t < reset {
                dates.append(t)
                t = t.addingTimeInterval(3600)
            }
        } else {
            var day = calendar.startOfDay(for: start)
            while day < reset {
                if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day), noon > start, noon < reset {
                    dates.append(noon)
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        return dates
    }
}
