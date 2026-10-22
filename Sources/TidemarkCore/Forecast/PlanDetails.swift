import CoreGraphics
import Foundation

/// Everything the details card shows for one plan, worked out once: the % left, the sentence and the
/// locked line, the pie, the week's chart, the pace, the 5-hour window and the busiest hours.
public struct PlanDetails: Equatable, Sendable {
    public struct FiveHour: Equatable, Sendable {
        /// % of the 5-hour window used.
        public var used: Int
        /// How far through the window we are, 0...100; nil when no window is open.
        public var now: Double?
        /// "resets 2:05 PM", or "not started".
        public var resets: String
    }

    public struct Hour: Equatable, Sendable {
        /// "Tue 4–5 PM"
        public var range: String
        /// "3.8%"
        public var used: String
    }

    public var state: PlanState
    /// % of the week left, whole.
    public var left: Int
    public var verdict: PlanVerdict
    /// Under the big number: "34 h until empty, if the pace holds" when it runs out, else the verdict's line.
    public var sentence: String
    /// "Locked 59 h, back Sun 9 AM" when the week runs out early, "Locked since Mon 6 PM" when it is full.
    public var locked: String?
    public var pie: WeekPie?
    public var chart: LeftChart?
    public var pace: PaceReading?
    public var fiveHour: FiveHour
    public var busiest: [Hour]
    /// False before there are two readings in the week: the card says "Not enough readings yet".
    public var hasHistory: Bool
    /// "As of 11:32 AM", for an old reading.
    public var asOf: String?

    /// `reading` should already be adjusted to `now` (`Reading.adjusted(to:)`).
    public static func make(reading r: Reading, history: [Reading], now: Date, formatting: Formatting,
                            thresholds: Thresholds = Thresholds(), isOld: Bool,
                            calendar: Calendar? = nil) -> PlanDetails {
        let forecast = Pace.forecast(r, history: history, now: now)
        let state = PlanStates.state(r, forecast, thresholds)
        let verdict = PlanVerdict.make(reading: r, forecast: forecast, state: state, now: now,
                                       formatting: formatting, thresholds: thresholds)
        let cal = calendar ?? formatting.calendar
        let pie = WeekPie.make(reading: r, history: history, now: now)
        let chart = LeftChart.make(reading: r, history: history, now: now, calendar: cal)
        let hasHistory = (WeekWindow(reading: r, history: history, until: now)?.points.count ?? 0) >= 2
        let hours = HourlyUse.measuredBusiest(reading: r, history: history, now: now, calendar: cal)
        let busiest = hours.map {
            Hour(range: UsageCopy.hourRange($0.start, formatting: formatting), used: String(format: "%.1f%%", $0.used))
        }
        // A full week has no pace to read; it says since when it has been locked.
        let weekOut = r.week >= 100
        let pace = weekOut ? nil : PaceReading.make(reading: r, now: now)
        var locked = verdict.locked
        if weekOut {
            let since = WeekWindow(reading: r, history: history, until: now)?.reachedFull ?? r.time
            locked = "Locked since \(formatting.dayTime(min(since, now), now: now))"
        }

        var five = FiveHour(used: Int(r.session.rounded()), now: nil, resets: "not started")
        if let end = r.sessionResetsAt, end > now {
            five.resets = "resets \(formatting.dayTime(end, now: now))"
            let window = 5 * 3600.0
            five.now = min(max((window - end.timeIntervalSince(now)) / window, 0), 1) * 100
        }

        let left = Int(max(0, 100 - r.week).rounded())
        let sentence = verdict.untilEmpty ?? verdict.line

        return PlanDetails(state: state, left: left, verdict: verdict, sentence: sentence, locked: locked,
                           pie: pie, chart: chart, pace: pace, fiveHour: five, busiest: busiest,
                           hasHistory: hasHistory, asOf: isOld ? UsageCopy.asOfLine(r.time, now: now, formatting: formatting) : nil)
    }
}

/// What the details card was opened from; each caller says, so the card lands where that thing wants it.
public enum DetailsAnchor: Equatable, Sendable {
    /// A slot in the widget bar: the card goes above it (or below, when the bar is in the upper half).
    case slot
    /// A slot in the widget's side strip: the card goes beside it, on the side with room.
    case stripSlot
    /// A battery in the menu bar: the card drops below it, under the menu bar.
    case menuBar
    /// The open notch: the card drops below it.
    case notch
}

/// Where the details card goes, from the frame of what was clicked (screen points, origin bottom left).
public enum DetailsPlacement {
    public static let width: CGFloat = 300
    /// Between the card and what it came from.
    public static let gap: CGFloat = 8
    /// Between the card and the screen's edge.
    public static let margin: CGFloat = 8

    /// Centred on `anchor`, then moved to keep the whole card on `screen` (the visible frame, so never over
    /// the menu bar), and made shorter if it would not fit. Where it goes follows `kind`: above a widget slot
    /// in the lower half of the screen (below one in the upper half), beside a strip slot, below a menu bar
    /// battery and below the notch.
    public static func frame(anchor: CGRect, from kind: DetailsAnchor, size: CGSize, screen: CGRect) -> CGRect {
        let room = screen.insetBy(dx: margin, dy: margin)
        let w = min(size.width, room.width), h = min(size.height, room.height)
        var x: CGFloat, y: CGFloat
        switch kind {
        case .stripSlot:
            x = anchor.midX < screen.midX ? anchor.maxX + gap : anchor.minX - gap - w
            y = anchor.midY - h / 2
        case .slot:
            x = anchor.midX - w / 2
            y = anchor.midY < screen.midY ? anchor.maxY + gap : anchor.minY - gap - h
        case .menuBar, .notch:
            x = anchor.midX - w / 2
            y = anchor.minY - gap - h
        }
        x = min(max(x, room.minX), room.maxX - w)
        y = min(max(y, room.minY), room.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
