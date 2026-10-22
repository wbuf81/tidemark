import Foundation

/// The calendar as the app uses it: sessions, names and reports kept in files under `folder`, with weeks,
/// months and trends computed from them when asked.
///
/// Safe to call from any thread. Every query answers from what was last loaded or saved (one lock guards
/// that state); a refresh runs on its own and never makes a query wait. Refreshes run one at a time.
public final class CalendarStore: CalendarStoring, @unchecked Sendable {
    let folder: URL
    let home: URL
    let environment: [String: String]
    let runner: ProcessRunning

    /// Guards the cached state below; held only briefly, never across disk or process work.
    private let lock = NSLock()
    /// Every write path (a refresh's save, an import, name edits, saving a report, Delete all) takes its turn here, so two
    /// of them can never interleave their read-merge-write.
    private let writer = NSLock()
    private var _calendar: Calendar
    private var observer: NSObjectProtocol?
    private var files: CalendarFiles
    private var sessions: [CalendarSession] = []
    /// The month file each stored session came from (or was last written to), and other months that held a stale copy.
    private var homes: [String: String] = [:]
    private var strays: [String: Set<String>] = [:]
    /// Months that couldn't be read when the calendar loaded: never written, even if they read fine later.
    private var failedMonths: Set<String> = []
    private var nameBook = NameBook()
    /// names.json couldn't be read (or is from a newer version): every title is hidden until it can be.
    private var namesUnreadable = false
    private var reports: [WeekReport] = []
    private var filesProblem: CalendarProblem?
    private var refreshProblems: [CalendarProblem] = []
    private var retentionDays = 30
    private var running: Task<RefreshSummary, Never>?
    private var computerCache: WeekComputer?
    /// What the last saved refresh was told to read (kept in format.json): a source switched on since is read in full.
    private var lastSwitches = SourceSwitches()
    /// Bumped by Delete all: a refresh that started before it drops its result.
    private var generation = 0
    private var waiting = 0
    /// Tests only: called inside the writer's turn, after it merged and before it writes.
    var beforeWrite: (() -> Void)?

