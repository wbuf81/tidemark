import Foundation

/// The sentences the widget and Insights show, kept here so they can be tested.
public enum Copy {
    public struct Today: Equatable, Sendable {
        public var main: String
        public var warning: String?
        /// The warning says the week runs out before it resets (amber); otherwise it only says how
        /// much would go unused, in words and a neutral ink (D6).
        public var warningRunsOut = false
    }

    /// The note beside the 5-hour bar: "↺ 2:20pm", "full 2:50pm", "back 3pm", "not started". The
    /// week's lowercase day form ("↺ fri", "out thu") is still here for the strip's bars.
    public static func glanceNote(_ limit: GlanceLimit, now: Date, formatting: Formatting, capitalized: Bool) -> String {
        func day(_ date: Date) -> String {
            let name = formatting.weekday(date)
            return capitalized ? name : name.lowercased()
        }
        let session = limit.kind == .session
        switch limit.note {
        case .notStarted: return session ? "not started" : "week not started"
        case .resets(let date): return "↺ " + (session ? formatting.shortTime(date) : day(date))
        case .fullAt(let date): return "full " + formatting.shortTime(date)
        case .backAt(let date): return "back " + (session ? formatting.shortTime(date) : day(date))
        case .runsOut(let date):
            return "out " + (formatting.calendar.isDate(date, inSameDayAs: now) ? formatting.shortTime(date) : day(date))
        case .nearlyOut(let left, _): return "nearly out · \(Formatting.percent(left)) left"
        case .unused(let unused, _): return "~\(Formatting.percent(unused)) unused"
        }
    }

    /// The words under the plan's name, in two parts so the first can be bold: "~20%" and
    /// "would go unused · Fri 4 AM", "runs out" and "Sat 2 PM", "out" and "until Mon 9 AM", "nearly out"
    /// and "· 6% left". `lead` is empty when there is nothing to stress.
    public struct WeekNote: Equatable, Sendable {
        public var lead: String
        public var rest: String

        /// The whole note on one line.
        public var text: String { lead.isEmpty ? rest : "\(lead) \(rest)" }

        /// About how wide the note is at `fontSize`, in points: a width to plan with and to test the fallbacks
        /// against (the widget itself lets the layout measure the real text).
        public func estimatedWidth(fontSize: Double = 11) -> Double { Double(text.count) * fontSize * 0.55 }
    }

    /// What the plan's week says about itself (S1.5, B19). With `asOf` (an old reading) it says so:
    /// a calm note gives way to "as of 10:42 AM", an urgent one keeps its words and adds it.
    public static func weekNote(_ limit: GlanceLimit, asOf: Date? = nil, now: Date, formatting: Formatting) -> WeekNote {
        weekNoteForms(limit, asOf: asOf, now: now, formatting: formatting)[0]
    }

    /// The same note in every length it can take, longest first (H1). Each shorter form keeps the
    /// meaning and the time ("runs out Sat", "~20% unused", "out until Mon", "resets Fri"): the widget
    /// picks the longest that fits and never falls back to the bold lead alone ("~20%", "runs out").
    public static func weekNoteForms(_ limit: GlanceLimit, asOf: Date? = nil, now: Date, formatting: Formatting) -> [WeekNote] {
        func time(_ date: Date) -> String { formatting.dayTime(date, now: now) }
        /// The day without the clock: "Sat", "Fri 23 Oct", or the time itself when it is today.
        func day(_ date: Date) -> String { formatting.day(date, now: now) }
        var forms: [WeekNote]
        switch limit.note {
        case .notStarted:
            forms = [WeekNote(lead: "0%", rest: "week not started"), WeekNote(lead: "", rest: "week not started"),
                     WeekNote(lead: "", rest: "not started")]
        case .backAt(let date):
            forms = [WeekNote(lead: "out", rest: "until \(time(date))"), WeekNote(lead: "out", rest: "until \(day(date))")]
        case .nearlyOut(let left, _):
            let percent = Formatting.percent(left)
            forms = [WeekNote(lead: "nearly out", rest: "· \(percent) left"), WeekNote(lead: "", rest: "\(percent) left")]
        case .runsOut(let date):
            forms = [WeekNote(lead: "runs out", rest: time(date)), WeekNote(lead: "runs out", rest: day(date))]
        case .unused(let unused, let reset):
            let percent = "~\(Formatting.percent(unused))"
            forms = [WeekNote(lead: percent, rest: "would go unused · \(time(reset))"),
                     WeekNote(lead: percent, rest: "would go unused"), WeekNote(lead: percent, rest: "unused")]
        case .resets(let date):
            forms = [WeekNote(lead: "", rest: "resets \(time(date))"), WeekNote(lead: "", rest: "resets \(day(date))")]
        case .fullAt(let date):
            forms = [WeekNote(lead: "full", rest: time(date))]
        }
        if let asOf {
            let at = time(asOf)
            switch limit.note {
            case .runsOut, .backAt, .nearlyOut:
                for i in forms.indices { forms[i].rest += " · as of \(at)" }
            default: forms = [WeekNote(lead: "as of", rest: at)]
            }
        }
        return forms
    }

