import Foundation

// The week calendar's data, shared by the engine, the window, the widget and the shell.
// Frozen (docs/contracts.md): change these only through the coordinator.

/// Where a session came from.
public enum SessionOrigin: String, Codable, Sendable {
    case claudeCode, cowork
}

/// A stretch of activity with no gap longer than the idle gap (30 minutes).
public struct Block: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// One of the user's own git commits, matched to the session that made it.
public struct Commit: Codable, Equatable, Sendable {
    public var sha: String
    public var time: Date
    public var repo: String
    public var subject: String
    public var files: [String]

    public init(sha: String, time: Date, repo: String, subject: String, files: [String] = []) {
        self.sha = sha
        self.time = time
        self.repo = repo
        self.subject = subject
        self.files = files
    }
}

/// A Claude Code session or a Cowork task, as stored. Blocks are unclipped; weeks clip them when shown.
public struct CalendarSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var origin: SessionOrigin
    public var title: String?
    /// Only kept while the "First messages" source is on.
    public var firstMessage: String?
    public var command: String?
    /// The project root before the user's moves: a repo's main checkout, the folder, or "Cowork".
    public var root: String
    /// Cowork folders attached to the task.
    public var folders: [String]
    public var isGit: Bool
    public var scheduled: Bool
    /// A Cowork task that logged itself.
    public var logged: Bool
    public var blocks: [Block]
    public var commits: [Commit]
    public var lastActivity: Date

    public init(id: String, origin: SessionOrigin, title: String? = nil, firstMessage: String? = nil, command: String? = nil,
                root: String, folders: [String] = [], isGit: Bool = false, scheduled: Bool = false, logged: Bool = false,
                blocks: [Block], commits: [Commit] = [], lastActivity: Date) {
        self.id = id
        self.origin = origin
        self.title = title
        self.firstMessage = firstMessage
        self.command = command
        self.root = root
        self.folders = folders
        self.isGit = isGit
        self.scheduled = scheduled
        self.logged = logged
        self.blocks = blocks
        self.commits = commits
        self.lastActivity = lastActivity
    }
}

/// Which day a week starts on. `region` follows the Mac's region.
public enum WeekStart: String, Codable, Sendable, CaseIterable {
    case region, monday, sunday
}

/// What builds the week, each switchable in Settings → Week and the first run.
public struct SourceSwitches: Codable, Equatable, Sendable {
    public var claudeCode = true
    public var firstMessages = false
    public var git = true
    /// The folder Cowork logs its tasks to; nil until the user chooses one.
    public var coworkLogFolder: String? = nil
    /// Claude Desktop's older Cowork session folder.
    public var desktopCowork = false

    public init() {}
}

// MARK: - Names, tags and projects

/// What the user calls a session, project or Cowork folder, and where it belongs.
public struct NameEntry: Codable, Equatable, Sendable {
    public var name: String?
    public var tags: [String]?
    public var project: String?
    public var hideTitles: Bool?

    public init(name: String? = nil, tags: [String]? = nil, project: String? = nil, hideTitles: Bool? = nil) {
        self.name = name
        self.tags = tags
        self.project = project
        self.hideTitles = hideTitles
    }
}

public enum NameKind: String, Codable, Sendable, CaseIterable {
    case sessions, projects, folders
}

/// Every name, tag and move the user made. Keys ending in `*` are "starts with" rules.
public struct NameBook: Codable, Equatable, Sendable {
    public var sessions: [String: NameEntry] = [:]
    public var projects: [String: NameEntry] = [:]
    public var folders: [String: NameEntry] = [:]
    /// A folder's basename → the project name the calendar uses for it.
    public var projectFolders: [String: String] = [:]

    public init() {}
}

/// One edit from Names & tags. A nil field isn't sent and stays as it was; `.some(nil)` clears it.
public struct NameChange: Equatable, Sendable {
    public var kind: NameKind
    public var key: String
    public var name: String??
    public var tags: [String]?
    public var project: String??
    public var hideTitles: Bool?

    public init(kind: NameKind, key: String, name: String?? = nil, tags: [String]? = nil, project: String?? = nil, hideTitles: Bool? = nil) {
        self.kind = kind
        self.key = key
        self.name = name
        self.tags = tags
        self.project = project
        self.hideTitles = hideTitles
    }
}

public enum NameBookError: LocalizedError, Equatable, Sendable {
    case badKey, badTags, unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .badKey: "That name can’t be used."
        case .badTags: "Tags must be a list of words."
        case .unreadable(let reason): "names.json couldn’t be read: \(reason)"
        }
    }
}

// MARK: - What the window shows