    /// `calendar` is the Mac's calendar and time zone; file names, keys and day strings always use a Gregorian one made from it.
    /// Without one the store follows the system's time zone as it changes while the app runs.
    public init(folder: URL, home: URL, environment: [String: String], runner: ProcessRunning = SystemProcessRunner(),
                calendar: Calendar? = nil) {
        self.folder = folder
        self.home = home
        self.environment = environment
        self.runner = runner
        let made = CalendarKeys.gregorian(calendar ?? Self.systemCalendar())
        self._calendar = made
        self.files = CalendarFiles(folder: folder, calendar: made)
        load()
        if calendar == nil {
            observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: nil) { [weak self] _ in
                NSTimeZone.resetSystemTimeZone()
                self?.useCalendar(Self.systemCalendar())
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    static func systemCalendar() -> Calendar { CalendarKeys.gregorian(Calendar.current) }

    var calendar: Calendar { locked { _calendar } }

    /// Switches the calendar (the time zone changed): weeks and months are worked out again, nothing stored moves.
    func useCalendar(_ calendar: Calendar) {
        locked {
            _calendar = CalendarKeys.gregorian(calendar)
            computerCache = nil
        }
    }

    // MARK: State

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Runs `body` as the only writer. Other writers wait their turn; queries never wait.
    func serialized<T>(_ body: () throws -> T) rethrows -> T {
        locked { waiting += 1 }
        writer.lock()
        locked { waiting -= 1 }
        defer { writer.unlock() }
        return try body()
    }

    /// How many writers are waiting for their turn (tests).
    var queuedWriters: Int { locked { waiting } }

    /// Reads everything from disk into the cached state.
    private func load() {
        let stored = files.loadStored()
        var names = NameBook()
        var unreadable = false
        do { names = try files.loadNames() } catch { unreadable = true }
        let reports = (try? files.loadReports()) ?? []
        let problem = files.readOnlyReason
        let retention = Self.retention(environment: environment, home: home)
        let lastSources = files.loadLastSources()

        // One session per id: the copy with the latest activity wins; other months holding it are remembered to be cleaned up.
        var winner: [String: (session: CalendarSession, month: String)] = [:]
        var months: [String: Set<String>] = [:]
        for (month, list) in stored.months {
            for s in list {
                months[s.id, default: []].insert(month)
                if let best = winner[s.id], (best.session.lastActivity, best.month) >= (s.lastActivity, month) { continue }
                winner[s.id] = (s, month)
            }
        }
        var homes: [String: String] = [:]
        var strays: [String: Set<String>] = [:]
        for (id, w) in winner {
            homes[id] = w.month
            let others = (months[id] ?? []).subtracting([w.month])
            if !others.isEmpty { strays[id] = others }
        }
        locked {
            sessions = SessionBuilder.sorted(winner.values.map(\.session))
            self.homes = homes
            self.strays = strays
            failedMonths = Set(stored.failed)
            nameBook = names
            namesUnreadable = unreadable
            self.reports = reports
            filesProblem = problem
            retentionDays = retention
            if let lastSources { lastSwitches = lastSources }
            computerCache = nil
        }
    }

    /// `cleanupPeriodDays` from Claude Code's settings: how long it keeps transcripts (30 when it doesn't say).
    static func retention(environment: [String: String], home: URL) -> Int {
        let url = ClaudePaths.settingsFile(environment: environment, home: home)
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let days = (object["cleanupPeriodDays"] as? NSNumber)?.intValue, days > 0 else { return 30 }
        return days
    }

    /// Everything that is stored, oldest first (tests and the importer read it).
    var storedSessions: [CalendarSession] { locked { sessions } }
    var savedReports: [WeekReport] { locked { reports } }
    var switches: SourceSwitches { locked { lastSwitches } }
    var currentFiles: CalendarFiles { locked { files } }

    /// The computer every query uses; rebuilt only when the stored state changes.
    func computer() -> WeekComputer {
        locked {
            if let computerCache { return computerCache }
            let made = WeekComputer(sessions: sessions, names: nameBook, reports: reports, calendar: _calendar,
                                    retentionDays: retentionDays, problems: currentProblems(), namesUnreadable: namesUnreadable)
            computerCache = made
            return made
        }
    }

    /// Callers hold the lock.
    private func currentProblems() -> [CalendarProblem] {
        var all: [CalendarProblem] = []
        if let filesProblem { all.append(filesProblem) }
        if namesUnreadable { all.append(Self.namesProblem) }
        all += refreshProblems
        return all
    }

    static let namesProblem = CalendarProblem(id: WeekComputer.namesUnreadableID, title: "Names & tags couldn’t be read",
                                              detail: "Titles are hidden until they can be. Tidemark won’t write over the file.")

    /// `switches` (tests) sets what the store believes the last refresh ran with, without saving it.
    func setRefreshProblems(_ problems: [CalendarProblem], switches: SourceSwitches? = nil) {
        locked {
            refreshProblems = problems
            if let switches { lastSwitches = switches }
            retentionDays = Self.retention(environment: environment, home: home)
            computerCache = nil
        }
    }

    private func updateFilesProblem() {
        let problem = currentFiles.readOnlyReason
        locked {
            filesProblem = problem
            computerCache = nil
        }
    }

    // MARK: Saving sessions

    /// What `absorb` did: the first write error, and whether it dropped the work because Delete all ran meanwhile.
    struct Absorbed {
        var error: Error?
        var dropped = false
    }

    /// Puts `changed` into the store: each replaces the stored session with the same id, new ones are added,
    /// and every stored session not named here stays (Claude Code deletes transcripts after 30 days, ES §7).
    /// A session lives in the file of its first block's month; one refreshed into another month moves there and its old
    /// file is rewritten without it. A session not refreshed stays in the file it came from, whatever the time zone is now.
    /// A month that couldn't be read when the calendar loaded, and a calendar from a newer version, are not written; the
    /// rest still is. The cached state is updated either way, so the window shows the new sessions. Returns the first write error.
    @discardableResult
    func absorb(_ changed: [CalendarSession]) -> Error? {
        serialized { absorbLocked(changed, generation: nil, base: nil).error }
    }

    /// Like `absorb`, but throws the first write error (for callers that report it, and for tests).
    func absorb(_ changed: [CalendarSession], throwing: Bool) throws {
        if let error = absorb(changed) { throw error }
    }

    /// The writer's turn must be held. `generation` and `base` come from a refresh: the work is dropped when Delete all ran since
    /// it started, and a session someone else changed since `base` is joined with the refreshed one instead of replaced.
    func absorbLocked(_ changed: [CalendarSession], generation expected: Int?, base: [String: CalendarSession]?) -> Absorbed {
        let state = locked { (generation: generation, current: sessions, homes: homes, strays: strays, failed: failedMonths, calendar: _calendar, files: files) }
        if let expected, expected != state.generation { return Absorbed(dropped: true) }
        let cal = state.calendar
        let currentByID = Dictionary(state.current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let incoming: [CalendarSession] = changed.map { s in
            guard let base, let now = currentByID[s.id], now != base[s.id] else { return s }
            return Self.reconcile(now, s)
        }
        let merged = SessionBuilder.sorted(CalendarFiles.merge(stored: state.current, refreshed: incoming))
        let mergedByID = Dictionary(merged.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        beforeWrite?()
        var newHomes = state.homes
        var months = Set<String>()
        for s in incoming {
            guard let m = mergedByID[s.id] else { continue }
            let month = CalendarFiles.month(of: m, calendar: cal)
            newHomes[s.id] = month
            months.insert(month)
            if let old = state.homes[s.id] { months.insert(old) }
            months.formUnion(state.strays[s.id] ?? [])
        }
        for s in merged where newHomes[s.id] == nil { newHomes[s.id] = CalendarFiles.month(of: s, calendar: cal) }

        var firstError: Error?
        var written = Set<String>()
        for month in months.sorted() {
            if state.failed.contains(month) {
                // Kept as it was; the sessions stay in memory, and the caller learns they weren't saved.
                if firstError == nil { firstError = CalendarFilesError.unreadable(file: "\(month).json") }
                continue
            }
            let inMonth = merged.filter { newHomes[$0.id] == month }
            if inMonth.isEmpty, !FileManager.default.fileExists(atPath: folder.appendingPathComponent("sessions/\(month).json").path) { written.insert(month); continue }
            do { try state.files.saveMonth(month, inMonth); written.insert(month) } catch { if firstError == nil { firstError = error } }
        }
        var newStrays = state.strays
        for s in incoming {
            let left = (months.intersection((state.strays[s.id] ?? []).union(state.homes[s.id].map { [$0] } ?? []))).subtracting(written).subtracting([newHomes[s.id] ?? ""])
            newStrays[s.id] = left.isEmpty ? nil : left
        }
        locked {
            sessions = merged
            homes = newHomes
            strays = newStrays
            computerCache = nil
        }
        updateFilesProblem()
        return Absorbed(error: firstError)
    }

    /// A refreshed session joined with a copy that changed while the refresh ran (an import): nothing of either is lost.
    static func reconcile(_ current: CalendarSession, _ refreshed: CalendarSession) -> CalendarSession {
        var s = combine(current, refreshed)
        var commits = current.commits
        for c in refreshed.commits {
            if let i = commits.firstIndex(where: { $0.repo == c.repo && CommitMatcher.sameCommit($0.sha, c.sha) }) {
                if commits[i].sha.count < c.sha.count { commits[i] = c }
            } else {
                commits.append(c)
            }
        }
        s.commits = commits.sorted { ($0.time, $0.sha) < ($1.time, $1.sha) }
        return s
    }

    /// The refresh already running, or the one `make` starts: refreshes run one at a time.
    func startOrJoinRefresh(_ make: () -> Task<RefreshSummary, Never>) -> Task<RefreshSummary, Never> {
        locked {
            if let running { return running }
            let task = make()
            running = task
            return task
        }
    }

    func finishRefresh() { locked { running = nil } }

    var currentGeneration: Int { locked { generation } }

    /// A refresh's save, as one turn: the sessions, then (only if every write worked) when it finished and which switches it
    /// ran with. Dropped whole when Delete all ran since `generation`.
    func commitRefresh(_ changed: [CalendarSession], base: [String: CalendarSession], generation: Int, now: Date, sources: SourceSwitches) -> Absorbed {
        serialized {
            let result = absorbLocked(changed, generation: generation, base: base)
            if result.dropped || result.error != nil { return result }
            do {
                try currentFiles.saveLastRefresh(now, sources: sources)
                locked { lastSwitches = sources }
            } catch {
                return Absorbed(error: error)
            }
            updateFilesProblem()
            return result
        }
    }

    func lastRefresh() -> Date? { currentFiles.loadLastRefresh() }

    // MARK: Names, reports, problems

    public var names: NameBook { locked { nameBook } }

    public var problems: [CalendarProblem] { locked { currentProblems() } }

    @discardableResult
    public func apply(_ change: NameChange) throws -> NameBook {
        try serialized {
            let updated = try names.apply(change)
            try setNamesLocked(updated)
            return updated
        }
    }

    public func replaceNames(_ book: NameBook) throws {
        try serialized { try setNamesLocked(book) }
    }

    /// The writer's turn must be held.
    func setNamesLocked(_ book: NameBook) throws {
        do {
            try currentFiles.saveNames(book)
        } catch {
            updateFilesProblem()
            throw error
        }
        locked {
            nameBook = book
            namesUnreadable = false
            computerCache = nil
        }
        updateFilesProblem()
    }

    public func save(_ report: WeekReport) throws {
        try serialized {
            try saveReportsLocked(savedReports.filter { $0.weekStart != report.weekStart } + [report])
        }
    }

    /// The writer's turn must be held.
    func saveReportsLocked(_ list: [WeekReport]) throws {
        let updated = list.sorted { $0.weekStart < $1.weekStart }
        do { try currentFiles.saveReports(updated) } catch { updateFilesProblem(); throw error }
        locked {
            reports = updated
            computerCache = nil
        }
        updateFilesProblem()
    }

    // MARK: Queries

    public func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel {
        computer().week(containing: day, weekStart: weekStart, now: now)
    }

    public func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel {
        computer().month(containing: day, weekStart: weekStart, now: now)
    }

    public func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        computer().trends(endingWith: day, count: count, grouping: grouping, weekStart: weekStart, now: now)
    }

    public func nameRows(_ kind: NameKind, now: Date) -> [NameRow] {
        computer().nameRows(kind, now: now)
    }

    public func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary {
        computer().weekSummary(containing: day, weekStart: weekStart, now: now)
    }

    // MARK: Delete

    /// Removes everything the calendar keeps under its folder (sessions, names, reports, backups, imported copies)
    /// except `import-source/`, the copied originals of an old calendar, which stay until Uninstall.
    public func deleteAll() throws {
        try serialized {
            // A refresh that started before this drops what it read; it never recreates a file.
            locked { generation += 1 }
            let fm = FileManager.default
            if fm.fileExists(atPath: folder.path) {
                for name in try fm.contentsOfDirectory(atPath: folder.path) where name != Self.importSourceName {
                    try fm.removeItem(at: folder.appendingPathComponent(name))
                }
            }
            locked {
                files = CalendarFiles(folder: folder, calendar: _calendar)
                sessions = []
                homes = [:]
                strays = [:]
                failedMonths = []
                nameBook = NameBook()
                namesUnreadable = false
                reports = []
                filesProblem = nil
                refreshProblems = []
                lastSwitches = SourceSwitches()
                computerCache = nil
            }
        }
    }

    static let importSourceName = "import-source"

    // MARK: Cowork log

    public func lastCoworkLogEntry(in folder: URL) -> Date? {
        CoworkLogReader.read(folder: folder, since: nil, keepFirstMessage: false).sessions.compactMap { $0.times.max() }.max()
    }
}
