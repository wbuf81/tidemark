import Foundation

/// The words on the Week pane, in one place so they can be tested.
public enum WindowCopy {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "19 – 25 Oct"; across months "28 Sep – 4 Oct".
    public static func range(_ w: WeekModel, calendar: Calendar) -> String {
        let first = w.days.first ?? w.start
        let last = w.days.count > 6 ? w.days[6] : first
        func parts(_ d: Date) -> (day: Int, month: Int) {
            (calendar.component(.day, from: d), calendar.component(.month, from: d) - 1)
        }
        let (a, b) = (parts(first), parts(last))
        if a.month == b.month { return "\(a.day) – \(b.day) \(months[b.month])" }
        return "\(a.day) \(months[a.month]) – \(b.day) \(months[b.month])"
    }

    /// "12 Oct": a week's first day, for the "‹ 12 Oct" button.
    public static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.day, from: date)) \(months[calendar.component(.month, from: date) - 1])"
    }

    /// "11 Claude Code · 4 Cowork"
    public static func sessionsDetail(_ w: WeekModel) -> String {
        var parts: [String] = []
        if w.claudeCodeSessions > 0 { parts.append("\(w.claudeCodeSessions) Claude Code") }
        if w.coworkSessions > 0 { parts.append("\(w.coworkSessions) Cowork") }
        return parts.isEmpty ? "none yet" : parts.joined(separator: " · ")
    }

    /// "in 3 repos", "in 1 repo" or "none".
    public static func commitsDetail(_ w: WeekModel) -> String {
        guard w.commits > 0, w.repos > 0 else { return "none" }
        return "in \(w.repos) \(w.repos == 1 ? "repo" : "repos")"
    }

    /// "tide-tables took 52%"
    public static func projectsDetail(_ w: WeekModel) -> String {
        guard let parts = projectsDetailParts(w) else { return "none yet" }
        return parts.name + parts.rest
    }

    /// The same line in two parts, so a view can shorten the name and never the " took 44%".
    public static func projectsDetailParts(_ w: WeekModel) -> (name: String, rest: String)? {
        guard let top = w.projects.first, w.total > 0 else { return nil }
        return (top.name, " took \(Int((top.seconds / w.total * 100).rounded()))%")
    }

    /// "Wed 21"
    public static func dayHeading(_ w: WeekModel, day: Int, now: Date, calendar: Calendar) -> String {
        guard day >= 0, day < w.days.count else { return "" }
        let date = w.days[day]
        let weekday = String(weekdays[calendar.component(.weekday, from: date) - 1].prefix(3))
        return "\(weekday) \(calendar.component(.day, from: date))"
    }

    /// "7h 10m · 52 commits"; today's carries "so far" ("3h 05m so far · 14 commits"). Empty for a day
    /// with no time.
    public static func dayHours(_ w: WeekModel, day: Int, now: Date, calendar: Calendar) -> String {
        guard day >= 0, day < w.perDay.count, w.perDay[day] > 0, day < w.days.count else { return "" }
        let isToday = calendar.isDate(w.days[day], inSameDayAs: now)
        var text = HoursText.format(w.perDay[day]) + (isToday ? " so far" : "")
        let commits = day < w.commitsPerDay.count ? w.commitsPerDay[day] : 0
        if commits > 0 { text += " · \(commits) \(commits == 1 ? "commit" : "commits")" }
        return text
    }

    /// "Add chart export, tide-tables, Monday 9:30 AM to 12:30 PM, 3 hours, 20 commits". `sharing` names
    /// sessions that had no lane of their own beside this one.
    public static func voiceOver(_ item: WeekItem, sharing: [String] = [], calendar: Calendar,
                                 twentyFourHour: Bool = Formatting.prefers24Hour()) -> String {
        let clock = Formatting(calendar: calendar, twentyFourHour: twentyFourHour)
        var parts = [item.title, item.project]
        if let first = item.spans.map(\.start).min(), let last = item.spans.map(\.end).max() {
            parts.append("\(weekdays[calendar.component(.weekday, from: first) - 1]) \(clock.hour(first)) to \(clock.hour(last))")
        }
        parts.append(duration(item.seconds))
        if item.commits > 0 { parts.append("\(item.commits) \(item.commits == 1 ? "commit" : "commits")") }
        else if item.noCommit { parts.append("no commits") }
        if !sharing.isEmpty { parts.append("also running: " + sharing.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }

    /// "2 hours 30 minutes", "1 hour", "45 minutes".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        let (h, m) = (minutes / 60, minutes % 60)
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 || h == 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        return parts.joined(separator: " ")
    }

    // MARK: The weekly report

    public static let plainReportNote = "Written by Tidemark from the week’s numbers. Nothing leaves your Mac."
    public static let emptyWeek = "No sessions yet this week."
    /// Until the user has chosen what Tidemark reads, the Week pane shows this and a button instead of a week.
    public static let sourcesNotChosen = "Choose what Tidemark reads."
    public static let sourcesNotChosenButton = "Choose sources"
    public static let partialWeek = "Claude Code had already deleted some of this week’s logs; what’s left is shown."

    /// "Written by Claude Code, Mon 19 Oct 9:02 AM"
    public static func writtenBy(_ report: WeekReport, calendar: Calendar, twentyFourHour: Bool = Formatting.prefers24Hour()) -> String {
        let clock = Formatting(calendar: calendar, twentyFourHour: twentyFourHour)
        let who = report.author == .claudeCode ? "Claude Code" : report.author == .imported ? "the old week calendar" : "Tidemark"
        let d = report.written
        let when = "\(String(weekdays[calendar.component(.weekday, from: d) - 1].prefix(3))) \(dayMonth(d, calendar: calendar)) \(clock.hour(d))"
        return "Written by \(who), \(when)"
    }

    /// What a failed report says.
    public static func reportFailure(_ failure: ReportFailure) -> String {
        switch failure {
        case .notInstalled: "Claude Code isn’t installed. Install it, sign in, then try again."
        case .timedOut: "Claude Code didn’t answer within 2 minutes."
        case .failed(let message): message.hasPrefix("Claude Code ") ? message : "Claude Code couldn’t write it: \(message)"
        case .unreadable: "Claude Code’s answer couldn’t be read. Try again."
        }
    }
}
