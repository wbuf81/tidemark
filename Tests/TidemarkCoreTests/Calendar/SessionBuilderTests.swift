import Foundation
import Testing
@testable import TidemarkCore

@Suite struct SessionBuilderTests {
    private struct FakeLocator: RepoLocating {
        var repos: [String: String]
        func repo(for cwd: String) -> String? { repos[cwd] }
    }

    private final class FakeRunner: ProcessRunning, @unchecked Sendable {
        var calls: [[String]] = []
        var respond: ([String]) -> (status: Int32, out: Data, err: Data)?
        init(_ respond: @escaping ([String]) -> (status: Int32, out: Data, err: Data)?) { self.respond = respond }
        func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL) -> (status: Int32, out: Data, err: Data)? {
            calls.append([executable.path] + args)
            return respond([executable.path] + args)
        }
    }

    private func t(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { local(2026, 10, 12, h, m).addingTimeInterval(Double(s)) }
    private func raw(_ times: [Date], cwd: String? = "/Users/you/code/tide-tables", id: String = "sess-tide-0001") -> RawSession {
        RawSession(id: id, origin: .claudeCode, cwd: cwd, times: times)
    }

    @Test func gapOfExactly30MinutesStaysInOneBlock() {
        let blocks = SessionBuilder.blocks([t(9, 0), t(9, 30)])
        #expect(blocks == [Block(start: t(9, 0), end: t(9, 30))])
    }

    @Test func gapOf30Minutes1SecondSplits() {
        let blocks = SessionBuilder.blocks([t(9, 0), t(9, 30, 1)])
        #expect(blocks == [Block(start: t(9, 0), end: t(9, 0)), Block(start: t(9, 30, 1), end: t(9, 30, 1))])
    }

    @Test func loneTimeIsAZeroLengthBlock() {
        #expect(SessionBuilder.blocks([t(9, 0)]) == [Block(start: t(9, 0), end: t(9, 0))])
        #expect(SessionBuilder.blocks([]).isEmpty)
    }

    @Test func unsortedTimesAreSortedFirst() {
        let blocks = SessionBuilder.blocks([t(12, 0), t(9, 0), t(9, 20), t(12, 10)])
        #expect(blocks == [Block(start: t(9, 0), end: t(9, 20)), Block(start: t(12, 0), end: t(12, 10))])
    }

    @Test func rootIsTheMainCheckoutFromAWorktree() {
        let locator = FakeLocator(repos: ["/Users/you/code/tide-tables-wt/feature": "/Users/you/code/tide-tables"])
        let repo = locator.repo(for: "/Users/you/code/tide-tables-wt/feature")
        let s = SessionBuilder.session(raw([t(9, 0), t(9, 10)], cwd: "/Users/you/code/tide-tables-wt/feature"), repo: repo)
        #expect(s.root == "/Users/you/code/tide-tables")
        #expect(s.isGit)
        #expect(s.lastActivity == t(9, 10))
        #expect(s.commits.isEmpty)
    }

    @Test func rootFallsBackToTheFolderThenUnknown() {
        #expect(SessionBuilder.session(raw([t(9, 0)], cwd: "/Users/you/notes/"), repo: nil).root == "/Users/you/notes")
        #expect(!SessionBuilder.session(raw([t(9, 0)], cwd: "/Users/you/notes"), repo: nil).isGit)
        #expect(SessionBuilder.session(raw([t(9, 0)], cwd: nil), repo: nil).root == "unknown folder")
        #expect(SessionBuilder.session(raw([t(9, 0)], cwd: "/"), repo: nil).root == "/")
    }

    @Test func coworkRootIsCowork() {
        var r = RawSession(id: "sess-cowork-0001", origin: .cowork, times: [t(9, 0)], title: "Brief", folders: ["field-notes"], scheduled: true, logged: true)
        r.firstMessage = "hello"
        let s = SessionBuilder.session(r, repo: "/Users/you/should-be-ignored")
        #expect(s.root == "Cowork" && !s.isGit)
        #expect(s.origin == .cowork && s.scheduled && s.logged)
        #expect(s.title == "Brief" && s.firstMessage == "hello" && s.folders == ["field-notes"])
    }

    @Test func sessionsSortDeterministically() {
        let a = SessionBuilder.session(raw([t(10, 0)], id: "sess-tide-0002"), repo: nil)
        let b = SessionBuilder.session(raw([t(10, 0)], id: "sess-tide-0001"), repo: nil)
        let c = SessionBuilder.session(raw([t(8, 0)], id: "sess-tide-0009"), repo: nil)
        #expect(SessionBuilder.sorted([a, b, c]).map(\.id) == ["sess-tide-0009", "sess-tide-0001", "sess-tide-0002"])
    }

    // MARK: - GitRepoLocator, with a fake runner

    private func gitOK(common: String) -> FakeRunner {
        FakeRunner { args in
            if args.first == "/usr/bin/xcode-select" { return (0, Data("/Library/Developer/CommandLineTools\n".utf8), Data()) }
            return (0, Data((common + "\n").utf8), Data())
        }
    }

    @Test func locatorAsksGitAboutTheFirstExistingFolder() throws {
        let home = tempDir()
        let existing = home.appendingPathComponent("code/tide-tables/src", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let runner = gitOK(common: "/Users/you/code/tide-tables/.git")
        let locator = GitRepoLocator(runner: runner, home: home)
        let repo = locator.repo(for: existing.appendingPathComponent("deleted/deeper").path)
        #expect(repo == "/Users/you/code/tide-tables")
        let git = runner.calls.last!
        #expect(git == ["/usr/bin/git", "-C", existing.path, "rev-parse", "--path-format=absolute", "--git-common-dir"])
    }

    @Test func locatorCachesPerFolderAndSaysNilOutsideGit() throws {
        let home = tempDir()
        let folder = home.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let runner = FakeRunner { args in
            args.first == "/usr/bin/xcode-select" ? (0, Data(), Data()) : (128, Data(), Data("fatal: not a git repository".utf8))
        }
        let locator = GitRepoLocator(runner: runner, home: home)
        #expect(locator.repo(for: folder.path) == nil)
        #expect(locator.repo(for: folder.path) == nil)
        #expect(runner.calls.filter { $0.first == "/usr/bin/git" }.count == 1)
    }

    @Test func locatorNeverRunsGitWithoutDeveloperTools() throws {
        let home = tempDir()
        let runner = FakeRunner { _ in (1, Data(), Data("xcode-select: error: no developer tools were found".utf8)) }
        let locator = GitRepoLocator(runner: runner, home: home)
        #expect(locator.repo(for: home.path) == nil)
        #expect(!runner.calls.contains { $0.first == "/usr/bin/git" })
    }
}
