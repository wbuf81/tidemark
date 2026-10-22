import Foundation

/// Tidemark's own three lines about a week, written from the numbers alone.
enum PlainReport {
    static func lines(_ w: WeekModel, calendar: Calendar) -> [String] {
        guard w.sessions > 0 else { return ["No sessions this week."] }
        return [first(w), second(w), third(w, calendar: calendar)]
    }

    private static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private static func first(_ w: WeekModel) -> String {
        let split: String
        if w.coworkSessions == 0 {
            split = "all Claude Code"
        } else if w.claudeCodeSessions == 0 {
            split = "all Cowork"
        } else {
            split = "\(w.claudeCodeSessions) Claude Code, \(w.coworkSessions) Cowork"
        }
        let commits = w.commits == 0 ? "no commits" : "\(plural(w.commits, "commit")) in \(plural(w.repos, "repo"))"
        return "\(HoursText.format(w.total)) of work across \(plural(w.sessions, "session")) (\(split)) and \(commits)."
    }

    private static func second(_ w: WeekModel) -> String {
        func percent(_ p: ProjectTotal) -> Int { w.total > 0 ? Int((p.seconds / w.total * 100).rounded()) : 0 }
        let top = Array(w.projects.prefix(3))
        switch top.count {
        case 0: return ""
        case 1: return "All of it on \(top[0].name)."
        case 2: return "Most time on \(top[0].name) (\(percent(top[0]))%), then \(top[1].name) (\(percent(top[1]))%)."
        default:
            return "Most time on \(top[0].name) (\(percent(top[0]))%), then \(top[1].name) (\(percent(top[1]))%) and \(top[2].name) (\(percent(top[2]))%)."
        }
    }

    private static func third(_ w: WeekModel, calendar: Calendar) -> String {
        let busiest = w.perDay.indices.max { w.perDay[$0] < w.perDay[$1] || (w.perDay[$0] == w.perDay[$1] && $0 > $1) } ?? 0
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMM"
        var text = "Busiest day \(formatter.string(from: w.days[busiest])) (\(HoursText.format(w.perDay[busiest])))"
        let weekdays = (0..<7).filter { (2...6).contains(calendar.component(.weekday, from: w.days[$0])) }
        for project in w.projects {
            let daysWithTime = Set(w.items.filter { $0.project == project.name && !$0.spans.isEmpty }.map(\.day))
            if weekdays.allSatisfy({ daysWithTime.contains($0) }) {
                text += "; \(project.name) ran all five weekdays"
                break
            }
        }
        return text + "."
    }
}
