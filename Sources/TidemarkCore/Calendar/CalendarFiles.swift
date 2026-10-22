import Foundation

/// Why a calendar file couldn't be read or written.
public enum CalendarFilesError: LocalizedError, Equatable, Sendable {
    /// Nothing is written: a file was saved by a newer Tidemark, or the file being written is one that can't be read.
    case readOnly(CalendarProblem)
    /// This file doesn't decode; it is kept as it was.
    case unreadable(file: String)

    public var errorDescription: String? {
        switch self {
        case .readOnly(let p): "\(p.title). \(p.detail)"
        case .unreadable(let f): "\(f) couldn’t be read."
        }
    }
}

/// The calendar's files in one folder (`<support>/calendar`), versioned, written atomically, with backups:
///
///     format.json            {"format":"tidemark-calendar","version":1,"lastRefresh":…}
///     sessions/<yyyy-MM>.json  {"version":1,"sessions":[…]}   by the local month of a session's first block
///     names.json             {"version":1,"names":…}
///     reports.json           {"version":1,"reports":[…]}
///     backups/<file>.<yyyyMMdd-HHmmss>-<nnn>.json   the last 10 of each file (sessions are `sessions-<yyyy-MM>`)
///
/// Safe to call from any thread (every call takes one lock). A file with a newer `version` makes the whole
/// calendar read-only; a file that won't decode is never written over, and only it is blocked.
/// A refresh passes whole months through `merge` first, so a session whose transcript is gone stays.
public struct CalendarFiles: Sendable {
    public static let version = 1
    public static let keptBackups = 10

