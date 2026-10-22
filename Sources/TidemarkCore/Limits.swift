import Foundation

/// Which of an org's limits: its weekly limit, a model-specific weekly limit (e.g. "Fable"),
/// or its 5-hour window.
public enum LimitKind: Hashable, Sendable {
    case week
    case model(String)
    case session
}

/// One limit of one org: what a forecast row and the detail pane are about.
public struct LimitID: Hashable, Sendable {
    public var org: String
    public var kind: LimitKind

    public init(org: String, kind: LimitKind) {
        self.org = org
        self.kind = kind
    }
}

/// A limit's value at one reading.
struct LimitPoint: Equatable, Sendable {
    var time: Date
    var value: Double

    init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// A limit's value at one reading, with the reset its window had then, for sums that cross
/// windows (daily use, recent 5-hour windows).
struct SeriesPoint: Equatable, Sendable {
    var time: Date
    var value: Double
    var resetsAt: Date?

    init(time: Date, value: Double, resetsAt: Date?) {
        self.time = time
        self.value = value
        self.resetsAt = resetsAt
    }
}

/// A limit as it stands now: its use, its window, and this window's earlier readings.
struct LimitState: Equatable, Sendable {
    var id: LimitID
    var used: Double
    /// nil when the window hasn't started.
    var resetsAt: Date?
    var window: TimeInterval
    /// This window's readings before now, oldest first.
    var past: [LimitPoint]
    /// When `used` was read: forecasts count from here, so an old reading keeps its run-out time.
    var asOf: Date? = nil

    var windowStart: Date? { resetsAt?.addingTimeInterval(-window) }
}

/// Reads any limit out of readings, so the week, model limits and the 5-hour window can be
/// forecast and drawn the same way.
enum Limits {
    static let weekWindow: TimeInterval = Pace.window
    static let sessionWindow: TimeInterval = 5 * 3600

    /// The limits a reading reports, in row order: the week, model limits by name, the 5-hour window.
    static func kinds(of reading: Reading) -> [LimitKind] {
        [.week] + reading.scoped.keys.sorted().map { .model($0) } + [.session]
    }

    /// A limit's use and reset in one reading; nil when the reading doesn't report that limit.
    static func value(_ kind: LimitKind, in r: Reading) -> (used: Double, resetsAt: Date?)? {
        switch kind {
        case .week: return (r.week, r.weekResetsAt)
        case .model(let name): return r.scoped[name].map { ($0, r.resetsAt(scoped: name)) }
        case .session: return (r.session, r.sessionResetsAt)
        }
    }

    static func window(_ kind: LimitKind) -> TimeInterval { kind == .session ? sessionWindow : weekWindow }

    /// Weekly limits pace over the last 72 hours; the 5-hour window over the whole window so far.
    static func lookback(_ kind: LimitKind) -> TimeInterval { kind == .session ? sessionWindow : Pace.lookback }

    /// The limit now and this window's earlier readings. `reading` should already be adjusted
    /// to `now`. nil when the reading doesn't report the limit.
    static func state(_ id: LimitID, reading: Reading, history: [Reading], now: Date) -> LimitState? {
        guard let current = value(id.kind, in: reading) else { return nil }
        let reset = current.resetsAt
        let past: [LimitPoint] = reset == nil ? [] : history
            .filter { $0.org == id.org && $0.time < now }
            .compactMap { r -> LimitPoint? in
                guard let v = value(id.kind, in: r), v.resetsAt == reset else { return nil }
                return LimitPoint(time: r.time, value: v.used)
            }
            .sorted { $0.time < $1.time }
        return LimitState(id: id, used: current.used, resetsAt: reset, window: window(id.kind), past: past, asOf: reading.time)
    }

    /// The 5-hour window's forecast only counts once this much of it has gone (30 minutes): a first
    /// burst says nothing about the pace. One rule for the widget, the strip, the notch and Usage (H2).
    static let sessionForecastFrom = 0.1

    /// The limit's forecast; nil before its window starts, and for the 5-hour window in its first 30 minutes.
    static func forecast(_ state: LimitState, now: Date, calendar: Calendar = .autoupdatingCurrent) -> WeekForecast? {
        guard let reset = state.resetsAt else { return nil }
        let at = min(now, state.asOf ?? now)
        if state.id.kind == .session,
           at.timeIntervalSince(reset.addingTimeInterval(-state.window)) < sessionForecastFrom * state.window { return nil }
        return Pace.forecast(used: state.used, resetsAt: reset, window: state.window, lookback: lookback(state.id.kind),
                             past: state.past, now: at, calendar: calendar)
    }

    /// Every reading of a limit in `history`, oldest first, whatever its window.
    static func series(_ id: LimitID, history: [Reading]) -> [SeriesPoint] {
        history.filter { $0.org == id.org }
            .compactMap { r in value(id.kind, in: r).map { SeriesPoint(time: r.time, value: $0.used, resetsAt: $0.resetsAt) } }
            .sorted { $0.time < $1.time }
    }
}
