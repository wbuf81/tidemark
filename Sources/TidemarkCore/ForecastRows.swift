import Foundation

/// One limit of one plan, as the headline and the detail's picker need it: its use, its window and
/// forecast. `isStale` is a reading older than `Reading.freshFor` (or none at all, with `since` nil).
public struct ForecastRow: Equatable, Sendable, Identifiable {
    public var id: LimitID
    var used: Double
    public var resetsAt: Date?
    var forecast: WeekForecast?
    /// Now when the limit is already used up, else when the forecast runs out; nil when it lasts.
    var runsOutAt: Date?
    public var isStale: Bool
    /// When the stale reading was taken; nil if the plan was never read.
    var since: Date?

    init(id: LimitID, used: Double, resetsAt: Date? = nil, forecast: WeekForecast? = nil,
         runsOutAt: Date? = nil, isStale: Bool = false, since: Date? = nil) {
        self.id = id
        self.used = used
        self.resetsAt = resetsAt
        self.forecast = forecast
        self.runsOutAt = runsOutAt
        self.isStale = isStale
        self.since = since
    }

    /// Hours from running out to the reset; nil when it lasts.
    var lockedHours: Double? {
        guard let out = runsOutAt, let reset = resetsAt else { return nil }
        return reset.timeIntervalSince(out) / 3600
    }
}

/// What fills a stretch of a plan's day bars.
enum DayFill: Equatable, Sendable {
    /// The running total by the end of the stretch, from the readings (%).
    case actual(Double)
    /// The forecast's total by the end of the stretch (%).
    case forecast(Double)
    /// Used up, waiting for the reset.
    case locked
    /// After the upcoming reset: a new window, not forecast.
    case nextWindow
    /// No reading covers this stretch.
    case noData
}

/// One day of a plan's week window on the Usage pane's row: the running total at the end of the day.
public struct DayBar: Equatable, Sendable {
    public var date: Date
    /// % used by the end of the day; nil when nothing was measured (before the first reading) or the
    /// day belongs to the plan's next window.
    public var value: Double?
    /// Forecast, not measured: drawn as an outline.
    public var isForecast: Bool
    public var isToday: Bool
}

/// Works out the limits' rows and the Usage pane's day bars.
public enum ForecastRows {
    /// The rows for `orgs` (ids, in display order): each org's week, its model limits by name,
    /// then its 5-hour window. An org never read gets one stale Week row.
    public static func make(orgs: [String], latest: [String: Reading], history: [Reading],
                            now: Date, calendar: Calendar = .autoupdatingCurrent) -> [ForecastRow] {
        orgs.flatMap { org -> [ForecastRow] in
            guard let raw = latest[org] else {
                return [ForecastRow(id: LimitID(org: org, kind: .week), used: 0, isStale: true)]
            }
            let reading = raw.adjusted(to: now)
            // The latest reading belongs on the row even before it reaches the history.
            let readings = history.contains(raw) ? history : history + [raw]
            return Limits.kinds(of: reading).compactMap { kind in
                row(LimitID(org: org, kind: kind), reading: reading, readings: readings, fresh: raw.isFresh(now: now),
                    now: now, calendar: calendar)
            }
        }
    }

    /// A plan's seven day bars: the seven 24-hour days of its current week window (from its start to its
    /// reset), oldest first. Past days come from the readings (nothing before the first one), today is
    /// the reading so far, later days are the forecast (100 once it would be out). Empty when the plan
    /// was never read or its week hasn't started.
    public static func dayBars(org: String, latest: [String: Reading], history: [Reading],
                               now: Date, calendar: Calendar = .autoupdatingCurrent) -> [DayBar] {
        guard let raw = latest[org] else { return [] }
        let reading = raw.adjusted(to: now)
        let readings = history.contains(raw) ? history : history + [raw]
        let id = LimitID(org: org, kind: .week)
        guard let state = Limits.state(id, reading: reading, history: readings, now: now),
              let reset = state.resetsAt else { return [] }
        let forecast = Limits.forecast(state, now: now, calendar: calendar)
        let runsOutAt = state.used >= 100 ? now : forecast?.runsOutAt
        let series = Limits.series(id, history: readings)
        let start = reset.addingTimeInterval(-Limits.weekWindow)
        return (0..<7).map { index in
            let from = start.addingTimeInterval(Double(index) * 86400)
            let to = from.addingTimeInterval(86400)
            if now >= from && now < to {
                return DayBar(date: from, value: state.used, isForecast: false, isToday: true)
            }
            switch fill(from: from, to: to, series, state, forecast, runsOutAt, now, at: min(now, raw.time)) {
            case .actual(let v): return DayBar(date: from, value: v, isForecast: false, isToday: false)
            case .forecast(let v): return DayBar(date: from, value: v, isForecast: true, isToday: false)
            case .locked: return DayBar(date: from, value: 100, isForecast: to > now, isToday: false)
            case .nextWindow, .noData: return DayBar(date: from, value: nil, isForecast: to > now, isToday: false)
            }
        }
    }

    /// One org's week row, even when its reading has gone stale (the widget draws the last known
    /// week); nil when the org was never read.
    public static func weekRow(org: String, latest: [String: Reading], history: [Reading],
                               now: Date, calendar: Calendar = .autoupdatingCurrent) -> ForecastRow? {
        guard let raw = latest[org] else { return nil }
        let reading = raw.adjusted(to: now)
        let readings = history.contains(raw) ? history : history + [raw]
        return row(LimitID(org: org, kind: .week), reading: reading, readings: readings, fresh: true, now: now, calendar: calendar)
    }

    static func row(_ id: LimitID, reading: Reading, readings: [Reading], fresh: Bool,
                    now: Date, calendar: Calendar) -> ForecastRow? {
        guard let state = Limits.state(id, reading: reading, history: readings, now: now) else { return nil }
        let forecast = Limits.forecast(state, now: now, calendar: calendar)
        let runsOutAt = state.resetsAt == nil ? nil : state.used >= 100 ? now : forecast?.runsOutAt
        return ForecastRow(id: id, used: state.used, resetsAt: state.resetsAt, forecast: forecast, runsOutAt: runsOutAt,
                           isStale: !fresh, since: fresh ? nil : reading.time)
    }

    /// What fills the stretch from `x` to `y`: the readings before now, the forecast after (counted from
    /// `at`, the reading's own time, so an old reading's paler bars don't drift).
    static func fill(from x: Date, to y: Date, _ series: [SeriesPoint], _ current: LimitState,
                     _ forecast: WeekForecast?, _ runsOutAt: Date?, _ now: Date, at: Date? = nil) -> DayFill {
        if y <= now {
            guard let used = used(at: y.addingTimeInterval(-1), series) else { return .noData }
            return used >= 100 ? .locked : .actual(used)
        }
        guard let reset = current.resetsAt else { return .noData }
        if x >= reset { return .nextWindow }
        if let out = runsOutAt, x >= out { return .locked }
        let end = min(y, reset)
        return .forecast(min(100, current.used + (forecast?.pacePerHour ?? 0) * max(end.timeIntervalSince(at ?? now), 0) / 3600))
    }

    /// The running total at `t` from the readings: the newest reading at or before `t`, or 0 if
    /// that reading's window had reset by `t`; nil before the first reading.
    static func used(at t: Date, _ series: [SeriesPoint]) -> Double? {
        guard let r = series.last(where: { $0.time <= t }) else { return nil }
        if let reset = r.resetsAt, reset <= t { return 0 }
        return r.value
    }
}
