import Foundation

/// The words on Month, Trends and Names & tags. Pure, so tests can pin each sentence.
public enum PanesCopy {
    // MARK: Formatting

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    private static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) " + (n == 1 ? one : (many ?? one + "s"))
    }

    // MARK: Month

    /// "October 2026".
    public static func monthTitle(_ month: Date, calendar: Calendar) -> String {
        formatter("LLLL yyyy", calendar).string(from: month)
    }

    /// "‹ Sep".
    public static func previousMonth(_ month: Date, calendar: Calendar) -> String {
        "‹ " + formatter("LLL", calendar).string(from: calendar.date(byAdding: .month, value: -1, to: month) ?? month)
    }

    /// "Nov ›".
    public static func nextMonth(_ month: Date, calendar: Calendar) -> String {
        formatter("LLL", calendar).string(from: calendar.date(byAdding: .month, value: 1, to: month) ?? month) + " ›"
    }

    /// "Mon" … "Sun" (or "Sun" … "Sat"), from the first week's own days.
    public static func weekdayHeaders(_ firstWeek: [MonthDay], calendar: Calendar) -> [String] {
        let f = formatter("EEE", calendar)
        return firstWeek.map { f.string(from: $0.date) }
    }

    /// "Wednesday 21 October, today, 1 hour 32 minutes: Release notes, Daily brief. Opens that week."
    public static func dayVoiceOver(_ day: MonthDay, calendar: Calendar) -> String {
        var text = formatter("EEEE d MMMM", calendar).string(from: day.date)
        if day.isToday { text += ", today" }
        if day.seconds > 0 {
            let minutes = Int((day.seconds / 60).rounded(.toNearestOrEven))
            var spoken: [String] = []
            if minutes / 60 > 0 { spoken.append(plural(minutes / 60, "hour")) }
            if minutes % 60 > 0 || spoken.isEmpty { spoken.append(plural(minutes % 60, "minute")) }
            text += ", " + spoken.joined(separator: " ")
            if !day.top.isEmpty { text += ": " + day.top.map(\.title).joined(separator: ", ") }
        } else {
            text += ", nothing recorded"
        }
        return text + ". Opens that week."
    }

    // MARK: Trends

    public static func trendsCaption(_ grouping: TrendGrouping) -> String {
        let one = grouping == .project ? "project" : "tag"
        return "One row per \(one), every row on one scale; a paler column is this week so far. Click a row for its chart and weeks."
    }

    /// Whole hours ("84h"), or minutes under an hour ("30m").
    public static func hours(_ seconds: TimeInterval) -> String {
        if seconds > 0, seconds < 3600 { return "\(max(Int((seconds / 60).rounded()), 1))m" }
        return "\(Int((seconds / 3600).rounded()))h"
    }

    /// "19 – 25 Oct"; across months "28 Sep – 4 Oct".
    public static func weekRange(start: Date, calendar: Calendar) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let first = formatter(sameMonth ? "d" : "d MMM", calendar).string(from: start)
        return "\(first) – \(formatter("d MMM", calendar).string(from: end))"
    }

    private static func hoursSpoken(_ seconds: TimeInterval) -> String {
        let hours = Int((seconds / 3600).rounded())
        if hours == 0, seconds > 0 { return plural(max(Int((seconds / 60).rounded()), 1), "minute") }
        return plural(hours, "hour")
    }

    /// "tide-tables, 84 hours over 8 weeks. Opens its chart and weeks."
    public static func trendRowVoiceOver(_ row: TrendRow, weeks: Int, grouping: TrendGrouping) -> String {
        let name = grouping == .tag ? "Tag \(row.name)" : row.name
        return "\(name), \(hoursSpoken(row.total)) over \(plural(weeks, "week")). Opens its chart and weeks."
    }

    /// "84h over 13 weeks".
    public static func detailSummary(_ row: TrendRow, weeks: Int) -> String {
        "\(hours(row.total)) over \(plural(weeks, "week"))"
    }

    /// "19 – 25 Oct, so far" for the week still going.
    public static func detailWeekLabel(start: Date, isPartial: Bool, calendar: Calendar) -> String {
        weekRange(start: start, calendar: calendar) + (isPartial ? ", so far" : "")
    }

    public static func detailWeekVoiceOver(start: Date, seconds: TimeInterval, isPartial: Bool, calendar: Calendar) -> String {
        "\(detailWeekLabel(start: start, isPartial: isPartial, calendar: calendar)), \(hoursSpoken(seconds)). Opens that week."
    }

    // MARK: Names & tags

    /// What the row is called now: the user's name for it, or its title.
    public static func displayTitle(_ row: NameRow) -> String {
        if let name = row.entry.name, !name.isEmpty { return name }
        return row.key
    }

    /// The small line under a name: what a rule matches, what a renamed row was, or what a hidden
    /// project holds.
    public static func subline(_ row: NameRow, book: NameBook) -> String? {
        if let rule = row.ruleKey {
            return "titles starting with \"\(rule.hasSuffix("*") ? String(rule.dropLast()) : rule)\""
        }
        if row.kind == .projects {
            let held = book.projects.filter { $0.key != row.key && $0.value.project == row.key }.count
            let hidden = row.entry.hideTitles == true
            if held > 0 {
                let base = plural(held, "personal project")
                return hidden ? base + ", titles hidden" : base
            }
            return hidden ? "titles hidden" : nil
        }
        if let name = row.entry.name, !name.isEmpty, name != row.key { return "was \"\(row.key)\"" }
        return nil
    }

    public enum Field: Sendable { case name, tags, project, hideTitles }

    /// The VoiceOver label of one of a row's fields: "Name for Add chart export".
    public static func label(_ field: Field, for row: NameRow) -> String {
        let title = displayTitle(row)
        switch field {
        case .name: return "Name for \(title)"
        case .tags: return "Tags for \(title)"
        case .project: return "Project for \(title)"
        case .hideTitles: return "Hide titles for \(title)"
        }
    }

    /// "Couldn’t save: <reason>".
    public static func saveError(_ error: Error) -> String {
        "Couldn’t save: \(error.localizedDescription)"
    }

    /// Words split on commas, trimmed, without repeats.
    public static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The key of a "starts with" rule for `prefix`: the text with `*` at the end; nil when empty.
    public static func ruleKey(for prefix: String) -> String? {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasSuffix("*") ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed
        return body.isEmpty ? nil : body + "*"
    }
}
