import Foundation
import Testing
@testable import TidemarkCore

/// A runner that must never be asked for anything: store tests that don't refresh don't run programs.
final class NoRunner: ProcessRunning, @unchecked Sendable {
    var calls = 0
    func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL)
        -> (status: Int32, out: Data, err: Data)? {
        calls += 1
        return nil
    }
}

func storeSession(_ id: String, start: Date, minutes: Double = 30, root: String = "/Users/you/code/tide-tables",
                  title: String? = nil, origin: SessionOrigin = .claudeCode, isGit: Bool = true) -> CalendarSession {
    CalendarSession(id: id, origin: origin, title: title, root: root, isGit: isGit,
                    blocks: [Block(start: start, end: start.addingTimeInterval(minutes * 60))],
                    lastActivity: start.addingTimeInterval(minutes * 60))
}

/// A flag that can be set once, from any thread.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false
    /// True the first time only.
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return set }
    func setOnce() -> Bool { lock.lock(); defer { lock.unlock() }; defer { set = true }; return !set }
}

@Suite struct StoreTests {
    private func store(_ folder: URL = tempDir(), home: URL = fakeHome(), runner: ProcessRunning = NoRunner()) -> (CalendarStore, URL) {
        (CalendarStore(folder: folder, home: home, environment: [:], runner: runner, calendar: newYork), folder)
    }

