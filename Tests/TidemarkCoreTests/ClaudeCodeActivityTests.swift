import Foundation
import Testing
@testable import TidemarkCore

@Suite(.serialized) struct ClaudeCodeActivityTests {
    /// Counts reports from the watcher's queue.
    final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [Date] = []
        func add(_ time: Date) { lock.withLock { times.append(time) } }
        var count: Int { lock.withLock { times.count } }
    }

    /// A fresh `projects` folder with one project in it, like `~/.claude/projects`.
    func makeProjects() throws -> URL {
        let projects = FileManager.default.temporaryDirectory
            .appendingPathComponent("TidemarkActivity-\(UUID().uuidString)/projects")
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("-Users-you-tide-tables"),
                                                withIntermediateDirectories: true)
        return projects
    }

    func wait(for reports: Reports, atLeast count: Int, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if reports.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return reports.count >= count
    }

    @Test func aTranscriptWriteIsActivity() async throws {
        let projects = try makeProjects()
        let reports = Reports()
        let watcher = ClaudeCodeActivity(folder: projects) { reports.add($0) }
        watcher.start()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: projects.deletingLastPathComponent())
        }
        try await Task.sleep(for: .milliseconds(300))
        try Data("{}\n".utf8).write(to: projects.appendingPathComponent("-Users-you-tide-tables/session.jsonl"))
        #expect(await wait(for: reports, atLeast: 1, seconds: 5))
    }

    @Test func otherFilesAreNot() async throws {
        let projects = try makeProjects()
        let reports = Reports()
        let watcher = ClaudeCodeActivity(folder: projects) { reports.add($0) }
        watcher.start()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: projects.deletingLastPathComponent())
        }
        try await Task.sleep(for: .milliseconds(300))
        try Data("notes".utf8).write(to: projects.appendingPathComponent("-Users-you-tide-tables/notes.txt"))
        #expect(await !wait(for: reports, atLeast: 1, seconds: 2.5))
    }

    // Someone who has never run Claude Code has no ~/.claude/projects.
    @Test func aMissingFolderIsQuiet() {
        let watcher = ClaudeCodeActivity(folder: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/projects")) { _ in }
        watcher.start()
        watcher.stop()
    }

    // Claude Code may first run after Tidemark started: the projects folder appears later.
    @Test func watchesAFolderThatAppearsLater() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TidemarkActivity-\(UUID().uuidString)")
        let projects = root.appendingPathComponent("projects")
        let reports = Reports()
        let watcher = ClaudeCodeActivity(folder: projects, recheckInterval: 0.2) { reports.add($0) }
        watcher.start()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: root)
        }
        try await Task.sleep(for: .milliseconds(500))
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("-Users-you-tide-tables"), withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(1200))
        try Data("{}\n".utf8).write(to: projects.appendingPathComponent("-Users-you-tide-tables/session.jsonl"))
        #expect(await wait(for: reports, atLeast: 1, seconds: 6))
    }
}
