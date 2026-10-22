import Foundation

/// What a plan's colour and shape say (D6): fine (green circle), runs out before it resets
/// (amber triangle), or out (red square). "Would go unused" is said in words, never as a state.
public enum PlanState: Equatable, Sendable {
    case fine, runsOutEarly, out
}

public enum PlanStates {
    /// First match wins: out, then runs out early, then fine.
    public static func state(_ r: Reading, _ f: WeekForecast?, _ t: Thresholds = Thresholds()) -> PlanState {
        if r.weekLeft < t.redWeekLeft || r.session >= t.redSession { return .out }
        if f?.runsOutEarlyByHours != nil || r.session >= t.yellowSession { return .runsOutEarly }
        return .fine
    }

    /// How the plan stands by its week alone, ignoring the 5-hour window: what a menu bar battery
    /// (which shows the week) colours by. `.out` means red (under `redWeekLeft` % left).
    public static func weekState(_ r: Reading, _ f: WeekForecast?, _ t: Thresholds = Thresholds()) -> PlanState {
        if r.weekLeft < t.redWeekLeft { return .out }
        return f?.runsOutEarlyByHours != nil ? .runsOutEarly : .fine
    }
}
