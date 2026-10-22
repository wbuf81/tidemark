import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ReportTests {
    // MARK: Plain report

    @Test func plainLinesForTheMockupWeek() {
        let demo = DemoCalendar.store()
        let calendar = Calendar.current
        let lastWeek = demo.week(containing: DemoCalendar.now.addingTimeInterval(-7 * 86_400), weekStart: .monday, now: DemoCalendar.now)
        #expect(lastWeek.plainReport == ["31h 20m of work across 24 sessions (17 Claude Code, 7 Cowork) and 186 commits in 4 repos.",
                                         "Most time on tide-tables (38%), then lighthouse-api (22%) and field-notes (16%).",
                                         "Busiest day Tuesday 13 Oct (9h 05m); Daily briefs ran all five weekdays."])
        #expect(PlainReport.lines(lastWeek, calendar: calendar) == lastWeek.plainReport)
        let thisWeek = demo.week(containing: DemoCalendar.now, weekStart: .monday, now: DemoCalendar.now)
        #expect(PlainReport.lines(thisWeek, calendar: calendar) == thisWeek.plainReport)
    }

    private func model(sessions: Int = 1, code: Int = 1, cowork: Int = 0, commits: Int = 1, repos: Int = 1, total: TimeInterval = 3600,
                       projects: [(String, TimeInterval)] = [("tide-tables", 3600)], perDay: [TimeInterval]? = nil,
                       items: [WeekItem] = [], calendar: Calendar = newYork, start: WeekStart = .monday) -> WeekModel {
        let days = WeekDays.midnights(containing: local(2026, 10, 7), weekStart: start, calendar: calendar)
        var w = WeekModel(start: days[0], days: days, total: total, sessions: sessions, claudeCodeSessions: code, coworkSessions: cowork,
                          commits: commits, repos: repos, perDay: perDay ?? [3600, 0, 0, 0, 0, 0, 0],
                          projects: projects.enumerated().map { ProjectTotal(name: $0.element.0, seconds: $0.element.1, sessions: 1, commits: 0, colorIndex: $0.offset) },
                          items: items)
        w.plainReport = PlainReport.lines(w, calendar: calendar)
        return w
    }

    @Test func plainSingulars() {
        let w = model()
        #expect(w.plainReport == ["1h 00m of work across 1 session (all Claude Code) and 1 commit in 1 repo.",
                                  "All of it on tide-tables.",
                                  "Busiest day Monday 5 Oct (1h 00m)."])
    }

    @Test func plainCoworkOnlyAndNoCommits() {
        let both = model(sessions: 3, code: 2, cowork: 1, commits: 0, repos: 0, total: 7200,
                         projects: [("tide-tables", 5400), ("Daily briefs", 1800)])
        #expect(both.plainReport[0] == "2h 00m of work across 3 sessions (2 Claude Code, 1 Cowork) and no commits.")
        #expect(both.plainReport[1] == "Most time on tide-tables (75%), then Daily briefs (25%).")
        let cowork = model(sessions: 2, code: 0, cowork: 2, commits: 2, repos: 2)
        #expect(cowork.plainReport[0] == "1h 00m of work across 2 sessions (all Cowork) and 2 commits in 2 repos.")
    }

    @Test func plainEmptyWeek() {
        let w = model(sessions: 0, code: 0, commits: 0, repos: 0, total: 0, projects: [], perDay: Array(repeating: 0, count: 7))
        #expect(w.plainReport == ["No sessions this week."])
    }

    @Test func plainWeekdayStreakFollowsTheRealWeekdays() {
        func item(_ day: Int, _ w: [Date]) -> WeekItem {
            WeekItem(id: "s|\(day)", sessionID: "s", day: day, title: "Brief", project: "Daily briefs", colorIndex: 0,
                     spans: [DateInterval(start: w[day], duration: 600)], seconds: 600, commits: 0, commitSubjects: [], origin: .cowork,
                     scheduled: true, noCommit: false, titlesHidden: false)
        }
        // Weeks starting on Sunday: Monday to Friday are days 1...5.
        let sunday = WeekDays.midnights(containing: local(2026, 10, 7), weekStart: .sunday, calendar: newYork)
        let all = model(projects: [("Daily briefs", 3000)], perDay: [0, 600, 600, 600, 600, 600, 0], items: (1...5).map { item($0, sunday) }, start: .sunday)
        #expect(all.plainReport[2] == "Busiest day Monday 5 Oct (0h 10m); Daily briefs ran all five weekdays.")
        let some = model(projects: [("Daily briefs", 2400)], perDay: [0, 600, 600, 600, 600, 0, 0], items: (1...4).map { item($0, sunday) }, start: .sunday)
        #expect(some.plainReport[2] == "Busiest day Monday 5 Oct (0h 10m).")
    }

    // MARK: What Claude Code is told

    private func storeWithHiddenProject() throws -> (CalendarStore, WeekModel) {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(project: "Other development")
        book.projects["Other development"] = NameEntry(hideTitles: true)
        let start = local(2026, 10, 6, 9)
        let hidden = CalendarSession(id: "sess-h", origin: .claudeCode, title: "Fix the harbor sonar parser", firstMessage: "Please fix the harbor sonar parser",
                                     root: "/Users/you/code/tide-tables", isGit: true, blocks: [Block(start: start, end: start.addingTimeInterval(3600))],
                                     commits: [Commit(sha: "aaa1111", time: start.addingTimeInterval(600), repo: "/Users/you/code/tide-tables", subject: "Patch the sonar parser", files: [])],
                                     lastActivity: start.addingTimeInterval(3600))
        let open = CalendarSession(id: "sess-o", origin: .claudeCode, title: "Chart export", firstMessage: "Add the chart export for tide charts",
                                   root: "/Users/you/code/lighthouse-api", isGit: true, blocks: [Block(start: start.addingTimeInterval(7200), end: start.addingTimeInterval(9000))],
                                   commits: [Commit(sha: "bbb2222", time: start.addingTimeInterval(7500), repo: "/Users/you/code/lighthouse-api", subject: "Add chart export", files: [])],
                                   lastActivity: start.addingTimeInterval(9000))
        let store = CalendarStore(folder: tempDir(), home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        try store.absorb([hidden, open], throwing: true)
        try store.replaceNames(book)
        return (store, store.week(containing: start, weekStart: .monday, now: local(2026, 11, 1)))
    }

    @Test func summaryHasNoHiddenTitles() throws {
        let (_, w) = try storeWithHiddenProject()
        let text = ClaudeCodeReport.summary(w, calendar: newYork)
        #expect(!text.contains("sonar"))
        #expect(text.contains("Other development"))
        #expect(text.contains("Chart export"))
        #expect(text.contains("Add chart export"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((object["week"] as? [String: String])?["start"] == "2026-10-05")
        #expect((object["days"] as? [Any])?.count == 7)
        #expect(object["hours"] as? String == "1h 30m")
    }

    @Test func summaryHasNoFirstMessagesWhenOff() throws {
        let (_, w) = try storeWithHiddenProject()
        let text = ClaudeCodeReport.summary(w, calendar: newYork)
        #expect(!text.contains("Please fix"))
        #expect(!text.contains("for tide charts"))
    }

    @Test func nothingIsSentWhenTheNamesCouldNotBeRead() async throws {
        let (_, plain) = try storeWithHiddenProject()
        var w = plain
        w.problems = [CalendarStore.namesProblem]
        let spy = SpyRunner()
        let r = ClaudeCodeReport(runner: spy, home: fakeHome(), environment: [:], candidates: [URL(fileURLWithPath: "/bin/sh")], calendar: newYork)
        let result = await r.write(w, now: local(2026, 10, 12))
        #expect(result == .failure(.failed("Names & tags couldn’t be read, so nothing is sent to Claude Code.")))
        #expect(spy.calls == 0)
    }

    private final class SpyRunner: ProcessRunning, @unchecked Sendable {
        var calls = 0
        func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL) -> (status: Int32, out: Data, err: Data)? {
            calls += 1
            return nil
        }
    }

    // MARK: Running Claude Code (a fake script or a spy; never the real one)

    private func script(_ body: String) throws -> URL {
        let dir = tempDir()
        let url = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func report(_ candidates: [URL], runner: ProcessRunning = SystemProcessRunner(), home: URL = fakeHome(), timeout: TimeInterval = 120) -> ClaudeCodeReport {
        ClaudeCodeReport(runner: runner, home: home, environment: [:], candidates: candidates, timeout: timeout, calendar: newYork)
    }

    @Test func claudeNotInstalled() async throws {
        let missing = tempDir().appendingPathComponent("claude")
        let notRunnable = tempDir().appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: notRunnable)   // no execute permission
        let r = report([missing, notRunnable, tempDir()])
        #expect(r.executable == nil)
        let (_, w) = try storeWithHiddenProject()
        #expect(await r.write(w, now: local(2026, 10, 12)) == .failure(.notInstalled))
    }

    @Test func claudeRunParsesThreeLines() async throws {
        let home = fakeHome()
        let seen = tempDir().appendingPathComponent("stdin.txt")
        let cwdFile = tempDir().appendingPathComponent("cwd.txt")
        let claude = try script("cat > '\(seen.path)'\npwd > '\(cwdFile.path)'\nprintf '\\n1. Shipped the chart export.\\n2) Most of the week went on tide-tables.\\n\\n- Next is the release notes.\\nA fourth line.\\n'")
        let r = report([tempDir().appendingPathComponent("nope"), claude], home: home)
        #expect(r.executable == claude)
        let (_, w) = try storeWithHiddenProject()
        let now = local(2026, 10, 12, 8)
        let result = await r.write(w, now: now)
        guard case .success(let saved) = result else { Issue.record("expected a report, got \(result)"); return }
        #expect(saved.lines == ["Shipped the chart export.", "Most of the week went on tide-tables.", "Next is the release notes."])
        #expect(saved.author == .claudeCode)
        #expect(saved.weekStart == "2026-10-05")
        #expect(saved.written == now)
        let told = try String(contentsOf: seen, encoding: .utf8)
        #expect(told.hasPrefix("Summarise the work log below in exactly three plain sentences."))
        #expect(told.contains("\"start\" : \"2026-10-05\""))
        #expect(!told.contains("sonar"))
        let ran = try String(contentsOf: cwdFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(fileURLWithPath: ran).resolvingSymlinksInPath().path == AppIdentity.supportURL(home: home).appendingPathComponent("report").resolvingSymlinksInPath().path)
    }

    @Test func claudeTimesOut() async throws {
        let claude = try script("exec sleep 30")
        let (_, w) = try storeWithHiddenProject()
        let started = Date()
        let result = await report([claude], timeout: 1).write(w, now: local(2026, 10, 12))
        #expect(result == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test func claudeFailingOrAnsweringTooLittleIsReported() async throws {
        let (_, w) = try storeWithHiddenProject()
        let failing = try script("echo 'Not logged in' >&2\nexit 1")
        #expect(await report([failing]).write(w, now: local(2026, 10, 12)) == .failure(.failed("Not logged in")))
        let short = try script("printf 'Only one line.\\n'")
        #expect(await report([short]).write(w, now: local(2026, 10, 12)) == .failure(.unreadable))
    }

    private final class Spy: ProcessRunning, @unchecked Sendable {
        var executable: URL?; var args: [String] = []; var cwd: URL?; var timeout: TimeInterval = 0; var stdin: Data?; var home: URL?
        func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL)
            -> (status: Int32, out: Data, err: Data)? {
            self.executable = executable; self.args = args; self.cwd = cwd; self.timeout = timeout; self.stdin = stdin; self.home = home
            return (0, Data("One.\nTwo.\nThree.\n".utf8), Data())
        }
    }

    @Test func claudeArgumentsAreLocked() async throws {
        let spy = Spy()
        let claude = try script("exit 0")
        let home = fakeHome()
        let (_, w) = try storeWithHiddenProject()
        let result = await report([claude], runner: spy, home: home).write(w, now: local(2026, 10, 12))
        #expect(result == .success(WeekReport(weekStart: "2026-10-05", lines: ["One.", "Two.", "Three."], author: .claudeCode, written: local(2026, 10, 12))))
        #expect(spy.executable == claude)
        #expect(spy.args == ["-p", "--output-format", "text", "--setting-sources", "project",
                             "--permission-mode", "default",
                             "--disallowedTools", "Agent Task Bash BashOutput KillShell Edit MultiEdit Write Read Glob Grep LS WebFetch WebSearch NotebookEdit NotebookRead TodoWrite Skill SlashCommand ExitPlanMode Monitor EnterWorktree ExitWorktree ToolSearch TaskStop LSP",
                             "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#])
        #expect(spy.timeout == 120)
        #expect(spy.home == home)
        #expect(spy.cwd?.lastPathComponent == "report")
        #expect(spy.cwd?.deletingLastPathComponent().lastPathComponent == "Tidemark")
        #expect(spy.stdin.map { String(decoding: $0, as: UTF8.self) }?.hasPrefix("Summarise the work log below in exactly three plain sentences. Sentence 1: what was shipped or finished.") == true)
    }

    @Test func systemCandidatesAreTheUsualPlaces() {
        let home = URL(fileURLWithPath: "/Users/you")
        #expect(ClaudeCodeReport.systemCandidates(home: home).map(\.path) == [
            "/Users/you/.claude/local/claude", "/Users/you/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"])
    }
}

@Suite struct DemoReportWriterTests {
    // L6: with demo data on, "Write it with Claude Code" never runs the real claude; it answers with the demo's report.
    @Test func theDemoWriterReturnsTheDemoReportForTheWeekAsked() async {
        let store = DemoCalendar.store()
        let week = store.week(containing: DemoCalendar.now, weekStart: .monday, now: DemoCalendar.now)
        let write = DemoCalendar.reportWriter(delay: .milliseconds(1))
        let result = await write(week, DemoCalendar.now)
        guard case .success(let report) = result else { Issue.record("expected a report"); return }
        #expect(report.lines.count == 3)
        #expect(report.author == .claudeCode)
        #expect(report.weekStart == "2026-10-19")
        #expect(report.written == DemoCalendar.now)
    }
}
