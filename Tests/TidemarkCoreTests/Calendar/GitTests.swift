import Foundation
import Testing
@testable import TidemarkCore

@Suite struct GitTests {
    private final class FakeRunner: ProcessRunning, @unchecked Sendable {
        var calls: [[String]] = []
        var respond: ([String]) -> (status: Int32, out: Data, err: Data)?
        init(_ respond: @escaping ([String]) -> (status: Int32, out: Data, err: Data)?) { self.respond = respond }
        func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL) -> (status: Int32, out: Data, err: Data)? {
            calls.append([executable.path] + args)
            return respond([executable.path] + args)
        }
        var gitCalls: [[String]] { calls.filter { $0.first == "/usr/bin/git" } }
    }

    private let home = URL(fileURLWithPath: "/Users/you")
    private let repo = "/Users/you/code/tide-tables"
    private func text(_ s: String) -> (status: Int32, out: Data, err: Data) { (0, Data(s.utf8), Data()) }

    private func record(_ sha: String, _ date: String, _ email: String, _ subject: String, files: [String]) -> String {
        "\u{1e}\(sha)\u{1f}\(date)\u{1f}\(email)\u{1f}\(subject)\n\n" + files.joined(separator: "\n") + "\n"
    }

    private func runner(log: String?, repoEmail: String = "you@example.com", globalEmail: String = "") -> FakeRunner {
        FakeRunner { args in
            if args.first == "/usr/bin/xcode-select" { return self.text("/Library/Developer/CommandLineTools\n") }
            if args.contains("log") { return log.map { self.text($0) } }
            if args.contains("--global") { return self.text(globalEmail) }
            if args.contains("config") { return self.text(repoEmail) }
            return self.text("")
        }
    }

    private let sha1 = "9eba146aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let sha2 = "abcdef0123456789abcdef0123456789abcdef01"

    @Test func parsesGitLog() {
        let log = record(sha1, "2026-10-12T13:10:00-04:00", "You@Example.com", "Add chart export", files: ["src/chart.swift", "README.md"])
            + record(sha2, "2026-10-12T14:00:00-04:00", "you@example.com", "Fix the legend", files: [])
        let reader = GitReader(runner: runner(log: log), home: home)
        let commits = reader.commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13))
        #expect(commits.count == 2)
        #expect(commits[0] == Commit(sha: sha1, time: local(2026, 10, 12, 13, 10), repo: repo, subject: "Add chart export", files: ["src/chart.swift", "README.md"]))
        #expect(commits[1].sha == sha2 && commits[1].files.isEmpty)
    }

    @Test func logArgumentsAreExact() {
        let fake = runner(log: "")
        _ = GitReader(runner: fake, home: home).commits(repo: repo, from: utc("2026-10-12T04:00:00Z"), to: utc("2026-10-13T04:00:00Z"))
        let log = fake.gitCalls.first { $0.contains("log") }!
        #expect(log == ["/usr/bin/git", "-C", repo, "log", "--all", "--since=2026-10-12T04:00:00Z", "--until=2026-10-13T04:00:00Z",
                        "--format=%x1e%H%x1f%cI%x1f%ae%x1f%s", "--name-only"])
        #expect(fake.gitCalls.contains(["/usr/bin/git", "-C", repo, "config", "user.email"]))
        #expect(fake.gitCalls.contains(["/usr/bin/git", "-C", "/Users/you", "config", "--global", "user.email"]))
    }

    @Test func othersCommitsIgnored() {
        let log = record(sha1, "2026-10-12T13:10:00-04:00", "someone@example.com", "Not mine", files: ["a.txt"])
            + record(sha2, "2026-10-12T14:00:00-04:00", "me-global@example.com", "Mine by the global address", files: [])
        let reader = GitReader(runner: runner(log: log, globalEmail: "Me-Global@example.com\n"), home: home)
        let commits = reader.commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13))
        #expect(commits.map(\.subject) == ["Mine by the global address"])
    }

    @Test func noEmailConfiguredMeansNoCommits() {
        let log = record(sha1, "2026-10-12T13:10:00-04:00", "someone@example.com", "x", files: [])
        let reader = GitReader(runner: runner(log: log, repoEmail: ""), home: home)
        #expect(reader.commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13)).isEmpty)
    }

    @Test func noDeveloperToolsMeansNoGit() {
        let fake = FakeRunner { _ in (1, Data(), Data("no developer tools".utf8)) }
        let reader = GitReader(runner: fake, home: home)
        #expect(!reader.isAvailable)
        #expect(reader.commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13)).isEmpty)
        #expect(fake.gitCalls.isEmpty)
    }

    @Test func gitTimeoutIsNoCommits() {
        let reader = GitReader(runner: runner(log: nil), home: home)
        #expect(reader.isAvailable)
        #expect(reader.commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13)).isEmpty)
    }

    @Test func failedLogIsNoCommits() {
        let fake = FakeRunner { args in
            args.first == "/usr/bin/xcode-select" ? (0, Data(), Data()) : (128, Data(), Data("fatal".utf8))
        }
        #expect(GitReader(runner: fake, home: home).commits(repo: repo, from: local(2026, 10, 12), to: local(2026, 10, 13)).isEmpty)
    }

    // MARK: - Matching

    private func session(_ id: String, _ start: Date, _ end: Date, root: String? = nil, git: Bool = true) -> CalendarSession {
        CalendarSession(id: id, origin: .claudeCode, root: root ?? repo, isGit: git, blocks: [Block(start: start, end: end)], lastActivity: end)
    }
    private func commit(_ sha: String, at time: Date, repo: String? = nil) -> Commit {
        Commit(sha: sha, time: time, repo: repo ?? self.repo, subject: "s", files: [])
    }

    @Test func hashPrintedInSessionWins() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11)),
                        session("sess-tide-0002", local(2026, 10, 12, 9, 30), local(2026, 10, 12, 10, 30))]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10))], to: &sessions, hashes: ["sess-tide-0002": ["9eba146"]])
        #expect(sessions[0].commits.isEmpty)
        #expect(sessions[1].commits.map(\.sha) == [sha1])
    }

    @Test func commitAfterBlockWithinGrace() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 10))]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10, 4)), commit(sha2, at: local(2026, 10, 12, 10, 6))], to: &sessions)
        #expect(sessions[0].commits.map(\.sha) == [sha1])
        #expect(CommitMatcher.grace == 300)
    }

    @Test func latestActiveSessionGetsIt() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 9, 40)),
                        session("sess-tide-0002", local(2026, 10, 12, 9, 10), local(2026, 10, 12, 9, 50))]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 9, 44))], to: &sessions)
        #expect(sessions[0].commits.isEmpty)
        #expect(sessions[1].commits.count == 1)
    }

    @Test func tiesGoToTheFirstSession() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11)),
                        session("sess-tide-0002", local(2026, 10, 12, 9), local(2026, 10, 12, 11))]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10))], to: &sessions)
        #expect(sessions[0].commits.count == 1 && sessions[1].commits.isEmpty)
    }

    @Test func otherReposAndNonGitSessionsGetNothing() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11), root: "/Users/you/code/other"),
                        session("sess-tide-0002", local(2026, 10, 12, 9), local(2026, 10, 12, 11), git: false)]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10))], to: &sessions)
        #expect(sessions.allSatisfy { $0.commits.isEmpty })
    }

    @Test func assigningTwiceCountsOnce() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11))]
        let c = commit(sha1, at: local(2026, 10, 12, 10))
        CommitMatcher.assign([c], to: &sessions)
        CommitMatcher.assign([c], to: &sessions)
        #expect(sessions[0].commits.count == 1)
    }

    @Test func aShortStoredShaIsTheSameCommitAsGitsFullOne() {
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11))]
        sessions[0].commits = [Commit(sha: "9eba146", time: local(2026, 10, 12, 11), repo: repo, subject: "Add chart export")]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10, 15))], to: &sessions)
        #expect(sessions[0].commits.count == 1)
        #expect(sessions[0].commits[0].sha == sha1)
        #expect(sessions[0].commits[0].time == local(2026, 10, 12, 10, 15))
    }

    @Test func aShortShaOnlyMatchesInItsOwnRepo() {
        var other = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11), root: "/Users/you/code/other")]
        other[0].commits = [Commit(sha: "9eba146", time: local(2026, 10, 12, 11), repo: "/Users/you/code/other", subject: "Elsewhere")]
        var mine = [session("sess-tide-0002", local(2026, 10, 12, 9), local(2026, 10, 12, 11))]
        mine[0].commits = []
        var all = other + mine
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10))], to: &all)
        #expect(all[0].commits.map(\.sha) == ["9eba146"])
        #expect(all[1].commits.map(\.sha) == [sha1])
    }

    @Test func rawActivityBreaksTiesLikeTheOldCalendar() {
        // A types until 10:35 inside a long block; B types at 10:44. A terminal commit at 10:45 is B's.
        var sessions = [session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 11)),
                        session("sess-tide-0002", local(2026, 10, 12, 10), local(2026, 10, 12, 10, 50))]
        let times: [String: [Date]] = [
            "sess-tide-0001": [local(2026, 10, 12, 9), local(2026, 10, 12, 9, 25), local(2026, 10, 12, 9, 50), local(2026, 10, 12, 10, 15), local(2026, 10, 12, 10, 35), local(2026, 10, 12, 11)],
            "sess-tide-0002": [local(2026, 10, 12, 10), local(2026, 10, 12, 10, 44), local(2026, 10, 12, 10, 50)]]
        CommitMatcher.assign([commit(sha1, at: local(2026, 10, 12, 10, 45))], to: &sessions, activity: times)
        #expect(sessions[0].commits.isEmpty)
        #expect(sessions[1].commits.count == 1)
    }

    @Test func noCommitOnlyWhenGitAndFinished() {
        let weekEnd = local(2026, 10, 19), now = local(2026, 10, 14, 12)
        let done = session("sess-tide-0001", local(2026, 10, 12, 9), local(2026, 10, 12, 10))
        #expect(CommitMatcher.noCommit(done, weekEnd: weekEnd, now: now, committedBefore: false))
        #expect(!CommitMatcher.noCommit(done, weekEnd: weekEnd, now: now, committedBefore: true))
        var withCommit = done
        withCommit.commits = [commit(sha1, at: local(2026, 10, 12, 10))]
        #expect(!CommitMatcher.noCommit(withCommit, weekEnd: weekEnd, now: now, committedBefore: false))
        var notGit = done
        notGit.isGit = false
        #expect(!CommitMatcher.noCommit(notGit, weekEnd: weekEnd, now: now, committedBefore: false))
        var cowork = done
        cowork.origin = .cowork
        #expect(!CommitMatcher.noCommit(cowork, weekEnd: weekEnd, now: now, committedBefore: false))
        let running = session("sess-tide-0002", local(2026, 10, 14, 11), local(2026, 10, 14, 11, 40))
        #expect(!CommitMatcher.noCommit(running, weekEnd: weekEnd, now: now, committedBefore: false))
        let spills = session("sess-tide-0003", local(2026, 10, 18, 23), local(2026, 10, 19, 1))
        #expect(!CommitMatcher.noCommit(spills, weekEnd: weekEnd, now: now, committedBefore: false))
    }

    // MARK: - The real runner, with harmless system tools (never git)

    @Test func systemRunnerGivesTheChildOnlyHomeAndPath() throws {
        let home = tempDir()
        let result = try #require(SystemProcessRunner().run(URL(fileURLWithPath: "/usr/bin/env"), [], cwd: nil, timeout: 10, stdin: nil, home: home))
        let lines = Set(String(decoding: result.out, as: UTF8.self).split(separator: "\n").map(String.init))
        #expect(lines == ["HOME=\(home.path)", "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"])
        #expect(result.status == 0)
    }

    @Test func systemRunnerPassesStdinAndTimesOut() throws {
        let home = tempDir()
        let echoed = SystemProcessRunner().run(URL(fileURLWithPath: "/bin/cat"), [], cwd: nil, timeout: 10, stdin: Data("hello".utf8), home: home)
        #expect(echoed.map { String(decoding: $0.out, as: UTF8.self) } == "hello")
        let slow = SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sleep"), ["20"], cwd: nil, timeout: 0.3, stdin: nil, home: home)
        #expect(slow == nil)
        #expect(SystemProcessRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), [], cwd: nil, timeout: 1, stdin: nil, home: home) == nil)
    }

    @Test func systemRunnerPassesTheConfigFolderWhenSetAndNothingElse() throws {
        let home = tempDir()
        let runner = SystemProcessRunner(environment: ["CLAUDE_CONFIG_DIR": "/Users/you/claude-config", "SECRET_TOKEN": "x", "HOME": "/elsewhere"])
        let result = try #require(runner.run(URL(fileURLWithPath: "/usr/bin/env"), [], cwd: nil, timeout: 10, stdin: nil, home: home))
        let lines = Set(String(decoding: result.out, as: UTF8.self).split(separator: "\n").map(String.init))
        #expect(lines == ["HOME=\(home.path)", "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "CLAUDE_CONFIG_DIR=/Users/you/claude-config"])
        // Unset or empty: not passed.
        let none = try #require(SystemProcessRunner(environment: ["CLAUDE_CONFIG_DIR": ""]).run(URL(fileURLWithPath: "/usr/bin/env"), [], cwd: nil, timeout: 10, stdin: nil, home: home))
        #expect(!String(decoding: none.out, as: UTF8.self).contains("CLAUDE_CONFIG_DIR"))
    }

    @Test func aChildThatNeverReadsItsInputDoesNotKillTheApp() throws {
        // /usr/bin/true exits at once; the input is far bigger than a pipe holds, so the write hits a closed pipe (SIGPIPE).
        let big = Data(repeating: 0x61, count: 4_000_000)
        let result = SystemProcessRunner().run(URL(fileURLWithPath: "/usr/bin/true"), [], cwd: nil, timeout: 10, stdin: big, home: tempDir())
        #expect(result?.status == 0)
    }
}
