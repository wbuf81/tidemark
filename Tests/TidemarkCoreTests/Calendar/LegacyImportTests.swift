import Foundation
import Testing
@testable import TidemarkCore

@Suite struct LegacyImportTests {
    private let tide = "/Users/you/code/tide-tables"

    /// A copy of the invented old calendar in a temp folder, so nothing in the repository is ever touched.
    private func oldCalendar() throws -> URL {
        let copy = tempDir().appendingPathComponent("old")
        try FileManager.default.copyItem(at: fixtureURL("legacy"), to: copy)
        return copy
    }

    private func store(folder: URL = tempDir()) -> CalendarStore {
        CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
    }

    private func snapshot(_ folder: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let url as URL in items {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { out[url.path + "/"] = Data(); continue }
            out[url.path] = try? Data(contentsOf: url)
        }
        return out
    }

    /// A one-week old calendar written into a temp folder: one session with one block and one commit.
    private func tinyCalendar(blockStart: String, blockEnd: String, total: Double = 0, extraSession: Bool = false) throws -> URL {
        let root = tempDir().appendingPathComponent("old")
        let weeks = root.appendingPathComponent("data/weeks")
        try FileManager.default.createDirectory(at: weeks, withIntermediateDirectories: true)
        let days = (0...7).map { "\"2026-10-\(String(format: "%02d", 5 + $0))T00:00:00-04:00\"" }.joined(separator: ",")
        let json = """
        {"start":"2026-10-05","week":{"days":[\(days)]},"total":\(total),
         "sessions":[{"id":"sess-tide-0100","source":"Claude Code","root":"\(tide)","origin":"\(tide)","title":"Edge","git":true}],
         "blocks":[{"s":0,"start":"\(blockStart)","end":"\(blockEnd)","commits":[{"h":"abc1234","subject":"Late commit","files":[]}]}]}
        """
        try Data(json.utf8).write(to: weeks.appendingPathComponent("2026-10-05.json"))
        return root
    }

    @Test func aCommitInABlockCutAtTheWeekEndStaysInThatWeek() throws {
        let s = store()
        _ = try s.importLegacy(from: try tinyCalendar(blockStart: "2026-10-11T22:00:00-04:00", blockEnd: "2026-10-12T00:00:00-04:00"))
        let c = try #require(s.storedSessions.first?.commits.first)
        #expect(c.time < local(2026, 10, 12))
        #expect(c.time >= local(2026, 10, 11, 22))
    }

    @Test func theTotalsCheckSeesWhereAnExistingSessionWon() throws {
        let s = store()
        try s.absorb([storeSession("sess-tide-0001", start: local(2026, 10, 5, 9), minutes: 10)], throwing: true)   // shorter than the old calendar's
        let result = try s.importLegacy(from: try oldCalendar())
        #expect(result.sessionsKept == 1)
        #expect(result.mismatches.contains("2026-10-05"))
    }

