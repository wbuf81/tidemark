import Foundation

/// A week in brief: hours and commits by day, the top projects, the weeks before and anything
/// wrong. The calendar store hands it out (`CalendarStoring.weekSummary`); the `week-summary/1`
/// JSON form stays decodable, with fields it doesn't know ignored and missing optional ones empty.
public struct WeekSummary: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        /// "2026-10-19", the calendar's own local date.
        public var date: String
        public var seconds: Double
        public var commits: Int

        public init(date: String, seconds: Double, commits: Int = 0) {
            self.date = date
            self.seconds = seconds
            self.commits = commits
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
            commits = try c.decodeIfPresent(Int.self, forKey: .commits) ?? 0
        }
    }

    public struct Project: Codable, Equatable, Sendable {
        public var name: String
        public var seconds: Double

        public init(name: String, seconds: Double) {
            self.name = name
            self.seconds = seconds
        }
    }

    public struct Week: Codable, Equatable, Sendable {
        public var start: String
        public var end: String
        /// Time with a session running, parallel sessions counted once.
        public var seconds: Double
        public var sessions: Int
        public var commits: Int
        public var days: [Day]
        public var projects: [Project]
        /// Last week's total, for comparison; nil when there's no week before.
        public var previousSeconds: Double?

        public init(start: String, end: String, seconds: Double, sessions: Int, commits: Int,
                    days: [Day], projects: [Project], previousSeconds: Double?) {
            self.start = start
            self.end = end
            self.seconds = seconds
            self.sessions = sessions
            self.commits = commits
            self.days = days
            self.projects = projects
            self.previousSeconds = previousSeconds
        }

        enum CodingKeys: String, CodingKey {
            case start, end, seconds, sessions, commits, days, projects
            case previousSeconds = "previous_seconds"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            start = try c.decode(String.self, forKey: .start)
            end = try c.decodeIfPresent(String.self, forKey: .end) ?? start
            seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
            sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
            commits = try c.decodeIfPresent(Int.self, forKey: .commits) ?? 0
            days = try c.decodeIfPresent([Day].self, forKey: .days) ?? []
            projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
            previousSeconds = try c.decodeIfPresent(Double.self, forKey: .previousSeconds)
        }
    }

    /// A week before this one, by its first day.
    public struct Total: Codable, Equatable, Sendable {
        public var start: String
        public var seconds: Double

        public init(start: String, seconds: Double) {
            self.start = start
            self.seconds = seconds
        }
    }

    /// Something the calendar says isn't working, e.g. a nightly build that didn't run.
    public struct Problem: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String = "") {
            self.title = title
            self.detail = detail
        }
    }

    /// Where the calendar's pages are: a web address and a file to fall back on.
    public struct Links: Codable, Equatable, Sendable {
        public var week: String?
        public var trends: String?
        public var weekFile: String?

        public init(week: String? = nil, trends: String? = nil, weekFile: String? = nil) {
            self.week = week
            self.trends = trends
            self.weekFile = weekFile
        }

        enum CodingKeys: String, CodingKey {
            case week, trends
            case weekFile = "week_file"
        }
    }

    public var format: String
    /// When the calendar wrote the file.
    public var generated: Date?
    public var week: Week
    public var weeks: [Total]
    public var problems: [Problem]
    public var links: Links?

    public init(format: String = WeekSummary.format, generated: Date?, week: Week, weeks: [Total] = [],
                problems: [Problem] = [], links: Links? = nil) {
        self.format = format
        self.generated = generated
        self.week = week
        self.weeks = weeks
        self.problems = problems
        self.links = links
    }

    public static let format = "week-summary/1"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        generated = try c.decodeIfPresent(Date.self, forKey: .generated)
        week = try c.decode(Week.self, forKey: .week)
        weeks = try c.decodeIfPresent([Total].self, forKey: .weeks) ?? []
        problems = try c.decodeIfPresent([Problem].self, forKey: .problems) ?? []
        links = try c.decodeIfPresent(Links.self, forKey: .links)
    }
}

extension WeekSummary {
    /// A short total, rounded down everywhere it shows (S4.24): "45m" under an hour, then whole
    /// hours ("19h" for 19 h 20 m). Rounding down means a total never claims more than it has.
    public static func shortHours(_ seconds: Double) -> String {
        let minutes = max(Int(seconds / 60), 0)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// Hours as the calendar writes them: "31h 05m", "0h 45m".
    public static func hours(_ seconds: Double) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 0)
        return "\(minutes / 60)h " + String(format: "%02d", minutes % 60) + "m"
    }

    /// Each day's hours as a share of the busiest day's, 0...1 (all 0 for an empty week).
    public var dayLevels: [Double] {
        let peak = week.days.map(\.seconds).max() ?? 0
        return week.days.map { peak > 0 ? $0.seconds / peak : 0 }
    }

    /// Which of the week's days is today in `calendar`, or nil when today isn't in this week.
    public func todayIndex(now: Date, calendar: Calendar) -> Int? {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let today = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return week.days.firstIndex { $0.date == today }
    }

    /// A day's date in `calendar`, at noon (so it can't slip a day), or nil when it doesn't parse.
    public static func date(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The file wasn't written in the last `limit` (36 hours: the calendar rebuilds nightly), or never said when.
    public func isStale(now: Date, limit: TimeInterval = 36 * 3600) -> Bool {
        generated.map { now.timeIntervalSince($0) > limit } ?? true
    }

    /// Whether `now` falls after this week's last day: the calendar hasn't started the new week yet.
    public func isPast(now: Date, calendar: Calendar) -> Bool {
        guard let end = Self.date(week.end, calendar: calendar) else { return false }
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: end)
    }

    /// The week as one sentence, for VoiceOver and the tooltip.
    public var sentence: String {
        var parts = ["This week: \(Self.hours(week.seconds))"]
        if week.sessions > 0 { parts[0] += " over \(week.sessions) session\(week.sessions == 1 ? "" : "s")" }
        if week.commits > 0 { parts[0] += ", \(week.commits) commit\(week.commits == 1 ? "" : "s")" }
        if let top = week.projects.first { parts.append("Most time: \(top.name), \(Self.hours(top.seconds))") }
        if let last = week.previousSeconds { parts.append("Last week: \(Self.hours(last))") }
        if let problem = problems.first { parts.append(problem.title) }
        return parts.joined(separator: ". ") + "."
    }
}