    public let folder: URL
    private let calendar: Calendar
    private let state = State()

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        /// Problems found by reading, by file path under the folder.
        var problems: [String: CalendarProblem] = [:]
    }

    public init(folder: URL, calendar: Calendar = .current) {
        self.folder = folder
        self.calendar = CalendarKeys.gregorian(calendar)
    }

    // MARK: Months

    /// "yyyy-MM": the local month of the session's first block (its last activity if it has none).
    public static func month(of session: CalendarSession, calendar: Calendar = .current) -> String {
        let date = session.blocks.first?.start ?? session.lastActivity
        let c = CalendarKeys.gregorian(calendar).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Sessions from a refresh replace stored ones with the same id (in place); stored sessions the refresh
    /// didn't find are kept, because Claude Code deletes transcripts after 30 days. New ones follow in order.
    public static func merge(stored: [CalendarSession], refreshed: [CalendarSession]) -> [CalendarSession] {
        var latest: [String: CalendarSession] = [:]
        var order: [String] = []
        for s in refreshed {
            if latest[s.id] == nil { order.append(s.id) }
            latest[s.id] = s
        }
        var out: [CalendarSession] = []
        var placed = Set<String>()
        for s in stored where placed.insert(s.id).inserted { out.append(latest[s.id] ?? s) }
        for id in order where placed.insert(id).inserted { out.append(latest[id]!) }
        return out
    }

    public func loadMonth(_ month: String) throws -> [CalendarSession] {
        try locked { try readEnvelope("sessions/\(month).json", SessionsFile.self, lenient: true)?.sessions ?? [] }
    }

    public func saveMonth(_ month: String, _ sessions: [CalendarSession]) throws {
        try locked { try write(SessionsFile(version: Self.version, sessions: sessions), "sessions/\(month).json", backupBase: "sessions-\(month)") }
    }

    /// The months that have a file, oldest first.
    public func storedMonths() -> [String] {
        locked {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("sessions").path)) ?? []
            return names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }.sorted()
        }
    }

    /// Every stored session, month by month. A month that can't be read is skipped (and reported by `readOnlyReason`).
    public func loadAllSessions() -> [CalendarSession] {
        loadStored().months.flatMap(\.sessions)
    }

    /// Every month's sessions, oldest month first, and the months whose file couldn't be read (the store never writes those).
    public func loadStored() -> (months: [(month: String, sessions: [CalendarSession])], failed: [String]) {
        var months: [(month: String, sessions: [CalendarSession])] = []
        var failed: [String] = []
        for month in storedMonths() {
            do { months.append((month, try loadMonth(month))) } catch { failed.append(month) }
        }
        return (months, failed)
    }

    /// Writes each month these sessions belong to, replacing that month's file with exactly these sessions.
    public func save(sessions: [CalendarSession]) throws {
        var byMonth: [String: [CalendarSession]] = [:]
        for s in sessions { byMonth[Self.month(of: s, calendar: calendar), default: []].append(s) }
        for month in byMonth.keys.sorted() { try saveMonth(month, byMonth[month]!) }
    }

    // MARK: Names, reports, format

    public func loadNames() throws -> NameBook {
        try locked { try readEnvelope("names.json", NamesFile.self)?.names ?? NameBook() }
    }

    public func saveNames(_ names: NameBook) throws {
        try locked { try write(NamesFile(version: Self.version, names: names), "names.json", backupBase: "names") }
    }

    public func loadReports() throws -> [WeekReport] {
        try locked { try readEnvelope("reports.json", ReportsFile.self, lenient: true)?.reports ?? [] }
    }

    public func saveReports(_ reports: [WeekReport]) throws {
        try locked { try write(ReportsFile(version: Self.version, reports: reports), "reports.json", backupBase: "reports") }
    }

    /// When the last refresh finished; nil if never, or if format.json can't be read.
    public func loadLastRefresh() -> Date? {
        locked { (try? readFormat())?.lastRefresh }
    }

    /// The switches the last refresh was run with (an optional field of format.json), if it saved them.
    public func loadLastSources() -> SourceSwitches? {
        locked { (try? readFormat())?.lastSources }
    }

    public func saveLastRefresh(_ date: Date, sources: SourceSwitches? = nil) throws {
        try locked {
            var f = try readFormat() ?? FormatFile()
            f.lastRefresh = date
            if let sources { f.lastSources = sources }
            try write(f, "format.json", backupBase: "format")
        }
    }

    /// Why nothing can be written, if that's so: a newer version first, else the first file that couldn't be read.
    public var readOnlyReason: CalendarProblem? {
        locked {
            _ = try? readFormat()
            return state.problems.values.sorted { $0.id < $1.id }.first { $0.id == Self.newerID } ?? state.problems.values.sorted { $0.id < $1.id }.first
        }
    }

    // MARK: Reading and writing

    private static let newerID = "calendar-newer-version"
    private static let newerProblem = CalendarProblem(id: newerID, title: "Tidemark’s calendar was saved by a newer version",
                                                      detail: "Update Tidemark to change it. Everything still shows.")

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        state.lock.lock()
        defer { state.lock.unlock() }
        return try body()
    }

    private struct Probe: Decodable { var version: Int }

    private func url(_ path: String) -> URL { folder.appendingPathComponent(path) }

    private func markUnreadable(_ path: String) -> CalendarFilesError {
        let file = (path as NSString).lastPathComponent
        state.problems[path] = CalendarProblem(id: "calendar-unreadable-\(path)", title: "A calendar file couldn’t be read",
                                               detail: "\(file) is kept as it was. Tidemark won’t write over it.")
        return .unreadable(file: file)
    }

    /// Reads and decodes one file. nil if it doesn't exist. Records and throws if it's newer or won't decode.
    /// `lenient` reads a file from a newer version as far as it decodes (still recording the newer-version problem,
    /// which blocks every write), so what it holds still shows.
    private func readEnvelope<T: Decodable>(_ path: String, _ type: T.Type, lenient: Bool = false) throws -> T? {
        guard let data = try? Data(contentsOf: url(path)) else {
            if FileManager.default.fileExists(atPath: url(path).path) { throw markUnreadable(path) }
            state.problems[path] = nil
            return nil
        }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else { throw markUnreadable(path) }
        if probe.version > Self.version {
            state.problems[Self.newerID] = Self.newerProblem
            if lenient, let value = try? Self.decoder.decode(T.self, from: data) { return value }
            throw CalendarFilesError.readOnly(Self.newerProblem)
        }
        do {
            let value = try Self.decoder.decode(T.self, from: data)
            state.problems[path] = nil
            return value
        } catch {
            throw markUnreadable(path)
        }
    }

    private func readFormat() throws -> FormatFile? {
        try readEnvelope("format.json", FormatFile.self, lenient: true)
    }

    /// Refuses unless the calendar is writable and `path` is a file that's absent or readable.
    private func write<T: Encodable>(_ value: T, _ path: String, backupBase: String) throws {
        // A corrupt format.json blocks only itself; a newer one (or any newer file found earlier) blocks everything.
        _ = try? readFormat()
        if let p = state.problems[Self.newerID] { throw CalendarFilesError.readOnly(p) }
        if path != "format.json" {
            // First write creates format.json so a newer or older Tidemark can tell what this folder is.
            if !FileManager.default.fileExists(atPath: url("format.json").path) {
                try writeFile(try Self.encoder.encode(FormatFile()), "format.json", backupBase: "format")
            }
        }
        if FileManager.default.fileExists(atPath: url(path).path) {
            // The file being replaced must be one we can read (and not newer); otherwise it is kept untouched.
            switch path {
            case "names.json": _ = try readEnvelope(path, NamesFile.self)
            case "reports.json": _ = try readEnvelope(path, ReportsFile.self)
            case "format.json": break
            default: _ = try readEnvelope(path, SessionsFile.self)
            }
            if let p = state.problems[Self.newerID] { throw CalendarFilesError.readOnly(p) }
        }
        try writeFile(try Self.encoder.encode(value), path, backupBase: backupBase)
    }

    private func writeFile(_ data: Data, _ path: String, backupBase: String) throws {
        let fm = FileManager.default
        let dest = url(path)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try backUp(dest, base: backupBase) }
        let temp = dest.deletingLastPathComponent().appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temp)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: dest)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        state.problems[path] = nil
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Copies the file about to be replaced into backups/ and keeps the newest 10 for that file.
    private func backUp(_ file: URL, base: String) throws {
        let fm = FileManager.default
        let dir = url("backups")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Self.stamp.string(from: Date())
        let existing = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(base + ".") && $0.hasSuffix(".json") }
        // The counter follows the highest one already used this second, so pruning never makes a name repeat.
        let prefix = "\(base).\(now)-"
        let used = existing.filter { $0.hasPrefix(prefix) }.compactMap { Int($0.dropFirst(prefix.count).dropLast(5)) }
        let name = "\(prefix)\(String(format: "%03d", (used.max() ?? -1) + 1)).json"
        try fm.copyItem(at: file, to: dir.appendingPathComponent(name))
        let all = (existing + [name]).sorted()
        for old in all.dropLast(Self.keptBackups) { try? fm.removeItem(at: dir.appendingPathComponent(old)) }
    }

    // MARK: Formats

    private struct SessionsFile: Codable { var version: Int; var sessions: [CalendarSession] }
    private struct NamesFile: Codable { var version: Int; var names: NameBook }
    private struct ReportsFile: Codable { var version: Int; var reports: [WeekReport] }
    private struct FormatFile: Codable {
        var format = "tidemark-calendar"
        var version = CalendarFiles.version
        var lastRefresh: Date?
        /// The switches that refresh ran with, so a source turned on later is read in full.
        var lastSources: SourceSwitches?
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// The calendar every file name, key and "yyyy-MM-dd" string is made with: always Gregorian (a Buddhist or Japanese
/// Mac calendar would name files 2569-10), with the user's time zone, locale and first weekday.
enum CalendarKeys {
    static func gregorian(_ calendar: Calendar) -> Calendar {
        if calendar.identifier == .gregorian { return calendar }
        var made = Calendar(identifier: .gregorian)
        made.timeZone = calendar.timeZone
        made.locale = calendar.locale
        made.firstWeekday = calendar.firstWeekday
        made.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        return made
    }
}
