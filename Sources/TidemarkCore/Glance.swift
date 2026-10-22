import Foundation

/// How a limit is doing, for its bar's colour: green has room, amber will fill or run out
/// before it resets (or is past the yellow line), red is full or nearly out. None has no open
/// window (nothing used yet: an empty bar, not a missing one). Ordered by urgency.
public enum GlanceTone: Int, Comparable, Sendable {
    case none, green, amber, red

    public static func < (a: GlanceTone, b: GlanceTone) -> Bool { a.rawValue < b.rawValue }
}

/// What the widget says beside a limit's bar.
enum GlanceNote: Equatable, Sendable {
    /// No open window: nothing used yet ("not started", a real 0%).
    case notStarted
    /// When it resets.
    case resets(Date)
    /// When the 5-hour window fills at this pace, before it resets.
    case fullAt(Date)
    /// Full now; when it comes back.
    case backAt(Date)
    /// When the week runs out at this pace, before it resets.
    case runsOut(Date)
    /// Under the red threshold: this much of the week is left, until this reset.
    case nearlyOut(left: Double, resets: Date)
    /// On track, but this much would go unused by the reset.
    case unused(Double, resets: Date)
}

/// One limit at a glance: how much is used, how far through its window it is (the tick),
/// its tone and its note.
public struct GlanceLimit: Equatable, Sendable {
    var kind: LimitKind
    /// 0 without an open window: nothing used yet is a real number, not a dash.
    public var used: Double?
    /// 0...1 through the window; nil without one.
    public var elapsed: Double?
    public var tone: GlanceTone
    var note: GlanceNote

    init(kind: LimitKind, used: Double?, elapsed: Double?, tone: GlanceTone, note: GlanceNote) {
        self.kind = kind
        self.used = used
        self.elapsed = elapsed
        self.tone = tone
        self.note = note
    }

    /// How many cells its bar is cut into: one per hour of the 5-hour window, one per day of the week.
    public var cells: Int { kind == .session ? 5 : 7 }

    /// How much of cell `index` (0 = first) is filled, 0...1: the fill runs on across the cells.
    public func cellFill(_ index: Int) -> Double {
        guard let used else { return 0 }
        return min(max(min(max(used, 0), 100) / 100 * Double(cells) - Double(index), 0), 1)
    }

    /// Full, or running out before it resets: the medium widget shows the note instead of the bar.
    public var isUrgent: Bool {
        switch note {
        case .backAt, .runsOut, .nearlyOut: true
        case .notStarted, .resets, .fullAt, .unused: false
        }
    }
}

/// An org's 5-hour window and week at a glance.
public struct Glance: Equatable, Sendable {
    public var session: GlanceLimit
    public var week: GlanceLimit

    /// The one to mention when there's room for one note: a 5-hour window that's amber or red
    /// and more urgent than the week; otherwise the week.
    public var mostUrgent: GlanceLimit { session.tone >= .amber && session.tone > week.tone ? session : week }

    public static func make(_ reading: Reading, history: [Reading], now: Date, thresholds t: Thresholds = Thresholds()) -> Glance {
        let r = reading.adjusted(to: now)
        return Glance(session: session(r, history: history, now: now, t), week: week(r, history: history, now: now, t))
    }

    private static func elapsed(resetsAt reset: Date, window: TimeInterval, now: Date) -> Double {
        min(max(1 - reset.timeIntervalSince(now) / window, 0), 1)
    }

    private static func session(_ r: Reading, history: [Reading], now: Date, _ t: Thresholds) -> GlanceLimit {
        guard let reset = r.sessionResetsAt else {
            return GlanceLimit(kind: .session, used: 0, elapsed: nil, tone: .none, note: .notStarted)
        }
        let gone = elapsed(resetsAt: reset, window: Limits.sessionWindow, now: now)
        func limit(_ tone: GlanceTone, _ note: GlanceNote) -> GlanceLimit {
            GlanceLimit(kind: .session, used: r.session, elapsed: gone, tone: tone, note: note)
        }
        if r.session >= 100 { return limit(.red, .backAt(reset)) }
        let hot: GlanceTone = r.session >= t.redSession ? .red : .amber
        if let state = Limits.state(LimitID(org: r.org, kind: .session), reading: r, history: history, now: now),
           let fullAt = Limits.forecast(state, now: now)?.runsOutAt {
            return limit(hot, .fullAt(fullAt))
        }
        if r.session >= t.yellowSession { return limit(hot, .resets(reset)) }
        return limit(.green, .resets(reset))
    }

    private static func week(_ r: Reading, history: [Reading], now: Date, _ t: Thresholds) -> GlanceLimit {
        guard let reset = r.weekResetsAt else {
            return GlanceLimit(kind: .week, used: 0, elapsed: nil, tone: .none, note: .notStarted)
        }
        let gone = elapsed(resetsAt: reset, window: Limits.weekWindow, now: now)
        func limit(_ tone: GlanceTone, _ note: GlanceNote) -> GlanceLimit {
            GlanceLimit(kind: .week, used: r.week, elapsed: gone, tone: tone, note: note)
        }
        if r.week >= 100 { return limit(.red, .backAt(reset)) }
        let forecast = Pace.forecast(r, history: history, now: now)
        if r.weekLeft < t.redWeekLeft { return limit(.red, .nearlyOut(left: r.weekLeft, resets: reset)) }
        if let out = forecast?.runsOutAt, forecast?.runsOutEarlyByHours != nil { return limit(.amber, .runsOut(out)) }
        if let unused = forecast?.unused, unused >= t.onPaceUnused { return limit(.green, .unused(unused, resets: reset)) }
        return limit(.green, .resets(reset))
    }
}
