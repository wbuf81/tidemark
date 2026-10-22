import Foundation
import Testing
@testable import TidemarkCore

@Suite struct CoworkReadersTests {
    private func log(_ lines: [String]) throws -> URL {
        let dir = tempDir()
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("tidemark-log.jsonl"), atomically: true, encoding: .utf8)
        return dir
    }

    private func entry(id: String? = "sess-cowork-0030", _ start: String, _ end: String, folders: String = "[]") -> String {
        let idPart = id.map { #""id":"\#($0)","# } ?? ""
        return #"{\#(idPart)"start":"\#(start)","end":"\#(end)","title":"T","ask":"a","folders":\#(folders)}"#
    }

    @Test func perFileEntriesGroupById() {
        let result = CoworkLogReader.read(folder: fixtureURL("cowork-log"), since: nil)
        let byId = Dictionary(uniqueKeysWithValues: result.sessions.map { ($0.id, $0) })
        #expect(Set(byId.keys) == ["sess-cowork-0001", "sess-cowork-0002"])
        let one = byId["sess-cowork-0001"]!
        #expect(one.origin == .cowork)
        #expect(one.title == "Tide table fixes, round two")
        #expect(one.firstMessage == "fix the tide table")
        #expect(one.folders == ["tide-tables"])
        #expect(one.logged && !one.scheduled)
        #expect(one.times.first == utc("2026-10-12T13:00:00Z") && one.times.last == utc("2026-10-12T14:05:00Z"))
        #expect(byId["sess-cowork-0002"]!.scheduled)
        #expect(result.problem == nil)
    }

    // M6: the sheet says "Tidemark reads only that file": the log and the older <id>__<stamp>.json entry files, nothing else
    // in the folder, even a .json that looks like an entry.
    @Test func onlyTheLogAndTheOlderEntryFilesAreRead() throws {
        let dir = tempDir()
        let line = entry("2026-10-12T09:00:00Z", "2026-10-12T09:10:00Z")
        try line.write(to: dir.appendingPathComponent("tidemark-log.jsonl"), atomically: true, encoding: .utf8)
        try entry(id: "sess-cowork-0031", "2026-10-12T10:00:00Z", "2026-10-12T10:10:00Z")
            .write(to: dir.appendingPathComponent("sess-cowork-0031__20261012T100000Z.json"), atomically: true, encoding: .utf8)
        for other in ["notes.json", "package.json", "other.jsonl", "__20261012.json", "draft.txt"] {
            try entry(id: "sess-other", "2026-10-12T11:00:00Z", "2026-10-12T11:10:00Z")
                .write(to: dir.appendingPathComponent(other), atomically: true, encoding: .utf8)
        }
        let result = CoworkLogReader.read(folder: dir, since: nil)
        #expect(Set(result.sessions.map(\.id)) == ["sess-cowork-0030", "sess-cowork-0031"])
        #expect(result.skipped == 0)
    }

    @Test func entryLongerThan12HoursSkipped() {
        let result = CoworkLogReader.read(folder: fixtureURL("cowork-log"), since: nil)
        #expect(!result.sessions.contains { $0.id == "sess-cowork-0003" })
        #expect(result.skipped == 2)   // the 13-hour entry and the one that isn't JSON
    }

    @Test func jsonLinesEntries() {
        let result = CoworkLogReader.read(folder: fixtureURL("cowork-log-lines"), since: nil)
        #expect(result.sessions.map(\.id).sorted() == ["sess-cowork-0010", "sess-cowork-0011"])
        let ten = result.sessions.first { $0.id == "sess-cowork-0010" }!
        #expect(ten.title == "Field notes tidy")   // an empty later title never overwrites
        #expect(ten.folders == ["field-notes"])
        #expect(result.skipped == 1)               // the line that isn't JSON
    }

    @Test func tenMinuteTimesWithinATurn() throws {
        let folder = try log([entry("2026-10-12T13:00:00Z", "2026-10-12T13:25:00Z")])
        let raw = CoworkLogReader.read(folder: folder, since: nil).sessions[0]
        #expect(raw.times == ["13:00", "13:10", "13:20", "13:25"].map { utc("2026-10-12T\($0):00Z") })
        let point = try log([entry("2026-10-12T13:00:00Z", "2026-10-12T13:00:00Z")])
        #expect(CoworkLogReader.read(folder: point, since: nil).sessions[0].times == [utc("2026-10-12T13:00:00Z")])
    }

    @Test func mountFoldersAndClaudeDropped() throws {
        let folders = #"["outputs","uploads","user-data","skills",".claude",".skills","Claude","tide-tables","a","b","c"]"#
        let folder = try log([entry("2026-10-12T13:00:00Z", "2026-10-12T13:05:00Z", folders: folders)])
        #expect(CoworkLogReader.read(folder: folder, since: nil).sessions[0].folders == ["tide-tables", "a", "b"])
    }

    @Test func entriesWithoutAnIdAreEachTheirOwnSession() throws {
        let folder = try log([entry(id: nil, "2026-10-12T13:00:00Z", "2026-10-12T13:05:00Z"),
                              entry(id: nil, "2026-10-12T13:06:00Z", "2026-10-12T13:09:00Z")])
        let ids = CoworkLogReader.read(folder: folder, since: nil).sessions.map(\.id)
        #expect(ids.count == 2 && Set(ids).count == 2)
        #expect(ids.allSatisfy { $0.hasPrefix("cowork-") })
    }

    @Test func entriesBeforeSinceAreLeftOut() throws {
        let folder = try log([entry("2026-10-12T13:00:00Z", "2026-10-12T13:05:00Z")])
        #expect(CoworkLogReader.read(folder: folder, since: utc("2026-10-12T13:05:01Z")).sessions.isEmpty)
        #expect(CoworkLogReader.read(folder: folder, since: utc("2026-10-12T13:05:00Z")).sessions.count == 1)
    }

    @Test func firstMessagesOffDropsTheAsk() throws {
        let folder = try log([entry("2026-10-12T13:00:00Z", "2026-10-12T13:05:00Z")])
        #expect(CoworkLogReader.read(folder: folder, since: nil, keepFirstMessage: false).sessions[0].firstMessage == nil)
    }

    @Test func coworkTitleInJapaneseSurvives() {
        let raw = CoworkLogReader.read(folder: fixtureURL("cowork-log-japanese"), since: nil).sessions[0]
        #expect(raw.title == "潮汐表の修正")
        #expect(raw.firstMessage == "潮汐表を直して")
    }

    @Test func unreadableFolderGivesAProblem() throws {
        let dir = tempDir().appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let result = CoworkLogReader.read(folder: dir, since: nil)
        #expect(result.sessions.isEmpty)
        #expect(result.problem?.title == "Tidemark can’t read the Cowork log folder")
        #expect(result.problem?.detail == "Choose it again in Settings → Week.")
        #expect(CoworkLogReader.read(folder: dir.appendingPathComponent("missing"), since: nil).problem != nil)
    }

    @Test func desktopSessionFromMetadataAndAudit() {
        let sessions = DesktopCoworkReader.read(root: fixtureURL("local-agent-mode-sessions"), since: nil, keepFirstMessage: true)
        let one = sessions.first { $0.id == "sess-cowork-0100" }
        #expect(one?.origin == .cowork)
        #expect(one?.title == "Harbor report draft")
        #expect(one?.firstMessage == "Draft the harbor report")
        #expect(one?.folders == ["harbor-site"])
        #expect(one?.times == ["16:00", "16:05", "16:07"].map { utc("2026-10-12T\($0):00Z") })
        #expect(one?.logged == false)
        #expect(!sessions.contains { $0.id == "task-cowork-0102" })   // no audit log
        let off = DesktopCoworkReader.read(root: fixtureURL("local-agent-mode-sessions"), since: nil, keepFirstMessage: false)
        #expect(off.first { $0.id == "sess-cowork-0100" }?.firstMessage == nil)
    }

    @Test func scheduledTaskFlag() {
        let sessions = DesktopCoworkReader.read(root: fixtureURL("local-agent-mode-sessions"), since: nil, keepFirstMessage: true)
        let two = sessions.first { $0.id == "sess-cowork-0101" }
        #expect(two?.scheduled == true)
        #expect(two?.firstMessage == nil)   // the task wrapper isn't something the user typed
        #expect(two?.times.count == 2)      // found through the short folder name
        #expect(sessions.first { $0.id == "sess-cowork-0100" }?.scheduled == false)
    }

    @Test func sameIdFromBothSourcesMerges() {
        let desktop = RawSession(id: "Sess-Cowork-0500", origin: .cowork, times: [utc("2026-10-12T10:00:00Z")], title: "Old title",
                                 firstMessage: nil, folders: ["harbor-site"], scheduled: false, logged: false)
        let logged = RawSession(id: "sess-cowork-0500", origin: .cowork, times: [utc("2026-10-12T10:00:00Z"), utc("2026-10-12T10:10:00Z")],
                                title: "Log title", firstMessage: "the ask", folders: ["other"], scheduled: true, logged: true)
        let merged = CoworkMerge.merge(desktop: [desktop], log: [logged])
        #expect(merged.count == 1)
        let m = merged[0]
        #expect(m.id == "Sess-Cowork-0500")
        #expect(m.title == "Old title")
        #expect(m.firstMessage == "the ask")
        #expect(m.folders == ["harbor-site"])
        #expect(m.scheduled && m.logged)
        #expect(m.times.count == 2)
    }
}
