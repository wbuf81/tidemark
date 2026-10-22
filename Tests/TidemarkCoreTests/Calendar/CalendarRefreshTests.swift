import Foundation
import Testing
@testable import TidemarkCore

@Suite struct CalendarRefreshTests {
    /// A pretend `git` and `xcode-select`: no program ever starts.
    private final class FakeRunner: ProcessRunning, @unchecked Sendable {
        let lock = NSLock()
        private(set) var calls: [[String]] = []
        var tools = true
        var delay: TimeInterval = 0
        var repo = "/Users/you/code/tide-tables"
        var log = ""
        /// Called (once) when the first repo is looked up, on the refresh's own thread: lets a test act mid-refresh.
        var onFirstRepoLookup: (() -> Void)?
        func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL)
            -> (status: Int32, out: Data, err: Data)? {
            lock.lock(); calls.append([executable.path] + args); lock.unlock()
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            func text(_ s: String) -> (status: Int32, out: Data, err: Data) { (0, Data(s.utf8), Data()) }
            if executable.path == "/usr/bin/xcode-select" { return tools ? text("/Library/Developer/CommandLineTools\n") : (1, Data(), Data()) }
            if args.contains("rev-parse") {
                lock.lock(); let hook = onFirstRepoLookup; onFirstRepoLookup = nil; lock.unlock()
                hook?()
                return text(repo + "/.git\n")
            }
            if args.contains("log") { return text(log) }
            if args.contains("config") { return text("you@example.com\n") }
            return nil
        }
        var gitCalls: Int { lock.lock(); defer { lock.unlock() }; return calls.filter { $0.first == "/usr/bin/git" }.count }
        var toolCalls: Int { lock.lock(); defer { lock.unlock() }; return calls.filter { $0.first == "/usr/bin/xcode-select" }.count }
    }

    private let now = local(2026, 10, 21, 12)

    private func line(_ time: String, cwd: String = "/Users/you/code/tide-tables", text: String? = nil, tool: String? = nil) -> String {
        if let tool {
            return #"{"type":"user","cwd":"\#(cwd)","timestamp":"\#(time)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"\#(tool)"}]}}"#
        }
        let message = text.map { #","origin":{"kind":"human"},"message":{"role":"user","content":"\#($0)"}"# } ?? #","message":{"role":"assistant","content":"ok"}"#
        let type = text == nil ? "assistant" : "user"
        return #"{"type":"\#(type)","cwd":"\#(cwd)","timestamp":"\#(time)"\#(message)}"#
    }

    @discardableResult
    private func write(_ projects: URL, _ id: String, _ lines: [String], folder: String = "-Users-you-code-tide-tables", modified: Date? = nil) -> URL {
        let dir = projects.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id).jsonl")
        try? Data(lines.joined(separator: "\n").utf8).write(to: url)
        if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    private func setup(runner: FakeRunner = FakeRunner(), environment: [String: String] = [:], home: URL = fakeHome()) -> (CalendarStore, URL, FakeRunner) {
        let s = CalendarStore(folder: tempDir(), home: home, environment: environment, runner: runner, calendar: newYork)
        return (s, home.appendingPathComponent(".claude/projects"), runner)
    }

    private let old = local(2026, 10, 10)

    @Test func firstRefreshReadsEverything() async {
        let (s, projects, runner) = setup()
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "Add the chart"), line("2026-10-12T13:20:00Z")], modified: old)
        write(projects, "sess-tide-0002", [line("2026-10-13T13:00:00Z", text: "Fix the legend")], modified: old)
        let summary = await s.refresh(SourceSwitches(), now: now)
        #expect(summary.sessionsRead == 2)
        #expect(summary.sessionsChanged == 2)
        #expect(summary.problems.isEmpty)
        let stored = s.storedSessions
        #expect(stored.map(\.id) == ["sess-tide-0001", "sess-tide-0002"])
        #expect(stored[0].root == "/Users/you/code/tide-tables")
        #expect(stored[0].isGit)
        #expect(stored[0].blocks == [Block(start: utc("2026-10-12T13:00:00Z"), end: utc("2026-10-12T13:20:00Z"))])
        #expect(stored[0].firstMessage == nil)   // first messages are off by default
        #expect(s.currentFiles.loadLastRefresh() == now)
        #expect(runner.gitCalls > 0)
    }

    @Test func secondRefreshReadsOnlyChangedFiles() async {
        let (s, projects, _) = setup()
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "Add the chart")], modified: old)
        write(projects, "sess-tide-0002", [line("2026-10-13T13:00:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 20, 12))
        let again = await s.refresh(SourceSwitches(), now: now)
        #expect(again.sessionsRead == 0)
        #expect(again.sessionsChanged == 0)
        // One transcript grew after the last refresh.
        write(projects, "sess-tide-0002", [line("2026-10-13T13:00:00Z"), line("2026-10-21T09:00:00Z")], modified: local(2026, 10, 21, 9))
        let third = await s.refresh(SourceSwitches(), now: local(2026, 10, 21, 13))
        #expect(third.sessionsRead == 1)
        #expect(third.sessionsChanged == 1)
        #expect(s.storedSessions.first { $0.id == "sess-tide-0002" }?.blocks.count == 2)
    }

    @Test func firstMessagesSwitchOffDropsThemFromTheStore() async {
        let (s, projects, _) = setup()
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "Add the chart export")], modified: old)
        var on = SourceSwitches()
        on.firstMessages = true
        _ = await s.refresh(on, now: local(2026, 10, 20))
        #expect(s.storedSessions.first?.firstMessage == "Add the chart export")
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.first?.firstMessage == nil)
        #expect(CalendarStore(folder: s.folder, home: s.home, environment: [:], runner: FakeRunner(), calendar: newYork).storedSessions.first?.firstMessage == nil)
    }

    @Test func coworkOffReadsNoCowork() async throws {
        let home = fakeHome()
        let desktop = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
        try FileManager.default.createDirectory(at: desktop.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureURL("local-agent-mode-sessions"), to: desktop)
        let (s, _, _) = setup(home: home)
        let summary = await s.refresh(SourceSwitches(), now: now)
        #expect(summary.sessionsRead == 0)
        #expect(s.storedSessions.isEmpty)

        var on = SourceSwitches()
        on.coworkLogFolder = fixtureURL("cowork-log").path
        on.desktopCowork = true
        let withCowork = await s.refresh(on, now: now)
        #expect(withCowork.sessionsRead > 0)
        let cowork = s.storedSessions.filter { $0.origin == .cowork }
        #expect(!cowork.isEmpty)
        #expect(cowork.allSatisfy { $0.root == "Cowork" && !$0.isGit })
        #expect(s.storedSessions.contains { $0.logged })
    }

    @Test func concurrentRefreshesRunOnce() async {
        let runner = FakeRunner()
        runner.delay = 0.25
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")], modified: old)
        write(projects, "sess-tide-0002", [line("2026-10-13T13:00:00Z")], modified: old)
        async let first = s.refresh(SourceSwitches(), now: now)
        async let second = s.refresh(SourceSwitches(), now: now)
        let (a, b) = await (first, second)
        #expect(a == b)
        #expect(a.sessionsChanged == 2)
        #expect(runner.toolCalls == 2)   // one reader and one locator for the one refresh that ran
    }

    @Test func noProjectsFolderIsAProblemNotACrash() async throws {
        let home = tempDir()
        let (s, _, _) = setup(home: home)
        let summary = await s.refresh(SourceSwitches(), now: now)
        #expect(summary.sessionsRead == 0)
        #expect(summary.problems == [CalendarProblem(id: "no-claude-code", title: "Claude Code hasn’t run on this Mac yet",
                                                     detail: "Your week fills in after your first session.")])
        #expect(s.problems.contains { $0.title == "Claude Code hasn’t run on this Mac yet" })
        // The problem goes away once there is something to read.
        let projects = home.appendingPathComponent(".claude/projects")
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")])
        let later = await s.refresh(SourceSwitches(), now: now)
        #expect(later.problems.isEmpty)
        #expect(s.problems.isEmpty)
    }

    @Test func honoursClaudeConfigDir() async {
        let home = fakeHome()
        let config = tempDir()
        write(config.appendingPathComponent("projects"), "sess-tide-0001", [line("2026-10-12T13:00:00Z")])
        write(home.appendingPathComponent(".claude/projects"), "sess-tide-9999", [line("2026-10-12T13:00:00Z")])
        let (s, _, _) = setup(environment: ["CLAUDE_CONFIG_DIR": config.path], home: home)
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.map(\.id) == ["sess-tide-0001"])
    }

    @Test func noDeveloperToolsLeavesCommitsOut() async {
        let runner = FakeRunner()
        runner.tools = false
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")])
        let summary = await s.refresh(SourceSwitches(), now: now)
        #expect(summary.problems == [CalendarProblem(id: "no-git", title: "Git isn’t installed",
                                                     detail: "Commits are left out. Install the Command Line Tools to add them.")])
        #expect(runner.gitCalls == 0)
        #expect(s.storedSessions.first?.root == "/Users/you/code/tide-tables")
        #expect(s.storedSessions.first?.isGit == false)
    }

    @Test func gitSwitchOffRunsNothing() async {
        let (s, projects, runner) = setup()
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")])
        var off = SourceSwitches()
        off.git = false
        let summary = await s.refresh(off, now: now)
        #expect(summary.problems.isEmpty)
        #expect(runner.calls.isEmpty)
        #expect(s.storedSessions.count == 1)
    }

    @Test func commitsAreMatchedAndKept() async {
        let runner = FakeRunner()
        runner.log = "\u{1e}9eba1460000000000000000000000000000000aa\u{1f}2026-10-12T13:15:00Z\u{1f}you@example.com\u{1f}Add chart export\n\nSources/Chart.swift\n"
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "go"), line("2026-10-12T13:20:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 20))
        #expect(s.storedSessions.first?.commits.map(\.subject) == ["Add chart export"])
        #expect(s.storedSessions.first?.commits.first?.repo == "/Users/you/code/tide-tables")
        // The same commit read again isn't added twice, and the stored one stays when the log no longer lists it.
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "go"), line("2026-10-12T13:20:00Z"), line("2026-10-21T08:00:00Z")], modified: local(2026, 10, 21, 8))
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.first?.commits.count == 1)
        runner.log = ""
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "go")], modified: local(2026, 10, 21, 10))
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 21, 13))
        #expect(s.storedSessions.first?.commits.count == 1)
    }

    @Test func anImportedShortShaDoesNotDoubleAfterARefresh() async throws {
        let runner = FakeRunner()
        runner.log = "\u{1e}9eba1460000000000000000000000000000000aa\u{1f}2026-10-12T13:15:00Z\u{1f}you@example.com\u{1f}Add chart export\n\nSources/Chart.swift\n"
        let (s, projects, _) = setup(runner: runner)
        let tide = "/Users/you/code/tide-tables"
        try s.absorb([CalendarSession(id: "sess-tide-0001", origin: .claudeCode, title: "Chart", root: tide, isGit: true,
                                      blocks: [Block(start: utc("2026-10-12T13:00:00Z"), end: utc("2026-10-12T13:20:00Z"))],
                                      commits: [Commit(sha: "9eba146", time: utc("2026-10-12T13:20:00Z"), repo: tide, subject: "Add chart export")],
                                      lastActivity: utc("2026-10-12T13:20:00Z"))], throwing: true)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "go"), line("2026-10-12T13:20:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: now)
        let commits = try #require(s.storedSessions.first).commits
        #expect(commits.map(\.sha) == ["9eba1460000000000000000000000000000000aa"])
        #expect(commits[0].time == utc("2026-10-12T13:15:00Z"))
        let w = s.week(containing: local(2026, 10, 12), weekStart: .monday, now: now)
        #expect(w.commits == 1 && w.commitsPerDay[0] == 1)
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.first?.commits.count == 1)
    }

    // MARK: Interleavings, with no sleeps: the fake runner acts at a known point inside the refresh.

    private func copyOfLegacy() throws -> URL {
        let copy = tempDir().appendingPathComponent("old")
        try FileManager.default.copyItem(at: fixtureURL("legacy"), to: copy)
        return copy
    }

    @Test func deleteAllDuringARefreshWins() async throws {
        let runner = FakeRunner()
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "go")], modified: old)
        try s.absorb([storeSession("sess-tide-0005", start: local(2026, 10, 6, 9))], throwing: true)
        runner.onFirstRepoLookup = { try? s.deleteAll() }
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.isEmpty)
        #expect(s.currentFiles.loadLastRefresh() == nil)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: s.folder.path)) ?? []).isEmpty)
        #expect(s.week(containing: local(2026, 10, 12), weekStart: .monday, now: now).sessions == 0)
    }

    @Test func anImportDuringARefreshKeepsBothSetsOfSessions() async throws {
        let runner = FakeRunner()
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-9001", [line("2026-10-14T13:00:00Z", text: "go")], modified: old)
        let legacy = try copyOfLegacy()
        runner.onFirstRepoLookup = { _ = try? s.importLegacy(from: legacy) }
        _ = await s.refresh(SourceSwitches(), now: now)
        let ids = Set(s.storedSessions.map(\.id))
        #expect(ids.contains("sess-tide-9001") && ids.contains("sess-tide-0001") && ids.count == 8)
        let again = CalendarStore(folder: s.folder, home: s.home, environment: [:], runner: FakeRunner(), calendar: newYork)
        #expect(Set(again.storedSessions.map(\.id)) == ids)
    }

    @Test func aSessionImportedDuringItsRefreshKeepsTheImportedPart() async throws {
        let runner = FakeRunner()
        let (s, projects, _) = setup(runner: runner)
        // The same session the old calendar knows (sess-tide-0001, 5 Oct), read again from its transcript.
        write(projects, "sess-tide-0001", [line("2026-10-05T13:00:00Z", text: "go"), line("2026-10-05T13:10:00Z")], modified: old)
        let legacy = try copyOfLegacy()
        runner.onFirstRepoLookup = { _ = try? s.importLegacy(from: legacy) }
        _ = await s.refresh(SourceSwitches(), now: now)
        let one = try #require(s.storedSessions.first { $0.id == "sess-tide-0001" })
        #expect(one.commits.map(\.subject) == ["Add chart export"])
        #expect(one.blocks.last?.end == local(2026, 10, 5, 14))   // the imported afternoon block is still there
        #expect(s.storedSessions.filter { $0.id == "sess-tide-0001" }.count == 1)
    }

    @Test func queriesNeverWaitForARefresh() async {
        let runner = FakeRunner()
        let (s, projects, _) = setup(runner: runner)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")], modified: old)
        let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0)
        runner.onFirstRepoLookup = { entered.signal(); gate.wait() }
        async let summary = s.refresh(SourceSwitches(), now: now)
        entered.wait()   // the refresh is now stuck inside its work
        let w = s.week(containing: local(2026, 10, 12), weekStart: .monday, now: now)
        _ = s.month(containing: local(2026, 10, 12), weekStart: .monday, now: now)
        _ = s.nameRows(.projects, now: now)
        #expect(w.sessions == 0 && s.problems.isEmpty)
        gate.signal()
        _ = await summary
        #expect(s.storedSessions.count == 1)
    }

    @Test func aDeletedTranscriptStaysThroughAFullReadRefresh() async {
        let (s, projects, _) = setup()
        let gone = write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")], modified: old)
        write(projects, "sess-tide-0002", [line("2026-10-13T13:00:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 20))
        try? FileManager.default.removeItem(at: gone)
        var on = SourceSwitches()
        on.firstMessages = true   // turning a source on reads everything again
        let summary = await s.refresh(on, now: now)
        #expect(summary.sessionsRead == 1)
        #expect(Set(s.storedSessions.map(\.id)) == ["sess-tide-0001", "sess-tide-0002"])
        #expect(Set(CalendarStore(folder: s.folder, home: s.home, environment: [:], runner: FakeRunner(), calendar: newYork).storedSessions.map(\.id)).count == 2)
    }

    @Test func aCorruptMonthIsLeftAloneByARefreshAndTheRefreshIsNotMarkedDone() async throws {
        let (s0, projects, _) = setup()
        let folder = s0.folder
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let garbage = Data("not json {{{".utf8)
        try garbage.write(to: folder.appendingPathComponent("sessions/2026-10.json"))
        let s = CalendarStore(folder: folder, home: s0.home, environment: [:], runner: FakeRunner(), calendar: newYork)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")], modified: old)
        write(projects, "sess-tide-0002", [line("2026-09-12T13:00:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect((try? Data(contentsOf: folder.appendingPathComponent("sessions/2026-10.json"))) == garbage)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sessions/2026-09.json").path))
        #expect(s.currentFiles.loadLastRefresh() == nil)   // October was not saved, so the next refresh reads it again
        #expect(s.problems.contains { $0.title == "A calendar file couldn’t be read" })
    }

    @Test func aSourceSwitchedOnAfterARelaunchIsReadInFull() async {
        let home = fakeHome()
        let (s, projects, _) = setup(home: home)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")], modified: old)
        var off = SourceSwitches()
        off.claudeCode = false
        _ = await s.refresh(off, now: local(2026, 10, 19))   // Claude Code is off for a while
        #expect(s.storedSessions.isEmpty)
        // The app relaunches, then Claude Code is turned on: the old transcript is older than the last refresh.
        let again = CalendarStore(folder: s.folder, home: home, environment: [:], runner: FakeRunner(), calendar: newYork)
        let summary = await again.refresh(SourceSwitches(), now: now)
        #expect(summary.sessionsRead == 1)
        #expect(again.storedSessions.map(\.id) == ["sess-tide-0001"])
    }

    @Test func firstMessagesTurnedOnAreFilledInForOldSessions() async {
        let home = fakeHome()
        let (s, projects, _) = setup(home: home)
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z", text: "Add the chart export")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 19))
        #expect(s.storedSessions.first?.firstMessage == nil)
        let again = CalendarStore(folder: s.folder, home: home, environment: [:], runner: FakeRunner(), calendar: newYork)
        var on = SourceSwitches()
        on.firstMessages = true
        _ = await again.refresh(on, now: now)
        #expect(again.storedSessions.first?.firstMessage == "Add the chart export")
    }

    @Test func aSessionNeverShrinksWhenItsTranscriptDoes() async {
        let (s, projects, _) = setup()
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z"), line("2026-10-12T14:00:00Z"), line("2026-10-12T14:20:00Z")], modified: old)
        _ = await s.refresh(SourceSwitches(), now: local(2026, 10, 20))
        write(projects, "sess-tide-0001", [line("2026-10-12T14:10:00Z")], modified: local(2026, 10, 21, 8))
        _ = await s.refresh(SourceSwitches(), now: now)
        let blocks = s.storedSessions.first?.blocks
        #expect(blocks == [Block(start: utc("2026-10-12T13:00:00Z"), end: utc("2026-10-12T13:00:00Z")),
                           Block(start: utc("2026-10-12T14:00:00Z"), end: utc("2026-10-12T14:20:00Z"))])
    }

    @Test func tidemarksOwnReportRunsAreNotSessions() async {
        let home = fakeHome()
        let (s, projects, _) = setup(home: home)
        let own = AppIdentity.supportURL(home: home).appendingPathComponent("report").path
        write(projects, "sess-own-0001", [line("2026-10-12T13:00:00Z", cwd: own)], folder: "-report")
        write(projects, "sess-tide-0001", [line("2026-10-12T13:00:00Z")])
        _ = await s.refresh(SourceSwitches(), now: now)
        #expect(s.storedSessions.map(\.id) == ["sess-tide-0001"])
    }
}