    @Test func anImportIntoAReadOnlyCalendarCopiesNothing() throws {
        let folder = tempDir()
        try Data(#"{"format":"tidemark-calendar","version":2}"#.utf8).write(to: folder.appendingPathComponent("format.json"))
        let s = store(folder: folder)
        #expect(throws: (any Error).self) { _ = try s.importLegacy(from: try oldCalendar()) }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("legacy").path))
        #expect(s.storedSessions.isEmpty)
    }

    @Test func findsTheOldCalendar() throws {
        let s = store()
        let found = LegacyFound(weeks: 3, first: "2026-10-05", last: "2026-10-19", hasNames: true, hasReports: true)
        #expect(s.findLegacy(in: fixtureURL("legacy")) == found)
        #expect(s.findLegacy(in: fixtureURL("legacy/data")) == found)
        #expect(s.findLegacy(in: tempDir()) == nil)
        #expect(s.findLegacy(in: tempDir().appendingPathComponent("missing")) == nil)
    }

    @Test func importsWeeksNamesAndReports() throws {
        let folder = tempDir()
        let s = store(folder: folder)
        let result = try s.importLegacy(from: try oldCalendar())
        #expect(result.weeks == 3)
        #expect(result.sessionsAdded == 7 && result.sessionsKept == 0)
        let stored = Dictionary(uniqueKeysWithValues: s.storedSessions.map { ($0.id, $0) })
        let a = try #require(stored["sess-tide-0001"])
        #expect(a.origin == .claudeCode && a.title == "Chart export" && a.root == tide && a.isGit)
        #expect(a.firstMessage == nil)   // the first-messages switch is off
        #expect(a.commits == [Commit(sha: "9eba146", time: local(2026, 10, 5, 10, 30), repo: tide, subject: "Add chart export",
                                     files: ["Sources/Chart.swift", "Tests/ChartTests.swift"])])
        #expect(a.blocks == [Block(start: local(2026, 10, 5, 9), end: local(2026, 10, 5, 10, 30)), Block(start: local(2026, 10, 5, 13), end: local(2026, 10, 5, 14))])
        #expect(a.lastActivity == local(2026, 10, 5, 14))
        #expect(stored["sess-tide-0002"]?.title == "Sign-in loop")   // from labels.json
        let cowork = try #require(stored["sess-cowork-0001"])
        #expect(cowork.origin == .cowork && cowork.root == "Cowork" && cowork.folders == ["Daily briefs"])
        #expect(cowork.scheduled && cowork.logged && !cowork.isGit)
        #expect(stored["sess-tide-0004"]?.commits.map(\.sha) == ["1234abc", "abcdef0"])

        let names = s.names
        #expect(names.projects["tide-tables"] == NameEntry(name: "Tide Tables", tags: ["work"]))
        #expect(names.projects["Side projects"]?.hideTitles == true)
        #expect(names.sessions["Daily email*"] == NameEntry(name: "Daily email brief", tags: ["mail"]))
        #expect(names.sessions["Chart export"]?.project == "Lighthouse API")
        #expect(names.folders["Daily briefs"]?.project == "Email")
        #expect(names.projectFolders == ["lighthouse-api": "Lighthouse API"])

        let reports = s.savedReports
        #expect(reports.count == 1)
        #expect(reports[0].weekStart == "2026-10-05" && reports[0].author == .imported)
        #expect(reports[0].lines == ["Shipped the chart export.", "Fixed the sign-in loop in lighthouse-api.", "Most time went on tide-tables."])
        #expect(reports[0].days == ["2026-10-05": "Chart export.", "2026-10-06": "Sign-in loop."])

        // It was saved, not just remembered.
        let again = store(folder: folder)
        #expect(again.storedSessions.count == 7)
        #expect(again.names == names)
        #expect(again.savedReports.map(\.weekStart) == ["2026-10-05"])
    }

    @Test func firstMessagesAreKeptOnlyWhenTheSwitchIsOn() throws {
        let s = store()
        var on = SourceSwitches()
        on.firstMessages = true
        s.setRefreshProblems([], switches: on)
        _ = try s.importLegacy(from: try oldCalendar())
        #expect(s.storedSessions.first { $0.id == "sess-tide-0001" }?.firstMessage == "Add the chart export")
    }

    // L1: the import runs before the first refresh now, so it goes by the switches the user has chosen, not the last refresh's.
    @Test func theChosenSwitchesDecideFirstMessagesNotTheLastRefresh() throws {
        let s = store()
        var chosen = SourceSwitches()
        chosen.firstMessages = true
        _ = try s.importLegacy(from: try oldCalendar(), sources: chosen)
        #expect(s.storedSessions.first { $0.id == "sess-tide-0001" }?.firstMessage == "Add the chart export")
        let off = store()
        _ = try off.importLegacy(from: try oldCalendar(), sources: SourceSwitches())
        #expect(off.storedSessions.first { $0.id == "sess-tide-0001" }?.firstMessage == nil)
    }

    @Test func weekTotalsMatchAfterImport() throws {
        let s = store()
        let result = try s.importLegacy(from: try oldCalendar())
        #expect(result.mismatches.isEmpty)
        let now = local(2026, 10, 21, 12)
        #expect(s.week(containing: local(2026, 10, 7), weekStart: .monday, now: now).total == 16_800)
        #expect(s.week(containing: local(2026, 10, 14), weekStart: .monday, now: now).total == 14_400)
        #expect(s.week(containing: local(2026, 10, 21), weekStart: .monday, now: now).total == 9_000)   // two overlapping sessions count once
        #expect(s.week(containing: local(2026, 10, 7), weekStart: .monday, now: now).perDay == [9000, 3600, 0, 0, 600, 0, 3600])
    }

    @Test func aWeekWhoseTotalDiffersIsListed() throws {
        let old = try oldCalendar()
        let file = old.appendingPathComponent("data/weeks/2026-10-19.json")
        let text = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "\"total\": 9000.0", with: "\"total\": 9100.0")
        try Data(text.utf8).write(to: file)
        let result = try store().importLegacy(from: old)
        #expect(result.mismatches == ["2026-10-19"])
        // Within a minute is fine.
        try Data(text.replacingOccurrences(of: "\"total\": 9100.0", with: "\"total\": 9050.0").utf8).write(to: file)
        #expect(try store().importLegacy(from: old).mismatches.isEmpty)
    }

    @Test func sourceFolderUnchanged() throws {
        let old = try oldCalendar()
        let before = snapshot(old)
        let folder = tempDir()
        let s = store(folder: folder)
        _ = try s.importLegacy(from: old)
        _ = try s.importLegacy(from: old)
        #expect(snapshot(old) == before)
        // Every source file is kept verbatim in legacy/.
        for name in ["weeks/2026-10-05.json", "weeks/2026-10-12.json", "weeks/2026-10-19.json", "names.js", "projects.json", "labels.json", "reports.json"] {
            #expect(try Data(contentsOf: folder.appendingPathComponent("legacy/\(name)")) == Data(contentsOf: old.appendingPathComponent("data/\(name)")))
        }
    }

    @Test func existingSessionsWin() throws {
        let s = store()
        try s.absorb([CalendarSession(id: "sess-tide-0005", origin: .claudeCode, title: "My own title", root: tide, isGit: true,
                                      blocks: [Block(start: local(2026, 10, 20, 9), end: local(2026, 10, 20, 9, 30))], lastActivity: local(2026, 10, 20, 9, 30))], throwing: true)
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(name: "Mine")
        try s.replaceNames(book)
        let result = try s.importLegacy(from: try oldCalendar())
        #expect(result.sessionsAdded == 6 && result.sessionsKept == 1)
        let kept = try #require(s.storedSessions.first { $0.id == "sess-tide-0005" })
        #expect(kept.title == "My own title")
        #expect(kept.blocks.count == 1 && kept.blocks[0].end == local(2026, 10, 20, 9, 30))
        #expect(s.names.projects["tide-tables"]?.name == "Mine")                  // the user's own names win too
        #expect(s.names.projects["Side projects"]?.hideTitles == true)            // and the rest is added
    }

    @Test func blocksAcrossWeeksAreJoined() throws {
        let s = store()
        _ = try s.importLegacy(from: try oldCalendar())
        let night = try #require(s.storedSessions.first { $0.id == "sess-tide-0003" })
        #expect(night.blocks == [Block(start: local(2026, 10, 11, 23), end: local(2026, 10, 12, 1))])
        #expect(s.storedSessions.filter { $0.id == "sess-tide-0003" }.count == 1)
    }

    @Test func namesJsWithCommentHeader() throws {
        let withEquals = "// Names, written by the page.\n// Edit with care: a = b in a comment is fine.\nwindow.NAMES = {\n \"projects\": {\"x\": {\"name\": \"Ex\", \"hide_titles\": true}}\n};\n"
        let book = try #require(LegacyImport.parseNames(withEquals))
        #expect(book.projects["x"] == NameEntry(name: "Ex", hideTitles: true))
        #expect(LegacyImport.parseNames("window.NAMES = {\"folders\": {\"f\": {\"project\": \"P\"}}}")?.folders["f"]?.project == "P")
        #expect(LegacyImport.parseNames("window.NAMES = {};  \n\n")?.sessions.isEmpty == true)
        #expect(LegacyImport.parseNames("window.NAMES = {broken") == nil)
        #expect(LegacyImport.parseNames("nothing here") == nil)
    }

    @Test func importTwiceAddsNothing() throws {
        let folder = tempDir()
        let s = store(folder: folder)
        let old = try oldCalendar()
        _ = try s.importLegacy(from: old)
        let sessions = s.storedSessions, names = s.names, reports = s.savedReports
        let again = try s.importLegacy(from: old)
        #expect(again.sessionsAdded == 0 && again.sessionsKept == 7 && again.weeks == 3)
        #expect(s.storedSessions == sessions && s.names == names && s.savedReports == reports)
        #expect(store(folder: folder).storedSessions == sessions)
    }

    @Test func notAnOldCalendarThrows() {
        #expect(throws: LegacyImportError.notFound) { _ = try store().importLegacy(from: tempDir()) }
    }
}