/// One session on one day of a week.
public struct WeekItem: Equatable, Sendable, Identifiable {
    /// "<session id>|<yyyy-MM-dd>"
    public var id: String
    public var sessionID: String
    /// 0…6 from the week's first day.
    public var day: Int
    /// As shown: the user's name for it, or the project's name when the project hides titles.
    public var title: String
    /// The shown project name.
    public var project: String
    /// 0…6, the project's colour; see ProjectTotal.
    public var colorIndex: Int
    /// This session's blocks clipped to this day.
    public var spans: [DateInterval]
    /// The union of `spans`.
    public var seconds: TimeInterval
    public var commits: Int
    public var commitSubjects: [String]
    public var origin: SessionOrigin
    public var scheduled: Bool
    public var noCommit: Bool
    public var titlesHidden: Bool

    public init(id: String, sessionID: String, day: Int, title: String, project: String, colorIndex: Int, spans: [DateInterval],
                seconds: TimeInterval, commits: Int = 0, commitSubjects: [String] = [], origin: SessionOrigin = .claudeCode,
                scheduled: Bool = false, noCommit: Bool = false, titlesHidden: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.day = day
        self.title = title
        self.project = project
        self.colorIndex = colorIndex
        self.spans = spans
        self.seconds = seconds
        self.commits = commits
        self.commitSubjects = commitSubjects
        self.origin = origin
        self.scheduled = scheduled
        self.noCommit = noCommit
        self.titlesHidden = titlesHidden
    }
}

/// A project's share of a week. `colorIndex` is its rank (0…5); everything after the sixth is 6.
public struct ProjectTotal: Equatable, Sendable {
    public var name: String
    public var seconds: TimeInterval
    public var sessions: Int
    public var commits: Int
    public var colorIndex: Int

    public init(name: String, seconds: TimeInterval, sessions: Int, commits: Int, colorIndex: Int) {
        self.name = name
        self.seconds = seconds
        self.sessions = sessions
        self.commits = commits
        self.colorIndex = colorIndex
    }
}

public struct TagTotal: Equatable, Sendable {
    public var tag: String
    public var seconds: TimeInterval
    public var sessions: Int
    public var commits: Int

    public init(tag: String, seconds: TimeInterval, sessions: Int, commits: Int) {
        self.tag = tag
        self.seconds = seconds
        self.sessions = sessions
        self.commits = commits
    }
}

/// Who wrote a weekly report.
public enum ReportAuthor: String, Codable, Sendable {
    case tidemark
    case claudeCode = "claude-code"
    /// Brought over from the old week calendar.
    case imported
}

/// A week's three-line report, and optional notes per day.
public struct WeekReport: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd", the week's first day.
    public var weekStart: String
    public var lines: [String]
    /// "yyyy-MM-dd" → a note for that day.
    public var days: [String: String]
    public var author: ReportAuthor
    public var written: Date

    public init(weekStart: String, lines: [String], days: [String: String] = [:], author: ReportAuthor, written: Date) {
        self.weekStart = weekStart
        self.lines = lines
        self.days = days
        self.author = author
        self.written = written
    }
}

public enum ReportFailure: Error, Equatable, Sendable {
    case notInstalled, failed(String), timedOut, unreadable
}

/// Something the calendar can't do, in words for the user.
public struct CalendarProblem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// One week, computed when it's shown.
public struct WeekModel: Equatable, Sendable {
    public var start: Date
    /// 8 local midnights: the week's 7 days and the end.
    public var days: [Date]
    /// Time with any session running; parallel sessions counted once.
    public var total: TimeInterval
    public var claudeCodeSeconds: TimeInterval
    public var coworkSeconds: TimeInterval
    public var sessions: Int
    public var claudeCodeSessions: Int
    public var coworkSessions: Int
    public var commits: Int
    public var repos: Int
    /// 7 values each.
    public var perDay: [TimeInterval]
    public var commitsPerDay: [Int]
    /// Seconds descending.
    public var projects: [ProjectTotal]
    public var tags: [TagTotal]
    /// By day, then by first span.
    public var items: [WeekItem]
    /// 7 values; "" when there's nothing to say.
    public var dayNotes: [String]
    /// The lede on the Week pane.
    public var brief: String
    /// Tidemark's own three lines.
    public var plainReport: [String]
    /// A saved report, if one was written.
    public var report: WeekReport?
    /// Projects (shown names) with a session still running.
    public var running: [String]
    /// Claude Code had already deleted some of this week's logs.
    public var isPartial: Bool
    public var problems: [CalendarProblem]

