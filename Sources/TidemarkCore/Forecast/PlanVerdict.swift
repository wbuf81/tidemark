import Foundation

/// What a plan says about itself under the forecast pie: one full line, two short ones for a small
/// pie, and the two extra lines the details card adds when the week runs out early.
public struct PlanVerdict: Equatable, Sendable {
    public var state: PlanState
    /// Full width.
    public var line: String
    /// Two short lines beside a small pie.
    public var short: [String]
    /// "34 h until empty, if the pace holds"
    public var untilEmpty: String?
    /// "Locked 59 h, back Sun 9 AM"
    public var locked: String?

    /// Why a red plan is red, said by the numbers: the week or the 5-hour window, and whether it is really full
    /// or only nearly (red starts below `redWeekLeft` % left and at `redSession` % used).
    public enum OutKind: Equatable, Sendable {
        case weekFull, sessionFull, weekNearly, sessionNearly

        public var isWeek: Bool { self == .weekFull || self == .weekNearly }
        /// Really out, not only nearly.
        public var isFull: Bool { self == .weekFull || self == .sessionFull }
        /// Most urgent first.
        var rank: Int {
            switch self {
            case .weekFull: 3
            case .sessionFull: 2
            case .weekNearly: 1
            case .sessionNearly: 0
            }
        }
    }

    static func outKind(_ r: Reading, thresholds t: Thresholds) -> OutKind {
        if r.week >= 100 { return .weekFull }
        if r.session >= 100 { return .sessionFull }
        if r.weekLeft < t.redWeekLeft { return .weekNearly }
        return .sessionNearly
    }

    /// What a red plan is red for, and when its window is back.
    static func outUntil(_ r: Reading, thresholds t: Thresholds) -> (kind: OutKind, back: Date?) {
        let kind = outKind(r, thresholds: t)
        return (kind, kind.isWeek ? r.weekResetsAt : r.sessionResetsAt)
    }

    public static func make(reading r: Reading, forecast: WeekForecast?, state: PlanState, now: Date,
                            formatting: Formatting, thresholds: Thresholds = Thresholds()) -> PlanVerdict {
        func time(_ date: Date) -> String { formatting.dayTime(date, now: now) }
        func verdict(_ line: String, _ short: [String]) -> PlanVerdict {
            PlanVerdict(state: state, line: line, short: short)
        }
        guard let reset = r.weekResetsAt else { return verdict("Not started", ["Not", "started"]) }

        var result: PlanVerdict
        switch state {
        case .out:
            // The words follow the numbers: "out" only when the window is full, else "nearly".
            let (kind, back) = outUntil(r, thresholds: thresholds)
            switch kind {
            case .weekFull:
                result = back.map { verdict("Out until \(time($0))", ["Out", time($0)]) } ?? verdict("Out", ["Out"])
            case .sessionFull:
                result = back.map { verdict("5 hours out until \(time($0))", ["5h out", time($0)]) } ?? verdict("5 hours out", ["5h", "out"])
            case .weekNearly:
                let left = "\(max(Int(r.weekLeft.rounded()), 1))% left"
                result = verdict("Nearly out · \(left)", ["Nearly out", left])
            case .sessionNearly:
                result = verdict("5 hours nearly used", ["5h", "nearly used"])
            }
        case .runsOutEarly:
            if let out = forecast?.runsOutAt, forecast?.runsOutEarlyByHours != nil {
                // An old reading's forecast can already be over: say so, not a time in the past.
                result = out > now ? verdict("Runs out \(time(out))", ["Empty", time(out)])
                                   : verdict("Ran out about \(time(out)), if the pace held", ["Ran out", "about \(time(out))"])
            } else {
                result = verdict("5 hours nearly used", ["5h", "nearly used"])
            }
        case .fine:
            if forecast?.settling == true {
                let left = "\(Formatting.percent(r.weekLeft)) left"
                result = verdict("New week · \(left)", ["New week", left])
            } else if let unused = forecast?.unused, unused >= thresholds.onPaceUnused {
                let percent = "~\(Formatting.percent(unused))"
                result = verdict("\(percent) left at reset", [percent, "spare"])
            } else {
                result = verdict("On pace to use it all", ["On", "pace"])
            }
        }

        if state != .out, let out = forecast?.runsOutAt, forecast?.runsOutEarlyByHours != nil, out > now {
            let seconds = out.timeIntervalSince(now)
            result.untilEmpty = seconds < 3600
                ? "\(max(Int((seconds / 60).rounded()), 1)) min until empty, if the pace holds"
                : "\(Int((seconds / 3600).rounded())) h until empty, if the pace holds"
            let hours = Int((max(reset.timeIntervalSince(out), 0) / 3600).rounded())
            result.locked = "Locked \(hours) h, back \(time(reset))"
        }
        return result
    }
}
