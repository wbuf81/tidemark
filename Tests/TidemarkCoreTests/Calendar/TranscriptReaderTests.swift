import Foundation
import Testing
@testable import TidemarkCore

@Suite struct TranscriptReaderTests {
    private func read(_ name: String, firstMessage: Bool = true, ownFolder: URL? = nil) -> RawSession? {
        TranscriptReader.read(fixtureURL(name), keepFirstMessage: firstMessage, ignoringRunsUnder: ownFolder)
    }

    @Test func customTitleBeatsAiTitle() {
        #expect(read("transcript-titles.jsonl")?.title == "Chart export work")
        #expect(read("transcript-aionly.jsonl")?.title == "Last AI title")
    }

    @Test func idIsTheFileStem() {
        let raw = read("transcript-titles.jsonl")
        #expect(raw?.id == "transcript-titles")
        #expect(raw?.origin == .claudeCode)
        #expect(raw?.cwd == "/Users/you/code/tide-tables")
    }

    @Test func sidechainsAddNoTime() {
        let raw = read("transcript-sidechain.jsonl")
        #expect(raw?.times == [utc("2026-10-12T13:00:00Z"), utc("2026-10-12T13:10:00Z")])
        #expect(raw?.cwd == "/Users/you/code/tide-tables")
    }

    @Test func badLineIsSkipped() {
        #expect(read("transcript-badline.jsonl")?.times.count == 3)
    }

    @Test func timesAreSortedAndFractionsParse() {
        let raw = read("transcript-titles.jsonl")
        #expect(raw?.times == [utc("2026-10-12T13:00:00Z"), utc("2026-10-12T13:05:00Z")])
    }

    @Test func firstMessageIsTheFirstTypedOne() {
        #expect(read("transcript-first.jsonl")?.firstMessage == "Add the chart export")
    }

    @Test func commandTextBecomesCommand() {
        let raw = read("transcript-command.jsonl")
        #expect(raw?.command == "/review pr 12")
        #expect(raw?.firstMessage == nil)
    }

    @Test func pastedAndImageMarkersRemoved() {
        #expect(read("transcript-markers.jsonl")?.firstMessage == "look at the log and this")
    }

    @Test func longMessagesAreCutTo600() throws {
        let dir = tempDir()
        let file = dir.appendingPathComponent("sess-tide-0001.jsonl")
        let text = String(repeating: "word ", count: 400)
        let line = #"{"type":"user","cwd":"/Users/you/x","timestamp":"2026-10-12T13:00:00Z","origin":{"kind":"human"},"message":{"role":"user","content":"\#(text)"}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.read(file, keepFirstMessage: true)?.firstMessage?.count == 600)
    }

    @Test func commitHashFromToolResult() {
        let raw = read("transcript-commit.jsonl")
        #expect(raw?.hashes == ["9eba146", "abcdef0123"])
    }

    @Test func firstMessagesOffKeepsNone() {
        let raw = read("transcript-first.jsonl", firstMessage: false)
        #expect(raw?.firstMessage == nil)
        #expect(raw?.times.count == 4)
        #expect(read("transcript-command.jsonl", firstMessage: false)?.command == nil)
    }

    @Test func ownReportRunsAreDropped() {
        let own = URL(fileURLWithPath: "/Users/you/Library/Application Support/Tidemark")
        #expect(read("transcript-own.jsonl", ownFolder: own) == nil)
        #expect(read("transcript-own.jsonl") != nil)
    }

    @Test func noTimedRecordsGivesNil() throws {
        let file = tempDir().appendingPathComponent("sess-tide-0002.jsonl")
        try #"{"type":"ai-title","aiTitle":"x"}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(TranscriptReader.read(file, keepFirstMessage: true) == nil)
    }

    @Test func filesOldestFirstSince() throws {
        let projects = tempDir()
        let a = projects.appendingPathComponent("-Users-you-a"), b = projects.appendingPathComponent("-Users-you-b")
        try FileManager.default.createDirectory(at: a.appendingPathComponent("sess-tide-0001/subagents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let files: [(URL, Date)] = [
            (a.appendingPathComponent("new.jsonl"), utc("2026-10-12T00:00:00Z")),
            (b.appendingPathComponent("old.jsonl"), utc("2026-10-01T00:00:00Z")),
            (b.appendingPathComponent("older.jsonl"), utc("2026-09-01T00:00:00Z")),
            (a.appendingPathComponent("sess-tide-0001/subagents/agent-1.jsonl"), utc("2026-10-13T00:00:00Z")),
            (a.appendingPathComponent("notes.txt"), utc("2026-10-13T00:00:00Z")),
        ]
        for (url, date) in files {
            try "{}".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        #expect(TranscriptReader.files(projectsDir: projects, since: nil).map(\.lastPathComponent) == ["older.jsonl", "old.jsonl", "new.jsonl"])
        #expect(TranscriptReader.files(projectsDir: projects, since: utc("2026-10-01T00:00:00Z")).map(\.lastPathComponent) == ["old.jsonl", "new.jsonl"])
        #expect(TranscriptReader.files(projectsDir: projects.appendingPathComponent("missing"), since: nil).isEmpty)
    }
}
