import Foundation

/// The week as seven segments, clockwise from the window's start (the reset) at the top. A plan's
/// days are its own: day `i` is `[start + i·24h, start + (i+1)·24h)`, not a calendar day.
public struct WeekPie: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        /// A day that's over.
        case used(heaviness: Double)
        /// A day that's over before Tidemark's first reading of this week: nothing is known about it.
        case unseen
        /// Elapsed 0...1 of the day gone.
        case today(elapsed: Double, heaviness: Double)
        case ahead
        /// A day ahead that runs out: ahead, then locked from `at` (0...1) to the day's end.
        case runsOut(at: Double)
        /// Today, when the forecast runs out today: used to `elapsed`, ahead until `at`, locked after.
        case todayRunsOut(elapsed: Double, at: Double, heaviness: Double)
        /// A whole day after the run-out, before the reset.
        case locked
        /// A past or current day it ran out in: used to `at`, locked after.
        case ranOut(at: Double, heaviness: Double)
    }

    public struct Point: Equatable, Sendable {
        public var day: Int
        public var fraction: Double

        public init(day: Int, fraction: Double) {
            self.day = day
            self.fraction = fraction
        }
    }

    /// Always 7.
    public var segments: [Segment]
    public var now: Point
    /// The red dot: the forecast run-out, or when it ran out.
    public var runsOut: Point?
    /// The centre number, as the ring shows it today.
    public var used: Int

    /// A day's use as a share of an even day (100 / 7 %).
    static func heaviness(_ use: Double) -> Double { min(1, max(use, 0) / (100.0 / 7)) }

    /// nil without an open week.
    public static func make(reading: Reading, history: [Reading], now: Date) -> WeekPie? {
        guard let reset = reading.weekResetsAt, reset > now,
              let window = WeekWindow(reading: reading, history: history, until: now) else { return nil }
        let today = window.dayPoint(now)

        func heaviness(_ day: Int) -> Double {
            let from = window.start.addingTimeInterval(Double(day) * WeekWindow.day)
            let to = min(from.addingTimeInterval(WeekWindow.day), max(now, from))
            return Self.heaviness(window.value(at: to) - window.value(at: from))
        }

        var runsOut: Point?
        var segments: [Segment]
        if reading.week >= 100 {
            let moment = window.reachedFull ?? reading.time
            let out = window.dayPoint(min(moment, now))
            runsOut = Point(day: out.day, fraction: out.fraction)
            segments = (0..<7).map { i in
                if i < out.day { return .used(heaviness: heaviness(i)) }
                if i == out.day { return .ranOut(at: out.fraction, heaviness: heaviness(i)) }
                return .locked
            }
        } else if let out = Pace.forecast(reading, history: history, now: now)?.runsOutAt, out < reset {
            let spot = window.dayPoint(out)
            let day = max(spot.day, today.day)
            runsOut = Point(day: day, fraction: day == spot.day ? spot.fraction : 0)
            segments = (0..<7).map { i in
                if i < today.day { return .used(heaviness: heaviness(i)) }
                if i < day { return i == today.day ? .today(elapsed: today.fraction, heaviness: heaviness(i)) : .ahead }
                if i == day {
                    guard i == today.day else { return .runsOut(at: runsOut!.fraction) }
                    // Today's own use so far stays bold; the rest of the way to the run-out is still ahead.
                    return .todayRunsOut(elapsed: today.fraction, at: max(runsOut!.fraction, today.fraction), heaviness: heaviness(i))
                }
                return .locked
            }
        } else {
            segments = (0..<7).map { i in
                if i < today.day { return .used(heaviness: heaviness(i)) }
                if i == today.day { return .today(elapsed: today.fraction, heaviness: heaviness(i)) }
                return .ahead
            }
        }
        // Days before the first reading of this week (more than an hour into it) are not guessed at.
        if let first = window.points.first?.time {
            let since = first.timeIntervalSince(window.start)
            let unseen = since < 3600 ? 0 : min(Int(since / WeekWindow.day), 6)
            for i in 0..<unseen { if case .used = segments[i] { segments[i] = .unseen } }
        }
        return WeekPie(segments: segments, now: Point(day: today.day, fraction: today.fraction),
                       runsOut: runsOut, used: Int(reading.week.rounded()))
    }
}