    /// The longest form of the note that fits `width` points; the shortest when none does (it truncates at
    /// its end, so its words stay first).
    public static func fitting(_ forms: [WeekNote], width: Double, fontSize: Double = 11) -> WeekNote {
        forms.first { $0.estimatedWidth(fontSize: fontSize) <= width } ?? forms[forms.count - 1]
    }

    /// One plan in the widget as a sentence, for VoiceOver and the tooltip: "Personal: week 58 percent
    /// used, about 20 percent would go unused, resets Friday 4 AM; 5-hour window 34 percent, resets
    /// 4:20 PM", and ", reading from 10:42 AM" when the reading is old.
    public static func widgetSummary(_ name: String, glance: Glance?, readAt: Date? = nil, now: Date,
                                     formatting: Formatting) -> String {
        guard let glance else { return "\(name): no reading yet." }
        func percent(_ value: Double) -> String { "\(Int(value.rounded())) percent" }
        func time(_ date: Date) -> String { formatting.spoken(date, now: now) }
        let week = glance.week, session = glance.session
        var weekPart = "week \(percent(week.used ?? 0)) used"
        switch week.note {
        case .notStarted: weekPart = "week not started"
        case .unused(let unused, let reset): weekPart += ", about \(percent(unused)) would go unused, resets \(time(reset))"
        case .runsOut(let date): weekPart += ", runs out \(time(date))"
        case .backAt(let date): weekPart += ", out until \(time(date))"
        case .nearlyOut(let left, let reset): weekPart += ", nearly out, \(percent(left)) left, resets \(time(reset))"
        case .resets(let date): weekPart += ", resets \(time(date))"
        case .fullAt: break
        }
        let sessionPart: String
        switch session.note {
        case .notStarted: sessionPart = "5-hour window not started"
        case .backAt(let date): sessionPart = "5-hour window full, back at \(time(date))"
        case .fullAt(let date): sessionPart = "5-hour window \(percent(session.used ?? 0)), full around \(time(date))"
        case .resets(let date):
            // Say why the plan is amber or red when the 5-hour window is the cause (L13).
            let close = session.tone == .red ? ", nearly full" : session.tone == .amber ? ", close to full" : ""
            sessionPart = "5-hour window \(percent(session.used ?? 0))\(close), resets \(time(date))"
        case .runsOut, .nearlyOut, .unused: sessionPart = "5-hour window \(percent(session.used ?? 0))"
        }
        var sentence = "\(name): \(weekPart); \(sessionPart)"
        if let readAt { sentence += ", reading from \(time(readAt))" }
        return sentence
    }

    /// The today line.
    public static func today(_ r: Reading, forecast: WeekForecast?, now: Date,
                             formatting: Formatting, _ t: Thresholds = Thresholds()) -> Today {
        guard let f = forecast, let reset = r.weekResetsAt else {
            return Today(main: "This week hasn’t started. Nothing is used yet.", warning: nil)
        }
        let resetText = formatting.dayTime(reset, now: now)
        if r.weekLeft < t.redWeekLeft {
            var main = "Only \(Formatting.percent(r.weekLeft)) left until \(resetText)"
            if f.pacePerHour > 0 { main += ", about \(hours(r.weekLeft / f.pacePerHour)) at your recent pace" }
            return Today(main: main + ".", warning: nil)
        }
        if let out = f.runsOutAt, let early = f.runsOutEarlyByHours {
            return Today(
                main: "Ease off to about \(Formatting.percent(f.useItAllPerDay)) a day to last until \(resetText).",
                warning: "At your current ~\(Formatting.percent(f.pacePerDay)) a day it runs out \(formatting.dayTime(out, now: now)), \(Formatting.duration(early * 3600)) early.",
                warningRunsOut: true)
        }
        let main: String
        if f.byMidnight >= r.weekLeft - 0.001 {
            main = "Use the last \(Formatting.percent(r.weekLeft)) before \(resetText)."
        } else {
            main = "Use about \(Formatting.percent(f.byMidnight)) more by midnight (to ~\(Formatting.percent(r.week + f.byMidnight)) used), then about \(Formatting.percent(f.useItAllPerDay)) a day."
        }
        let warning = f.unused >= t.onPaceUnused
            ? "At your current ~\(Formatting.percent(f.pacePerDay)) a day, about \(Formatting.percent(f.unused)) goes unused by \(resetText)."
            : nil
        return Today(main: main, warning: warning)
    }

    static func hours(_ h: Double) -> String {
        h < 1 ? "\(max(Int(h * 60), 1)) minutes" : "\(Int(h.rounded())) hours"
    }
}
