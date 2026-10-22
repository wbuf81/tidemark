import Foundation
import Testing
@testable import TidemarkCore

@Suite struct CalendarFilesTests {
    private func session(_ id: String, start: Date, minutes: Double = 30, title: String? = nil) -> CalendarSession {
        CalendarSession(id: id, origin: .claudeCode, title: title, root: "/Users/you/tide-tables",
                        blocks: [Block(start: start, end: start.addingTimeInterval(minutes * 60))],
                        commits: [Commit(sha: "abc123", time: start.addingTimeInterval(60), repo: "/Users/you/tide-tables", subject: "Add tide chart")],
                        lastActivity: start.addingTimeInterval(minutes * 60))
    }

    private func files(_ folder: URL = tempDir()) -> (CalendarFiles, URL) {
        (CalendarFiles(folder: folder, calendar: newYork), folder)
    }

    private func backups(_ folder: URL, _ prefix: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("backups").path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }
    }

    @Test func roundTripsAMonth() throws {
        let (f, _) = files()
        let list = [session("sess-tide-0001", start: local(2026, 10, 6, 9), title: "Chart work"),
                    session("sess-tide-0002", start: local(2026, 10, 7, 14))]
        try f.saveMonth("2026-10", list)
        #expect(try f.loadMonth("2026-10") == list)
        #expect(try f.loadMonth("2026-09").isEmpty)
        #expect(f.storedMonths() == ["2026-10"])
        #expect(f.readOnlyReason == nil)
    }

    @Test func writeIsAtomicAndBacksUp() throws {
        let (f, folder) = files()
        for n in 1...11 { try f.saveMonth("2026-10", [session("sess-tide-\(n)", start: local(2026, 10, 6, 9))]) }
        #expect(backups(folder, "sessions-2026-10.").count == 10)
        for n in 12...14 { try f.saveMonth("2026-10", [session("sess-tide-\(n)", start: local(2026, 10, 6, 9))]) }
        #expect(backups(folder, "sessions-2026-10.").count == 10)
        // The newest backup holds the version before the last save.
        let newest = backups(folder, "sessions-2026-10.").sorted().last!
        let data = try Data(contentsOf: folder.appendingPathComponent("backups").appendingPathComponent(newest))
        #expect(String(decoding: data, as: UTF8.self).contains("sess-tide-13"))
        // No temp files are left behind.
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("sessions").path)
        #expect(left == ["2026-10.json"])
        #expect(try f.loadMonth("2026-10").map(\.id) == ["sess-tide-14"])
    }

    @Test func corruptMonthIsNeverWrittenOver() throws {
        let (f, folder) = files()
        try f.saveMonth("2026-09", [session("sess-tide-0001", start: local(2026, 9, 8, 9))])
        let path = folder.appendingPathComponent("sessions/2026-10.json")
        let garbage = Data([0x7b, 0x22, 0xff, 0x00, 0x01])
        try garbage.write(to: path)
        #expect(throws: (any Error).self) { try f.loadMonth("2026-10") }
        #expect(throws: (any Error).self) { try f.saveMonth("2026-10", [session("sess-tide-0002", start: local(2026, 10, 6, 9))]) }
        #expect(try Data(contentsOf: path) == garbage)
        let problem = try #require(f.readOnlyReason)
        #expect(problem.title == "A calendar file couldn’t be read")
        #expect(problem.detail == "2026-10.json is kept as it was. Tidemark won’t write over it.")
        // Other files still work.
        try f.saveMonth("2026-09", [session("sess-tide-0003", start: local(2026, 9, 9, 9))])
        try f.saveNames(NameBook())
        #expect(try Data(contentsOf: path) == garbage)
    }

    @Test func newerFormatIsReadOnly() throws {
        let (f, folder) = files()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("sessions/2026-10.json")
        let newer = Data(#"{"version":2,"sessions":[],"somethingNew":true}"#.utf8)
        try newer.write(to: path)
        #expect(try f.loadMonth("2026-10").isEmpty)   // a newer file is read as far as it decodes
        try Data(#"{"version":2,"sessions":"a different shape"}"#.utf8).write(to: folder.appendingPathComponent("sessions/2026-11.json"))
        #expect(throws: (any Error).self) { try f.loadMonth("2026-11") }
        #expect(throws: (any Error).self) { try f.saveMonth("2026-09", [session("sess-tide-0001", start: local(2026, 9, 8, 9))]) }
        #expect(throws: (any Error).self) { try f.saveNames(NameBook()) }
        #expect(try Data(contentsOf: path) == newer)
        let problem = try #require(f.readOnlyReason)
        #expect(problem.title == "Tidemark’s calendar was saved by a newer version")
        #expect(problem.detail == "Update Tidemark to change it. Everything still shows.")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("sessions/2026-09.json").path))
    }

    @Test func refreshNeverDropsSessionsWhoseFileIsGone() {
        let old = session("sess-tide-old", start: local(2026, 9, 1, 9))
        let kept = session("sess-tide-kept", start: local(2026, 10, 5, 9), title: "before")
        let changed = session("sess-tide-kept", start: local(2026, 10, 5, 9), minutes: 90, title: "after")
        let fresh = session("sess-tide-new", start: local(2026, 10, 6, 9))
        let merged = CalendarFiles.merge(stored: [old, kept], refreshed: [changed, fresh])
        #expect(merged.map(\.id) == ["sess-tide-old", "sess-tide-kept", "sess-tide-new"])
        #expect(merged[1].title == "after")
        #expect(CalendarFiles.merge(stored: [old], refreshed: []) == [old])
        #expect(CalendarFiles.merge(stored: [], refreshed: [fresh, fresh]).count == 1)
    }

    @Test func sessionStoredUnderItsFirstMonth() throws {
        let (f, _) = files()
        let spanning = session("sess-tide-0001", start: local(2026, 9, 30, 23), minutes: 120)
        #expect(CalendarFiles.month(of: spanning, calendar: newYork) == "2026-09")
        let other = session("sess-tide-0002", start: local(2026, 10, 1, 9))
        try f.save(sessions: [spanning, other])
        #expect(try f.loadMonth("2026-09").map(\.id) == ["sess-tide-0001"])
        #expect(try f.loadMonth("2026-10").map(\.id) == ["sess-tide-0002"])
        #expect(f.loadAllSessions().map(\.id) == ["sess-tide-0001", "sess-tide-0002"])
    }

    @Test func namesRoundTrip() throws {
        let (f, _) = files()
        #expect(try f.loadNames() == NameBook())
        var book = NameBook()
        book.sessions["Email Brief*"] = NameEntry(name: "Daily brief", tags: ["mail"], project: "Harbor Labs")
        book.projects["tide-tables"] = NameEntry(hideTitles: true)
        book.projectFolders["lighthouse-api"] = "Lighthouse API"
        try f.saveNames(book)
        #expect(try f.loadNames() == book)
    }

    @Test func reportsRoundTrip() throws {
        let (f, _) = files()
        #expect(try f.loadReports().isEmpty)
        let r = WeekReport(weekStart: "2026-10-19", lines: ["One", "Two", "Three"], days: ["2026-10-20": "Tides"], author: .tidemark,
                           written: utc("2026-10-21T15:32:00Z"))
        try f.saveReports([r])
        #expect(try f.loadReports() == [r])
    }

    @Test func lastRefreshKept() throws {
        let (f, folder) = files()
        #expect(f.loadLastRefresh() == nil)
        let when = utc("2026-10-21T15:32:00Z")
        try f.saveLastRefresh(when)
        try f.saveNames(NameBook())
        try f.saveMonth("2026-10", [session("sess-tide-0001", start: local(2026, 10, 6, 9))])
        #expect(CalendarFiles(folder: folder).loadLastRefresh() == when)
        let text = String(decoding: try Data(contentsOf: folder.appendingPathComponent("format.json")), as: UTF8.self)
        #expect(text.contains("tidemark-calendar"))
    }
}
