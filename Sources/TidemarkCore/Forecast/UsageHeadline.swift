import Foundation

/// The Usage page's headline and the line under it, most urgent plan first.
public struct UsageHeadline: Equatable, Sendable {
    public var title: String
    public var detail: String

    public struct Plan: Sendable {
        public var name: String
        public var reading: Reading
        public var forecast: WeekForecast?
        public var state: PlanState

        public init(name: String, reading: Reading, forecast: WeekForecast?, state: PlanState) {
            self.name = name
            self.reading = reading
            self.forecast = forecast
            self.state = state
        }
    }

    /// "this morning", "tonight", "tomorrow afternoon", "Thursday night": morning 5 AM to noon, afternoon
    /// noon to 5 PM, evening 5 to 9 PM, night 9 PM to 5 AM. A night belongs to the day it began on, so
    /// 1 AM Thursday is Wednesday night.
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let part = hour >= 5 && hour < 12 ? "morning" : hour >= 12 && hour < 17 ? "afternoon" : hour >= 17 && hour < 21 ? "evening" : "night"
        let day = hour < 5 ? date.addingTimeInterval(-5 * 3600) : date
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        if days <= 0 { return part == "night" ? "tonight" : "this \(part)" }
        if days == 1 { return "tomorrow \(part)" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: day)) \(part)"
    }

    /// "Personal covers", "Personal and Work cover"; nil with no names.
    private static func covers(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) covers"
        default: return "\(names.dropLast().joined(separator: ", ")) and \(names.last!) cover"
        }
    }

    /// nil with no plans.
    public static func make(_ plans: [Plan], now: Date, formatting: Formatting,
                            thresholds: Thresholds = Thresholds(),
                            calendar: Calendar = .autoupdatingCurrent) -> UsageHeadline? {
        guard !plans.isEmpty else { return nil }
        func time(_ date: Date) -> String { formatting.dayTime(date, now: now) }
        func covering(_ plan: Plan) -> [String] {
            plans.filter { $0.state == .fine && $0.name != plan.name }.map(\.name)
        }

        // Red: really out before nearly out, then the one that stays out longest.
        let out = plans.filter { $0.state == .out }
            .map { (plan: $0, why: PlanVerdict.outUntil($0.reading, thresholds: thresholds)) }
            .max { a, b in
                a.why.kind.rank != b.why.kind.rank ? a.why.kind.rank < b.why.kind.rank
                    : (a.why.back ?? .distantFuture) < (b.why.back ?? .distantFuture)
            }
        if let out {
            let name = out.plan.name
            let back = out.why.back
            var parts: [String] = []
            let title: String
            switch out.why.kind {
            case .weekFull, .sessionFull:
                if let back { parts.append("Back \(time(back)).") }
                title = "\(name) is out" + (back.map { " until \(when($0, now: now, calendar: calendar))" } ?? "")
            case .weekNearly:
                let left = "\(max(Int(out.plan.reading.weekLeft.rounded()), 1))% left"
                parts.append(back.map { "\(left) until \(time($0))." } ?? "\(left).")
                title = "\(name) is nearly out"
            case .sessionNearly:
                if let back { parts.append("Back \(time(back)).") }
                title = "\(name) has nearly used its 5 hours"
            }
            if let covers = covers(covering(out.plan)) { parts.append("\(covers).") }
            return UsageHeadline(title: title, detail: parts.joined(separator: " "))
        }

        // Runs out early: the one that empties first.
        let early = plans.compactMap { plan -> (plan: Plan, out: Date)? in
            guard plan.state == .runsOutEarly, plan.forecast?.runsOutEarlyByHours != nil,
                  let out = plan.forecast?.runsOutAt else { return nil }
            return (plan, out)
        }.min { $0.out < $1.out }
        if let early {
            // An old reading's forecast can already be over.
            if early.out <= now {
                return UsageHeadline(title: "\(early.plan.name) may have run out",
                                     detail: "Empty about \(time(early.out)), if the pace held.")
            }
            var detail = "Empty \(time(early.out)), if the pace holds."
            if let covers = covers(covering(early.plan)) {
                let back = early.plan.reading.weekResetsAt.map { " until \(early.plan.name) is back \(time($0))" } ?? ""
                detail += " \(covers)\(back)."
            }
            return UsageHeadline(title: "\(early.plan.name) runs out \(when(early.out, now: now, calendar: calendar))", detail: detail)
        }

        // All fine: the plan with the least to spare, at its reset.
        let title = plans.count == 1 ? "\(plans[0].name) lasts the week" : "Every plan lasts the week"
        // A plan whose week just started has no spare to speak of yet.
        let least = plans.compactMap { plan -> (unused: Double, reset: Date)? in
            guard let f = plan.forecast, !f.settling, let reset = plan.reading.weekResetsAt else { return nil }
            return (f.unused, reset)
        }.min { $0.unused < $1.unused }
        guard let least else {
            let fresh = plans.contains { $0.forecast?.settling == true }
            return UsageHeadline(title: title, detail: fresh ? "A new week just started." : "")
        }
        let detail = least.unused >= thresholds.onPaceUnused
            ? "About \(Formatting.percent(least.unused)) to spare at \(time(least.reset))."
            : "On pace to use it all by \(time(least.reset))."
        return UsageHeadline(title: title, detail: detail)
    }
}