    private func read(_ folder: URL, _ path: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(path)) }

    @Test func aNewStoreStartsEmptyAndWritesNothing() {
        let (s, folder) = store()
        #expect(s.storedSessions.isEmpty)
        #expect(s.problems.isEmpty)
        #expect(s.names == NameBook())
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("format.json").path))
    }

    @Test func whatWasSavedComesBackInANewStore() throws {
        let (s, folder) = store()
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9), title: "Chart work")])
        let (again, _) = store(folder)
        #expect(again.storedSessions.map(\.id) == ["sess-tide-0001"])
        #expect(again.storedSessions.first?.title == "Chart work")
    }

    @Test func refreshNeverDropsSessionsWhoseFileIsGone() throws {
        let (s, folder) = store()
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9)),
                      storeSession("sess-tide-0002", start: local(2026, 10, 7, 9))])
        // Claude Code deleted the first transcript: a later refresh only finds the second.
        try s.absorb([storeSession("sess-tide-0002", start: local(2026, 10, 7, 9), minutes: 45)])
        #expect(Set(s.storedSessions.map(\.id)) == ["sess-tide-0001", "sess-tide-0002"])
        let (again, _) = store(folder)
        #expect(Set(again.storedSessions.map(\.id)) == ["sess-tide-0001", "sess-tide-0002"])
        #expect(again.storedSessions.first { $0.id == "sess-tide-0002" }?.blocks.first?.end == local(2026, 10, 7, 9, 45))
    }

    @Test func sessionStoredUnderItsFirstMonth() throws {
        let (s, folder) = store()
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 9, 30, 23), minutes: 120)])
        #expect(read(folder, "sessions/2026-09.json") != nil)
        #expect(read(folder, "sessions/2026-10.json") == nil)
    }

    @Test func aSessionWhoseFirstMonthChangesMovesItsCopy() throws {
        let (s, folder) = store()
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 2, 9)), storeSession("sess-tide-0002", start: local(2026, 10, 3, 9))])
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 9, 29, 9), minutes: 30)])
        let (again, _) = store(folder)
        #expect(again.storedSessions.filter { $0.id == "sess-tide-0001" }.count == 1)
        let files = CalendarFiles(folder: folder, calendar: newYork)
        #expect(try files.loadMonth("2026-09").map(\.id) == ["sess-tide-0001"])
        #expect(try files.loadMonth("2026-10").map(\.id) == ["sess-tide-0002"])
    }

    @Test func corruptMonthIsNeverWrittenOver() throws {
        let folder = tempDir()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let garbage = Data("not json {{{".utf8)
        try garbage.write(to: folder.appendingPathComponent("sessions/2026-10.json"))
        let (s, _) = store(folder)
        #expect(!s.problems.isEmpty)
        _ = s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9)), storeSession("sess-tide-0002", start: local(2026, 9, 6, 9))])
        #expect(read(folder, "sessions/2026-10.json") == garbage)
        #expect(read(folder, "sessions/2026-09.json") != nil)
        #expect(s.problems.first?.title == "A calendar file couldn’t be read")
    }

    private var london: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func fileCopies(_ folder: URL, _ id: String) throws -> Int {
        let files = CalendarFiles(folder: folder, calendar: newYork)
        return try files.storedMonths().reduce(0) { $0 + (try files.loadMonth($1).filter { $0.id == id }.count) }
    }

    @Test func aTimeZoneChangeNeverDoublesASession() throws {
        let folder = tempDir()
        let (s, _) = store(folder)
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 9, 30, 23, 30), minutes: 60),
                      storeSession("sess-tide-0002", start: local(2026, 10, 6, 9))], throwing: true)
        #expect(read(folder, "sessions/2026-09.json") != nil)
        // The Mac moves to London, where that session started on 1 October.
        let moved = CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: london)
        try moved.absorb([storeSession("sess-tide-0003", start: local(2026, 10, 8, 9))], throwing: true)
        #expect(try fileCopies(folder, "sess-tide-0001") == 1)   // an untouched session stays in the file it came from
        try moved.absorb([storeSession("sess-tide-0001", start: local(2026, 9, 30, 23, 30), minutes: 90)], throwing: true)
        #expect(try fileCopies(folder, "sess-tide-0001") == 1)   // a refreshed one moves, and leaves no copy behind
        let again = CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: london)
        #expect(again.storedSessions.map(\.id).sorted() == ["sess-tide-0001", "sess-tide-0002", "sess-tide-0003"])
        #expect(again.storedSessions.first { $0.id == "sess-tide-0001" }?.blocks.first?.end == local(2026, 10, 1, 1, 0))
    }

    @Test func twoCopiesOnDiskLoadAsTheNewerOneAndAreCleanedUp() throws {
        let folder = tempDir()
        let files = CalendarFiles(folder: folder, calendar: newYork)
        try files.saveMonth("2026-09", [storeSession("sess-tide-0001", start: local(2026, 9, 30, 23, 30), minutes: 90)])
        try files.saveMonth("2026-10", [storeSession("sess-tide-0001", start: local(2026, 9, 30, 23, 30), minutes: 30)])
        let (s, _) = store(folder)
        #expect(s.storedSessions.count == 1)
        #expect(s.storedSessions[0].lastActivity == local(2026, 10, 1, 1))   // the 90-minute copy
        try s.absorb([storeSession("sess-tide-0009", start: local(2026, 10, 9, 9))], throwing: true)
        #expect(store(folder).0.storedSessions.filter { $0.id == "sess-tide-0001" }.count == 1)
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 9, 30, 23, 30), minutes: 100)], throwing: true)
        #expect(try fileCopies(folder, "sess-tide-0001") == 1)
        #expect(store(folder).0.storedSessions.first { $0.id == "sess-tide-0001" }?.lastActivity == local(2026, 10, 1, 1, 10))
    }

    @Test func theStoreFollowsTheTimeZoneItIsGiven() {
        let (s, _) = store()
        let before = s.week(containing: local(2026, 10, 7), weekStart: .monday, now: local(2026, 11, 1))
        #expect(before.days[0] == local(2026, 10, 5))
        s.useCalendar(london)
        let after = s.week(containing: local(2026, 10, 7), weekStart: .monday, now: local(2026, 11, 1))
        #expect(after.days[0] == london.date(from: DateComponents(year: 2026, month: 10, day: 5)))
    }

    @Test func writersTakeTurnsSoNothingIsLost() throws {
        let (s, folder) = store()
        let hooked = Flag()
        let done = DispatchSemaphore(value: 0)
        let finished = Flag()
        s.beforeWrite = { [unowned s] in
            guard hooked.setOnce() else { return }
            // While this write holds its turn, another writer starts and waits for it.
            DispatchQueue.global().async {
                _ = s.absorb([storeSession("sess-tide-0002", start: local(2026, 10, 7, 9))])
                try? s.save(WeekReport(weekStart: "2026-10-05", lines: ["x"], author: .tidemark, written: local(2026, 10, 8)))
                _ = finished.setOnce()
                done.signal()
            }
            // Wait until the other writer is queued behind this one (or, were writes not serialized, has already finished).
            while s.queuedWriters == 0 && !finished.isSet { sched_yield() }
        }
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9))], throwing: true)
        done.wait()
        #expect(Set(s.storedSessions.map(\.id)) == ["sess-tide-0001", "sess-tide-0002"])
        #expect(Set(store(folder).0.storedSessions.map(\.id)) == ["sess-tide-0001", "sess-tide-0002"])
        #expect(s.savedReports.count == 1)
    }

    @Test func aMonthThatFailedToLoadStaysReadOnlyEvenIfItReadsLaterOn() throws {
        let folder = tempDir()
        let files = CalendarFiles(folder: folder, calendar: newYork)
        try files.saveMonth("2026-10", [storeSession("sess-tide-0001", start: local(2026, 10, 5, 9))])
        let good = try #require(read(folder, "sessions/2026-10.json"))
        try Data("not json {{{".utf8).write(to: folder.appendingPathComponent("sessions/2026-10.json"))
        let (s, _) = store(folder)        // can't read October now (a transient error would look the same)
        try good.write(to: folder.appendingPathComponent("sessions/2026-10.json"))   // and it reads fine a moment later
        _ = s.absorb([storeSession("sess-tide-0002", start: local(2026, 10, 6, 9)), storeSession("sess-tide-0003", start: local(2026, 9, 6, 9))])
        #expect(read(folder, "sessions/2026-10.json") == good)   // not rewritten from a cache that lacks sess-tide-0001
        #expect(read(folder, "sessions/2026-09.json") != nil)
        #expect(Set(s.storedSessions.map(\.id)) == ["sess-tide-0002", "sess-tide-0003"])   // the window still shows what it has
    }

    @Test func aNewerMonthStillShowsWhatItHolds() throws {
        let folder = tempDir()
        let files = CalendarFiles(folder: folder, calendar: newYork)
        try files.saveMonth("2026-10", [storeSession("sess-tide-0001", start: local(2026, 10, 5, 9))])
        let raw = try #require(read(folder, "sessions/2026-10.json"))
        let text = String(decoding: raw, as: UTF8.self)
        try Data(text.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 2"#).utf8).write(to: folder.appendingPathComponent("sessions/2026-10.json"))
        let (s, _) = store(folder)
        #expect(s.storedSessions.map(\.id) == ["sess-tide-0001"])
        #expect(s.problems.map(\.title) == ["Tidemark’s calendar was saved by a newer version"])
        _ = s.absorb([storeSession("sess-tide-0002", start: local(2026, 10, 6, 9))])
        #expect(try String(contentsOf: folder.appendingPathComponent("sessions/2026-10.json"), encoding: .utf8) == text.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 2"#))
    }

    @Test func newerFormatIsReadOnly() throws {
        let folder = tempDir()
        try Data(#"{"format":"tidemark-calendar","version":2}"#.utf8).write(to: folder.appendingPathComponent("format.json"))
        let (s, _) = store(folder)
        #expect(s.problems.map(\.title) == ["Tidemark’s calendar was saved by a newer version"])
        _ = s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9))])
        #expect(read(folder, "sessions/2026-10.json") == nil)
        #expect(throws: (any Error).self) { try s.save(WeekReport(weekStart: "2026-10-05", lines: ["x"], author: .tidemark, written: local(2026, 10, 7))) }
        #expect(throws: (any Error).self) { _ = try s.apply(NameChange(kind: .projects, key: "tide-tables", name: .some("Tides"))) }
    }

    @Test func namesAndReportsPersist() throws {
        let (s, folder) = store()
        let book = try s.apply(NameChange(kind: .projects, key: "tide-tables", name: .some("Tide Tables"), tags: ["work"]))
        #expect(book.projects["tide-tables"]?.name == "Tide Tables")
        try s.save(WeekReport(weekStart: "2026-10-05", lines: ["One", "Two", "Three"], author: .tidemark, written: local(2026, 10, 7)))
        try s.save(WeekReport(weekStart: "2026-10-05", lines: ["New"], author: .tidemark, written: local(2026, 10, 8)))
        let (again, _) = store(folder)
        #expect(again.names.projects["tide-tables"]?.tags == ["work"])
        #expect(again.savedReports.map(\.lines) == [["New"]])
        try again.replaceNames(NameBook())
        #expect(again.names == NameBook())
    }

    @Test func aBadNameIsRefused() {
        let (s, _) = store()
        #expect(throws: NameBookError.badKey) { _ = try s.apply(NameChange(kind: .sessions, key: "*", name: .some("All"))) }
    }

    @Test func aStoreInAnEmptyFolderHasNoProblems() {
        // CalendarStores.live is the same store pointed at the support folder; tests never build it (it would use real paths).
        let (s, _) = store(tempDir().appendingPathComponent("calendar"))
        #expect(s.problems.isEmpty)
        #expect(s.storedSessions.isEmpty)
    }
}
