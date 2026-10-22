import Foundation
import Testing
@testable import TidemarkCore

@Suite struct DeleteAndInstructionTests {
    private func filled(folder: URL = tempDir()) throws -> CalendarStore {
        let s = CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9)), storeSession("sess-tide-0002", start: local(2026, 9, 6, 9))], throwing: true)
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9), minutes: 40)], throwing: true)   // makes a backup
        try s.apply(NameChange(kind: .projects, key: "tide-tables", name: .some("Tides")))
        try s.save(WeekReport(weekStart: "2026-10-05", lines: ["One"], author: .tidemark, written: local(2026, 10, 7)))
        let copy = tempDir().appendingPathComponent("old")
        try FileManager.default.copyItem(at: fixtureURL("legacy"), to: copy)
        _ = try s.importLegacy(from: copy)
        return s
    }

    private func contents(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func deleteAllEmptiesTheCalendar() throws {
        let folder = tempDir()
        let s = try filled(folder: folder)
        #expect(contents(folder).count >= 5)   // format, sessions, names, reports, backups, legacy
        try s.deleteAll()
        #expect(contents(folder).isEmpty)
        #expect(s.storedSessions.isEmpty && s.names == NameBook() && s.savedReports.isEmpty && s.problems.isEmpty)
        #expect(s.week(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 10, 21)).sessions == 0)
        // A fresh store sees nothing, and the emptied calendar can be written again.
        #expect(CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork).storedSessions.isEmpty)
        try s.absorb([storeSession("sess-tide-0009", start: local(2026, 10, 8, 9))], throwing: true)
        #expect(s.storedSessions.map(\.id) == ["sess-tide-0009"])
    }

    @Test func deleteAllKeepsImportSource() throws {
        let folder = tempDir()
        let s = try filled(folder: folder)
        let source = folder.appendingPathComponent("import-source/data/weeks")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appendingPathComponent("2026-10-05.json"))
        try s.deleteAll()
        #expect(contents(folder) == ["import-source"])
        #expect(try Data(contentsOf: source.appendingPathComponent("2026-10-05.json")) == Data("{}".utf8))
    }

    @Test func deleteAllWorksOnAFolderThatIsNotThereOrIsReadOnlyBecauseOfAnUnreadableFile() throws {
        let missing = CalendarStore(folder: tempDir().appendingPathComponent("nothing"), home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        try missing.deleteAll()
        let folder = tempDir()
        try Data(#"{"format":"tidemark-calendar","version":2}"#.utf8).write(to: folder.appendingPathComponent("format.json"))
        let newer = CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        #expect(!newer.problems.isEmpty)
        try newer.deleteAll()
        #expect(newer.problems.isEmpty)
        try newer.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 6, 9))], throwing: true)
    }

    @Test func instructionNamesTheFolderAndFields() {
        let text = CoworkInstruction.text(folderName: "Tidemark Log")
        #expect(text.contains("\"Tidemark Log/tidemark-log.jsonl\""))
        for field in ["\"id\"", "\"start\"", "\"end\"", "\"title\"", "\"ask\"", "\"folders\""] { #expect(text.contains(field)) }
        #expect(text.contains("3 to 6 words"))
        #expect(text.contains("under 150 characters"))
        #expect(text.contains("Never let the log hold up or change the task"))
        #expect(text.contains("Skip turns where you used no tools"))
        #expect(CoworkInstruction.text(folderName: "My Log").contains("My Log/tidemark-log.jsonl"))
        #expect(CoworkInstruction.text() == CoworkInstruction.text(folderName: AppIdentity.coworkLogFolderName))
        // The example line is valid JSON the Cowork reader accepts.
        let example = text.split(separator: "\n").first { $0.hasPrefix("{\"id\"") }
        #expect(example != nil)
        let folder = tempDir()
        try? Data((example.map(String.init) ?? "").utf8).write(to: folder.appendingPathComponent("tidemark-log.jsonl"))
        #expect(CoworkLogReader.read(folder: folder, since: nil).sessions.map(\.id) == ["cse_Abc123"])
    }

    @Test func instructionHasNoPrivateBits() {
        let text = CoworkInstruction.text(folderName: AppIdentity.coworkLogFolderName)
        for word in ["OneDrive", "driveId", "/Users/", "@", "http", "Documents/Claude"] { #expect(!text.contains(word), "found \(word)") }
    }
}