    public init(start: Date, days: [Date], total: TimeInterval = 0, claudeCodeSeconds: TimeInterval = 0, coworkSeconds: TimeInterval = 0,
                sessions: Int = 0, claudeCodeSessions: Int = 0, coworkSessions: Int = 0, commits: Int = 0, repos: Int = 0,
                perDay: [TimeInterval] = Array(repeating: 0, count: 7), commitsPerDay: [Int] = Array(repeating: 0, count: 7),
                projects: [ProjectTotal] = [], tags: [TagTotal] = [], items: [WeekItem] = [],
                dayNotes: [String] = Array(repeating: "", count: 7), brief: String = "", plainReport: [String] = [],
                report: WeekReport? = nil, running: [String] = [], isPartial: Bool = false, problems: [CalendarProblem] = []) {
        self.start = start
        self.days = days
        self.total = total
        self.claudeCodeSeconds = claudeCodeSeconds
        self.coworkSeconds = coworkSeconds
        self.sessions = sessions
        self.claudeCodeSessions = claudeCodeSessions
        self.coworkSessions = coworkSessions
        self.commits = commits
        self.repos = repos
        self.perDay = perDay
        self.commitsPerDay = commitsPerDay
        self.projects = projects
        self.tags = tags
        self.items = items
        self.dayNotes = dayNotes
        self.brief = brief
        self.plainReport = plainReport
        self.report = report
        self.running = running
        self.isPartial = isPartial
        self.problems = problems
    }
}

public struct MonthItem: Equatable, Sendable {
    public var title: String
    public var colorIndex: Int

    public init(title: String, colorIndex: Int) {
        self.title = title
        self.colorIndex = colorIndex
    }
}

public struct MonthDay: Equatable, Sendable {
    public var date: Date
    public var inMonth: Bool
    public var isToday: Bool
    public var seconds: TimeInterval
    /// The day's two longest items.
    public var top: [MonthItem]

    public init(date: Date, inMonth: Bool, isToday: Bool, seconds: TimeInterval, top: [MonthItem]) {
        self.date = date
        self.inMonth = inMonth
        self.isToday = isToday
        self.seconds = seconds
        self.top = top
    }
}

public struct MonthModel: Equatable, Sendable {
    /// The month's first day.
    public var month: Date
    /// Whole weeks, each 7 days, starting on the week start.
    public var weeks: [[MonthDay]]

    public init(month: Date, weeks: [[MonthDay]]) {
        self.month = month
        self.weeks = weeks
    }
}

public enum TrendGrouping: String, Sendable, CaseIterable {
    case project, tag
}

public struct TrendRow: Equatable, Sendable {
    public var name: String
    /// One value per week in TrendModel.weeks.
    public var seconds: [TimeInterval]
    public var total: TimeInterval

    public init(name: String, seconds: [TimeInterval], total: TimeInterval) {
        self.name = name
        self.seconds = seconds
        self.total = total
    }
}

public struct TrendModel: Equatable, Sendable {
    /// Each week's first day, oldest first.
    public var weeks: [Date]
    /// Total descending.
    public var rows: [TrendRow]
    /// The last week is this week, still going.
    public var lastIsPartial: Bool

    public init(weeks: [Date], rows: [TrendRow], lastIsPartial: Bool) {
        self.weeks = weeks
        self.rows = rows
        self.lastIsPartial = lastIsPartial
    }
}

/// A row in Names & tags.
public struct NameRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: NameKind
    /// The title, project or folder as the calendar sees it.
    public var key: String
    /// The layered entry: a matching rule's fields, then the key's own.
    public var entry: NameEntry
    /// The "starts with" rule that matched, if any.
    public var ruleKey: String?
    public var seconds: TimeInterval
    /// The shown project it's in now.
    public var currentProject: String

    public init(id: String, kind: NameKind, key: String, entry: NameEntry, ruleKey: String? = nil, seconds: TimeInterval, currentProject: String) {
        self.id = id
        self.kind = kind
        self.key = key
        self.entry = entry
        self.ruleKey = ruleKey
        self.seconds = seconds
        self.currentProject = currentProject
    }
}

public struct RefreshSummary: Equatable, Sendable {
    public var sessionsRead: Int
    public var sessionsChanged: Int
    public var problems: [CalendarProblem]

    public init(sessionsRead: Int = 0, sessionsChanged: Int = 0, problems: [CalendarProblem] = []) {
        self.sessionsRead = sessionsRead
        self.sessionsChanged = sessionsChanged
        self.problems = problems
    }
}

/// An old week calendar found on disk.
public struct LegacyFound: Equatable, Sendable {
    public var weeks: Int
    /// "yyyy-MM-dd" of the first and last week.
    public var first: String
    public var last: String
    public var hasNames: Bool
    public var hasReports: Bool

    public init(weeks: Int, first: String, last: String, hasNames: Bool, hasReports: Bool) {
        self.weeks = weeks
        self.first = first
        self.last = last
        self.hasNames = hasNames
        self.hasReports = hasReports
    }
}

public struct ImportResult: Equatable, Sendable {
    public var weeks: Int
    public var sessionsAdded: Int
    public var sessionsKept: Int
    /// Week starts whose recomputed total differs from the old calendar's by more than 60 seconds.
    public var mismatches: [String]

    public init(weeks: Int, sessionsAdded: Int, sessionsKept: Int, mismatches: [String]) {
        self.weeks = weeks
        self.sessionsAdded = sessionsAdded
        self.sessionsKept = sessionsKept
        self.mismatches = mismatches
    }
}
