import Foundation
import Testing
@testable import TidemarkCore

@Suite struct WeekComputerTests {
    private let tide = "/Users/you/code/tide-tables"
    private let light = "/Users/you/code/lighthouse-api"
    private let notes = "/Users/you/code/field-notes"

    private func block(_ start: Date, _ minutes: Double) -> Block { Block(start: start, end: start.addingTimeInterval(minutes * 60)) }

    private func session(_ id: String, _ root: String, _ blocks: [Block], title: String? = nil, folders: [String] = [],
                         origin: SessionOrigin = .claudeCode, commits: [Commit] = [], first: String? = nil) -> CalendarSession {
        CalendarSession(id: id, origin: origin, title: title, firstMessage: first, root: root, folders: folders,
                        isGit: origin == .claudeCode, blocks: blocks, commits: commits, lastActivity: blocks.map(\.end).max()!)
    }

    private func commit(_ sha: String, _ time: Date, _ repo: String, _ subject: String) -> Commit {
        Commit(sha: sha, time: time, repo: repo, subject: subject, files: ["Sources/A.swift"])
    }

    private func store(_ sessions: [CalendarSession], names: NameBook = NameBook(), calendar: Calendar = newYork, home: URL = fakeHome()) throws -> CalendarStore {
        let s = CalendarStore(folder: tempDir(), home: home, environment: [:], runner: NoRunner(), calendar: calendar)
        try s.absorb(sessions, throwing: true)
        if names != NameBook() { try s.replaceNames(names) }
        return s
    }

    private func week(_ s: CalendarStore, _ day: Date = local(2026, 10, 7), now: Date = local(2026, 11, 1), start: WeekStart = .monday) -> WeekModel {
        s.week(containing: day, weekStart: start, now: now)
    }

    // MARK: Ported from the old calendar

    @Test func hoursPerProjectCountParallelSessionsOnce() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 5, 9), 120)]),
                           session("sess-b", tide, [block(local(2026, 10, 5, 10), 120)]),
                           session("sess-c", light, [block(local(2026, 10, 5, 14), 60)])])
        let w = week(s)
        #expect(w.projects.map(\.name) == ["tide-tables", "lighthouse-api"])
        #expect(w.projects.map(\.seconds) == [3 * 3600, 3600])
        #expect(w.projects[0].sessions == 2)
        #expect(w.total == 4 * 3600)
        #expect(w.sessions == 3)
    }

    @Test func aMovedSessionTakesItsHours() throws {
        var book = NameBook()
        book.sessions["Legend fixes"] = NameEntry(project: "tide-tables")
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 5, 9), 60)], title: "Chart export"),
                           session("sess-b", light, [block(local(2026, 10, 5, 10), 60)], title: "Legend fixes")], names: book)
        let w = week(s)
        #expect(w.projects.map(\.name) == ["tide-tables"])
        #expect(w.projects[0].seconds == 2 * 3600)
        #expect(w.items.map(\.project) == ["tide-tables", "tide-tables"])
    }

    @Test func rollupByProjectAndTag() throws {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(tags: ["work"])
        book.projects["field-notes"] = NameEntry(tags: ["work"])
        book.sessions["Daily brief"] = NameEntry(tags: ["mail"])
        let s = try store([
            session("sess-a", tide, [block(local(2026, 10, 5, 9), 120)], title: "Chart export",
                    commits: [commit("aaa1111", local(2026, 10, 5, 10), tide, "Add chart"), commit("aaa2222", local(2026, 10, 5, 10, 30), tide, "Add legend")]),
            session("sess-b", notes, [block(local(2026, 10, 5, 12), 60)], title: "Drafts"),
            session("sess-c", "Cowork", [block(local(2026, 10, 6, 7), 60)], title: "Daily brief", origin: .cowork)], names: book)
        let w = week(s)
        let work = w.tags.first { $0.tag == "work" }
        #expect(work?.seconds == 10_800.0)
        #expect(work?.sessions == 2)
        #expect(work?.commits == 2)
        #expect(w.tags.first { $0.tag == "mail" }?.seconds == 3600)
        #expect(w.tags.map(\.tag) == ["work", "mail"])
        #expect(w.projects.first { $0.name == "tide-tables" }?.commits == 2)
    }

    @Test func aWeek() throws {
        // An idle gap of 80 minutes makes two blocks; a Cowork task is moved to Email by its folder.
        var book = NameBook()
        book.folders["Daily briefs"] = NameEntry(project: "Email")
        book.sessions["Tide chart"] = NameEntry(name: "Tide charts")
        let t0 = local(2026, 10, 6, 9)
        let s = try store([
            session("sess-a", tide, [block(t0, 20), block(t0.addingTimeInterval(100 * 60), 10)], title: "Tide chart"),
            session("sess-c", "Cowork", [block(local(2026, 10, 6, 14), 5)], title: "Daily email brief", folders: ["Daily briefs"], origin: .cowork)], names: book)
        let w = week(s)
        #expect(w.total == 35 * 60)
        #expect(w.projects.first { $0.name == "Email" }?.seconds == 300.0)
        #expect(w.projects.first { $0.name == "Email" }?.sessions == 1)
        #expect(w.items.first { $0.sessionID == "sess-a" }?.title == "Tide charts")
        #expect(w.items.first { $0.sessionID == "sess-c" }?.origin == .cowork)
        #expect(w.claudeCodeSeconds == 30 * 60)
        #expect(w.coworkSeconds == 5 * 60)
        #expect(w.dayNotes[1] == "Tide charts; Daily email brief.")
        #expect(w.dayNotes[0] == "")
    }

    @Test func aProjectThatHidesTitlesSaysNothingAboutThem() throws {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(project: "Other development")
        book.projects["Other development"] = NameEntry(hideTitles: true)
        let s = try store([
            session("sess-a", tide, [block(local(2026, 10, 6, 9), 60)], title: "Fix the harbor sonar parser",
                    commits: [commit("aaa1111", local(2026, 10, 6, 9, 30), tide, "Patch the harbor sonar parser")],
                    first: "Please fix the harbor sonar parser")], names: book)
        let w = week(s)
        #expect(w.items.first?.title == "Other development")
        #expect(w.items.first?.titlesHidden == true)
        #expect(w.items.first?.commitSubjects == [])
        #expect(w.items.first?.commits == 1)
        #expect(w.projects.map(\.name) == ["Other development"])
        #expect(!String(describing: w).contains("sonar"))
        #expect(!String(describing: s.month(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 11, 1))).contains("sonar"))
        #expect(!String(describing: s.weekSummary(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 11, 1))).contains("sonar"))
    }

    @Test func aFirstMessageNamingAHiddenProjectStaysOut() throws {
        var book = NameBook()
        book.projects["tidal"] = NameEntry(project: "Other development")
        book.projects["Other development"] = NameEntry(hideTitles: true)
        let s = try store([
            session("sess-a", light, [block(local(2026, 10, 6, 9), 60)], title: "Port the tidal-sync login",
                    commits: [commit("aaa1111", local(2026, 10, 6, 9, 30), light, "Reuse the Tidal cache"),
                              commit("aaa2222", local(2026, 10, 6, 9, 40), light, "Tidalwave notes")]),
            session("sess-b", light, [block(local(2026, 10, 6, 11), 60)], title: "Tidalwave notes"),
            session("sess-t", "/Users/you/code/tidal", [block(local(2026, 10, 6, 13), 30)], title: "Anything")], names: book)
        let w = week(s)
        let a = w.items.first { $0.sessionID == "sess-a" }!
        #expect(a.title == "lighthouse-api")                    // the title names the hidden project, so it is not shown
        #expect(a.commitSubjects == ["Tidalwave notes"])        // whole words only
        #expect(w.items.first { $0.sessionID == "sess-b" }?.title == "Tidalwave notes")
        #expect(!w.dayNotes[1].lowercased().contains("tidal-sync"))
        #expect(w.dayNotes[1] == "lighthouse-api; Tidalwave notes.")
    }

    // MARK: Boundaries

    @Test func blockAcrossMidnightCountsOnBothDays() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 22), 180)])])
        let w = week(s)
        #expect(w.perDay[1] == 2 * 3600)
        #expect(w.perDay[2] == 3600)
        #expect(w.total == 3 * 3600)
        #expect(w.sessions == 1)
        #expect(w.items.map(\.day) == [1, 2])
        #expect(w.items.map(\.id) == ["sess-a|2026-10-06", "sess-a|2026-10-07"])
    }

    @Test func blockAcrossWeekBoundaryClippedInBoth() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 11, 23), 120)])])
        let first = week(s, local(2026, 10, 8))
        let second = week(s, local(2026, 10, 14))
        #expect(first.perDay[6] == 3600 && first.total == 3600)
        #expect(second.perDay[0] == 3600 && second.total == 3600)
        #expect(first.sessions == 1 && second.sessions == 1)
    }

    @Test func aLoneTimestampStillCountsTheSession() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 9), 0)])])
        let w = week(s)
        #expect(w.sessions == 1)
        #expect(w.total == 0)
        #expect(w.items.count == 1)
    }

    @Test func sundayWeeksAddUpToTheSameMonth() throws {
        var sessions: [CalendarSession] = []
        for d in stride(from: 1, through: 31, by: 3) {
            sessions.append(session("sess-\(d)", tide, [block(local(2026, 10, d, 9), 90), block(local(2026, 10, d, 23), 120)]))
        }
        sessions.append(session("sess-edge", light, [block(local(2026, 9, 30, 23), 180)]))
        sessions.append(session("sess-late", light, [block(local(2026, 10, 31, 23), 180)]))
        let s = try store(sessions)
        func total(_ start: WeekStart) -> TimeInterval {
            s.month(containing: local(2026, 10, 15), weekStart: start, now: local(2026, 11, 5)).weeks.flatMap { $0 }.filter(\.inMonth).reduce(0) { $0 + $1.seconds }
        }
        #expect(total(.monday) == total(.sunday))
        #expect(total(.monday) > 0)
        // The whole of October by weeks: Monday weeks and Sunday weeks both cover it.
        func weeksTotal(_ start: WeekStart) -> TimeInterval {
            var sum: TimeInterval = 0
            for model in s.month(containing: local(2026, 10, 15), weekStart: start, now: local(2026, 11, 5)).weeks {
                let w = s.week(containing: model[0].date, weekStart: start, now: local(2026, 11, 5))
                for (i, day) in model.enumerated() where day.inMonth { sum += w.perDay[i] }
            }
            return sum
        }
        #expect(weeksTotal(.monday) == weeksTotal(.sunday))
        #expect(weeksTotal(.monday) == total(.monday))
    }

    @Test func mondayAndSundayWeeksEachAddUpToTheSameWorkAcrossAMonth() throws {
        // Work around both kinds of week boundary (Sat to Sun and Sun to Mon), none on 4 Oct or 1 Nov, which the two kinds of week disagree on.
        let blocks: [(Date, Double)] = [
            (local(2026, 10, 5, 9), 90), (local(2026, 10, 10, 23), 120),   // crosses Saturday to Sunday (a Sunday week's start)
            (local(2026, 10, 11, 23), 180),                                   // crosses Sunday to Monday (a Monday week's start)
            (local(2026, 10, 17, 22), 240), (local(2026, 10, 18, 23, 30), 60),
            (local(2026, 10, 24, 23), 120), (local(2026, 10, 30, 9), 60)]
        let s = try store(blocks.enumerated().map { session("sess-\($0.offset)", tide, [block($0.element.0, $0.element.1)]) })
        let expected = blocks.reduce(0) { $0 + $1.1 * 60 }
        func sum(_ start: WeekStart, firstWeek: Date, weeks: Int) -> TimeInterval {
            (0..<weeks).reduce(0) { acc, n in
                let day = newYork.date(byAdding: .day, value: 7 * n, to: firstWeek)!
                return acc + s.week(containing: day, weekStart: start, now: local(2026, 11, 5)).total
            }
        }
        #expect(sum(.monday, firstWeek: local(2026, 10, 5), weeks: 4) == expected)   // 5 Oct to 1 Nov
        #expect(sum(.sunday, firstWeek: local(2026, 10, 4), weeks: 4) == expected)   // 4 Oct to 31 Oct
        // And the month grid's in-month days add up to the same.
        for start in [WeekStart.monday, .sunday] {
            let month = s.month(containing: local(2026, 10, 15), weekStart: start, now: local(2026, 11, 5))
            #expect(month.weeks.flatMap { $0 }.filter(\.inMonth).reduce(0) { $0 + $1.seconds } == expected)
        }
    }

    @Test func dstWeekAddsUp() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let sunday = london.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let monday = london.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        let s = try store([CalendarSession(id: "sess-a", origin: .claudeCode, root: tide, isGit: true,
                                           blocks: [Block(start: sunday, end: monday)], lastActivity: monday)], calendar: london)
        let w = s.week(containing: sunday, weekStart: .monday, now: monday)
        #expect(w.days.count == 8)
        #expect(w.perDay.count == 7)
        #expect(w.perDay[6] == 25 * 3600)
        #expect(w.total == 25 * 3600)
        #expect(w.sessions == 1)
    }

    // MARK: Week figures

    @Test func colorIndexStableByRank() throws {
        var list: [CalendarSession] = []
        for n in 0..<8 {
            list.append(session("sess-\(n)", "/Users/you/code/proj-\(n)", [block(local(2026, 10, 5, 8, 0).addingTimeInterval(Double(n) * 10_000), Double(90 - n * 10))]))
        }
        let s = try store(list)
        let w = week(s)
        #expect(w.projects.map(\.name) == (0..<8).map { "proj-\($0)" })
        #expect(w.projects.map(\.colorIndex) == [0, 1, 2, 3, 4, 5, 6, 6])
        #expect(w.items.allSatisfy { item in item.colorIndex == w.projects.first { $0.name == item.project }?.colorIndex })
        #expect(week(s) == w)
    }

    @Test func weekSummaryMatchesTheWeek() throws {
        let now = local(2026, 10, 14, 12)
        let s = try store([
            session("sess-p", tide, [block(local(2026, 10, 1, 9), 60)]),
            session("sess-a", tide, [block(local(2026, 10, 12, 9), 120)], commits: [commit("aaa1111", local(2026, 10, 12, 10), tide, "Add chart")]),
            session("sess-b", light, [block(local(2026, 10, 13, 9), 60)])])
        let w = week(s, local(2026, 10, 13), now: now)
        let sum = s.weekSummary(containing: local(2026, 10, 13), weekStart: .monday, now: now)
        #expect(sum.format == "week-summary/1")
        #expect(sum.generated == now)
        #expect(sum.links == nil)
        #expect(sum.week.start == "2026-10-12" && sum.week.end == "2026-10-18")
        #expect(sum.week.seconds == w.total && sum.week.seconds == 3 * 3600)
        #expect(sum.week.sessions == 2 && sum.week.commits == 1)
        #expect(sum.week.days.map(\.seconds) == w.perDay)
        #expect(sum.week.days.map(\.commits) == w.commitsPerDay)
        #expect(sum.week.projects.map(\.name) == ["tide-tables", "lighthouse-api"])
        #expect(sum.week.previousSeconds == 0)   // nothing ran in the week before, but the calendar goes back further
        #expect(sum.weeks.last == WeekSummary.Total(start: "2026-10-12", seconds: 3 * 3600))
        #expect(sum.weeks.first?.start == "2026-09-28")
        let none = s.weekSummary(containing: local(2026, 9, 29), weekStart: .monday, now: now)
        #expect(none.week.previousSeconds == nil)
    }

    @Test func weekSummaryMergesProjectsShownUnderOneName() throws {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(name: "Tides")
        book.projects["field-notes"] = NameEntry(name: "Tides")
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 5, 9), 20)]), session("sess-b", notes, [block(local(2026, 10, 6, 9), 20)])], names: book)
        let sum = s.weekSummary(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 11, 1))
        #expect(sum.week.projects == [WeekSummary.Project(name: "Tides", seconds: 2400)])
    }

    @Test func runningAndPartial() throws {
        let home = fakeHome()
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data(#"{"cleanupPeriodDays": 7}"#.utf8).write(to: home.appendingPathComponent(".claude/settings.json"))
        let now = local(2026, 10, 21, 12)
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 21, 11, 30), 20)]),
                           session("sess-b", light, [block(local(2026, 10, 12, 11, 0), 20)])], home: home)
        let thisWeek = s.week(containing: now, weekStart: .monday, now: now)
        #expect(thisWeek.running == ["tide-tables"])
        #expect(!thisWeek.isPartial)
        let lastWeek = s.week(containing: local(2026, 10, 13), weekStart: .monday, now: now)
        #expect(lastWeek.running.isEmpty)
        #expect(lastWeek.isPartial)   // week start 12 Oct is more than 7 days before now
        let defaults = try store([session("sess-b", light, [block(local(2026, 10, 12, 11, 0), 20)])])
        #expect(!defaults.week(containing: local(2026, 10, 13), weekStart: .monday, now: now).isPartial)
    }

    @Test func commitsAndNoCommitFlags() throws {
        let now = local(2026, 10, 21, 12)
        let s = try store([
            session("sess-a", tide, [block(local(2026, 10, 12, 9), 60)], commits: [commit("aaa1111", local(2026, 10, 12, 9, 30), tide, "Add chart"),
                                                                                  commit("aaa2222", local(2026, 10, 13, 0, 2), tide, "Late fix")]),
            session("sess-b", tide, [block(local(2026, 10, 14, 9), 60)]),
            session("sess-c", "Cowork", [block(local(2026, 10, 14, 9), 60)], origin: .cowork),
            session("sess-d", tide, [block(local(2026, 10, 21, 11, 50), 5)])])
        let w = week(s, local(2026, 10, 13), now: now)
        #expect(w.commits == 2 && w.repos == 1)
        #expect(w.commitsPerDay == [1, 1, 0, 0, 0, 0, 0])
        func item(_ id: String) -> WeekItem { w.items.first { $0.sessionID == id }! }
        #expect(item("sess-a").commits == 1 && item("sess-a").commitSubjects == ["Add chart"])
        #expect(!item("sess-a").noCommit)
        #expect(item("sess-b").noCommit)
        #expect(!item("sess-c").noCommit)
        let current = week(s, now, now: now)
        #expect(current.items.first { $0.sessionID == "sess-d" }?.noCommit == false)   // still running
    }

    @Test func dayNotesAndBriefComeFromTheSavedReportOrTheTitles() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 5, 9), 60)], title: "Chart export"),
                           session("sess-b", tide, [block(local(2026, 10, 5, 12), 30)], title: "Legend"),
                           session("sess-c", tide, [block(local(2026, 10, 5, 15), 10)], title: "Typos"),
                           session("sess-d", light, [block(local(2026, 10, 6, 9), 60)], title: "Sign-in loop")])
        let plain = week(s)
        #expect(plain.dayNotes[0] == "Chart export; Legend.")
        #expect(plain.brief == plain.plainReport[0])
        #expect(plain.report == nil)
        try s.save(WeekReport(weekStart: "2026-10-05", lines: ["Shipped the chart export.", "Two", "Three"],
                              days: ["2026-10-06": "Fixed the sign-in loop."], author: .claudeCode, written: local(2026, 10, 9)))
        let saved = week(s)
        #expect(saved.brief == "Shipped the chart export.")
        #expect(saved.dayNotes[0] == "Chart export; Legend.")
        #expect(saved.dayNotes[1] == "Fixed the sign-in loop.")
        #expect(saved.report?.author == .claudeCode)
        #expect(saved.plainReport.count == 3)
    }

    @Test func problemsComeFromTheStore() throws {
        let folder = tempDir()
        try Data(#"{"format":"tidemark-calendar","version":2}"#.utf8).write(to: folder.appendingPathComponent("format.json"))
        let s = CalendarStore(folder: folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        #expect(week(s).problems.map(\.title) == ["Tidemark’s calendar was saved by a newer version"])
    }

    // MARK: Months, trends, names

    @Test func monthStartsOnTheRightMonday() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 1, 9), 60)])])
        let m = s.month(containing: local(2026, 10, 15), weekStart: .monday, now: local(2026, 10, 21, 11, 32))
        #expect(m.month == local(2026, 10, 1))
        #expect(m.weeks.count == 5)
        #expect(m.weeks.allSatisfy { $0.count == 7 })
        #expect(m.weeks[0][0].date == local(2026, 9, 28))
        #expect(m.weeks[0][0].inMonth == false)
        #expect(m.weeks[0][3].date == local(2026, 10, 1) && m.weeks[0][3].inMonth)
        #expect(m.weeks[0][3].seconds == 3600)
        #expect(m.weeks[4][6].date == local(2026, 11, 1) && !m.weeks[4][6].inMonth)
        #expect(m.weeks.flatMap { $0 }.filter(\.isToday).map(\.date) == [local(2026, 10, 21)])
        let sunday = s.month(containing: local(2026, 10, 15), weekStart: .sunday, now: local(2026, 10, 21))
        #expect(sunday.weeks[0][0].date == local(2026, 9, 27))
    }

    @Test func monthTopIsTheTwoLongestTitles() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 9), 30)], title: "Typos"),
                           session("sess-b", tide, [block(local(2026, 10, 6, 10), 120)], title: "Chart export"),
                           session("sess-c", light, [block(local(2026, 10, 6, 13), 60)], title: "Sign-in loop")])
        let day = s.month(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 11, 1)).weeks.flatMap { $0 }.first { $0.date == local(2026, 10, 6) }!
        #expect(day.top.map(\.title) == ["Chart export", "Sign-in loop"])
        #expect(day.top.map(\.colorIndex) == [0, 1])
        #expect(day.seconds == 210 * 60)
    }

    @Test func trendsQuarterHas13Weeks() throws {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(tags: ["feature"])
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 21, 9), 60)]),
                           session("sess-b", tide, [block(local(2026, 10, 14, 9), 120)]),
                           session("sess-c", light, [block(local(2026, 8, 3, 9), 30)]),
                           session("sess-old", light, [block(local(2026, 7, 1, 9), 600)])], names: book)
        let now = local(2026, 10, 21, 11, 32)
        let t = s.trends(endingWith: now, count: 13, grouping: .project, weekStart: .monday, now: now)
        #expect(t.weeks.count == 13)
        #expect(t.weeks.first == local(2026, 7, 27) && t.weeks.last == local(2026, 10, 19))
        #expect(t.lastIsPartial)
        #expect(t.rows.map(\.name) == ["tide-tables", "lighthouse-api"])
        #expect(t.rows[0].seconds.count == 13)
        #expect(t.rows[0].seconds[12] == 3600 && t.rows[0].seconds[11] == 7200 && t.rows[0].total == 10_800)
        #expect(t.rows[1].seconds[1] == 1800 && t.rows[1].total == 1800)    // July's session is outside the quarter
        let tags = s.trends(endingWith: now, count: 13, grouping: .tag, weekStart: .monday, now: now)
        #expect(tags.rows.map(\.name) == ["feature"])
        #expect(tags.rows[0].total == 10_800)
        let past = s.trends(endingWith: local(2026, 10, 14), count: 4, grouping: .project, weekStart: .monday, now: now)
        #expect(!past.lastIsPartial)
    }

    @Test func nameRowsListTitlesProjectsAndFolders() throws {
        var book = NameBook()
        book.sessions["Daily*"] = NameEntry(name: "Daily brief", tags: ["mail"])
        book.folders["Daily briefs"] = NameEntry(project: "Email")
        let now = local(2026, 10, 21, 12)
        let s = try store([
            session("sess-a", tide, [block(local(2026, 10, 20, 9), 120)], title: "Chart export"),
            session("sess-b", "Cowork", [block(local(2026, 10, 20, 7), 30)], title: "Daily email brief", folders: ["Daily briefs"], origin: .cowork),
            session("sess-c", "Cowork", [block(local(2026, 10, 19, 7), 30)], title: "Daily email brief", folders: ["Daily briefs"], origin: .cowork),
            session("sess-gone", light, [block(local(2026, 1, 5, 9), 30)], title: "Ancient work")], names: book)
        let titles = s.nameRows(.sessions, now: now)
        #expect(titles.map(\.key) == ["Chart export", "Daily email brief"])
        #expect(titles[0].seconds == 7200 && titles[0].currentProject == "tide-tables")
        #expect(titles[1].seconds == 3600 && titles[1].ruleKey == "Daily*")
        #expect(titles[1].entry.name == "Daily brief" && titles[1].entry.tags == ["mail"])
        #expect(titles[1].currentProject == "Email")
        #expect(titles[0].ruleKey == nil)
        let projects = s.nameRows(.projects, now: now)
        #expect(projects.map(\.key) == ["tide-tables", "Cowork", "Email"])   // Email is where the Cowork folder was moved
        #expect(projects[2].seconds == 3600)
        let folders = s.nameRows(.folders, now: now)
        #expect(folders.map(\.key) == ["Daily briefs"])
        #expect(folders[0].entry.project == "Email" && folders[0].seconds == 3600)
    }

    @Test func lastCoworkLogEntryIsTheNewestEnd() {
        let s = CalendarStore(folder: tempDir(), home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
        #expect(s.lastCoworkLogEntry(in: fixtureURL("cowork-log")) == utc("2026-10-12T15:10:00Z"))
        #expect(s.lastCoworkLogEntry(in: tempDir()) == nil)
    }

    @Test func sessionStoredUnderItsFirstMonthShowsInBothWeeks() throws {
        let s = try store([session("sess-a", tide, [block(local(2026, 9, 30, 23), 120)])])
        let sep = week(s, local(2026, 9, 30))
        let oct = week(s, local(2026, 10, 1), now: local(2026, 11, 1))
        #expect(sep.total == 7200 && oct.total == 7200)   // the two days are in the same Monday week
        #expect(sep == oct)
        let monthOct = s.month(containing: local(2026, 10, 15), weekStart: .monday, now: local(2026, 11, 1))
        #expect(monthOct.weeks.flatMap { $0 }.first { $0.date == local(2026, 10, 1) }?.seconds == 3600)
        let monthSep = s.month(containing: local(2026, 9, 15), weekStart: .monday, now: local(2026, 11, 1))
        #expect(monthSep.weeks.flatMap { $0 }.first { $0.date == local(2026, 9, 30) }?.seconds == 3600)
    }

    // MARK: Names that can't be read fail closed

    private func hiddenBook() -> NameBook {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(project: "Other work")
        book.projects["Other work"] = NameEntry(hideTitles: true)
        return book
    }

    private func storeWithUnreadableNames(_ contents: String) throws -> CalendarStore {
        let start = local(2026, 10, 6, 9)
        let first = try store([session("sess-a", tide, [block(start, 60)], title: "Fix the harbor sonar parser",
                                       commits: [commit("aaa1111", start.addingTimeInterval(600), tide, "Patch the sonar parser")]),
                               session("sess-b", light, [block(start.addingTimeInterval(7200), 30)], title: "Chart export")], names: hiddenBook())
        let namesFile = first.folder.appendingPathComponent("names.json")
        #expect(FileManager.default.fileExists(atPath: namesFile.path))
        try Data(contents.utf8).write(to: namesFile)
        return CalendarStore(folder: first.folder, home: fakeHome(), environment: [:], runner: NoRunner(), calendar: newYork)
    }

    private func expectClosed(_ s: CalendarStore, garbage: Data) throws {
        let w = week(s)
        #expect(w.items.map(\.title) == ["tide-tables", "lighthouse-api"])   // every title is its project's name
        #expect(w.items.allSatisfy { $0.commitSubjects.isEmpty })
        #expect(w.items.allSatisfy { $0.titlesHidden })
        #expect(w.problems.contains { $0.id == "names-unreadable" })
        #expect(s.problems.contains { $0.id == "names-unreadable" })
        let text = ClaudeCodeReport.summary(w, calendar: newYork)
        #expect(!text.contains("sonar") && !text.contains("Chart export"))
        #expect(!s.month(containing: local(2026, 10, 6), weekStart: .monday, now: local(2026, 11, 1)).weeks.flatMap { $0 }.flatMap(\.top).contains { $0.title == "Chart export" })
        #expect(s.nameRows(.sessions, now: local(2026, 10, 21)).isEmpty)
        // The file is kept as it was, and edits are refused.
        #expect(throws: (any Error).self) { _ = try s.apply(NameChange(kind: .projects, key: "tide-tables", name: .some("Tides"))) }
        #expect((try? Data(contentsOf: s.folder.appendingPathComponent("names.json"))) == garbage)
    }

    @Test func aCorruptNamesFileHidesEveryTitle() throws {
        let s = try storeWithUnreadableNames("not json {{{")
        try expectClosed(s, garbage: Data("not json {{{".utf8))
    }

    @Test func aNewerNamesFileHidesEveryTitleToo() throws {
        let text = #"{"version":2,"names":{"projects":{}}}"#
        let s = try storeWithUnreadableNames(text)
        try expectClosed(s, garbage: Data(text.utf8))
    }

    // MARK: Saved report text passes the secret filter

    @Test func savedReportTextNamingASecretProjectIsLeftOut() throws {
        var book = hiddenBook()
        book.projects["tide-tables"] = NameEntry(project: "Other work")
        let report = WeekReport(weekStart: "2026-10-05", lines: ["Shipped the weekly sync.", "Fixed the tide-tables login.", "Next: tidy up."],
                                days: ["2026-10-06": "Fixed the tide-tables login", "2026-10-07": "Wrote the release notes"],
                                author: .imported, written: local(2026, 10, 12))
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 9), 60)], title: "Login loop"),
                           session("sess-b", light, [block(local(2026, 10, 7, 9), 60)], title: "Release notes")], names: book)
        try s.save(report)
        let w = week(s)
        #expect(!w.dayNotes.joined().contains("tide-tables"))
        #expect(w.dayNotes[1] == "Other work.")            // the generated note stands in
        #expect(w.dayNotes[2] == "Wrote the release notes")   // an ordinary one stays
        #expect(w.report?.lines[1] == w.plainReport[1])
        #expect(w.report?.lines[0] == "Shipped the weekly sync.")
        let keptDays = Array(w.report?.days.values ?? [:].values).joined(separator: " ")
        #expect(keptDays == "Wrote the release notes")
        let text = ClaudeCodeReport.summary(w, calendar: newYork)
        #expect(!text.contains("tide-tables"))
        // A first line that names one is replaced for the brief too.
        let named = WeekReport(weekStart: "2026-10-05", lines: ["All about tide-tables."], days: [:], author: .imported, written: local(2026, 10, 12))
        try s.save(named)
        #expect(!week(s).brief.contains("tide-tables"))
    }

    // MARK: A moved project hides titles when either end hides them

    @Test func hidingTitlesOnAMovedProjectIsHonoured() throws {
        var book = NameBook()
        book.projects["tide-tables"] = NameEntry(project: "Other work", hideTitles: true)   // the origin hides, the target doesn't
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 9), 60)], title: "Fix the harbor sonar parser",
                                   commits: [commit("aaa1111", local(2026, 10, 6, 9, 10), tide, "Patch the sonar parser")])], names: book)
        let w = week(s)
        #expect(w.items.first?.title == "Other work")
        #expect(w.items.first?.titlesHidden == true)
        #expect(w.items.first?.commitSubjects == [])
    }

    // MARK: Names and the Gregorian calendar

    @Test func aBuddhistCalendarStillMakesGregorianKeysAndFiles() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = newYork.timeZone
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 6, 9), 60)], title: "Chart")], calendar: buddhist)
        #expect(FileManager.default.fileExists(atPath: s.folder.appendingPathComponent("sessions/2026-10.json").path))
        try s.save(WeekReport(weekStart: "2026-10-05", lines: ["One"], days: ["2026-10-06": "Chart day"], author: .tidemark, written: local(2026, 10, 12)))
        let w = week(s)
        #expect(w.report?.lines == ["One"])
        #expect(w.dayNotes[1] == "Chart day")
        let sum = s.weekSummary(containing: local(2026, 10, 7), weekStart: .monday, now: local(2026, 11, 1))
        #expect(sum.week.start == "2026-10-05" && sum.week.end == "2026-10-11")
        #expect(sum.week.days.first?.date == "2026-10-05")
        #expect(w.items.first?.id == "sess-a|2026-10-06")
        let text = ClaudeCodeReport.summary(w, calendar: buddhist)
        #expect(text.contains("\"start\" : \"2026-10-05\""))
        #expect(s.month(containing: local(2026, 10, 15), weekStart: .monday, now: local(2026, 11, 1)).weeks.count >= 4)
    }

    // MARK: Names & tags rows

    @Test func projectRowsAlsoListTheProjectsOthersAreMovedInto() throws {
        var book = NameBook()
        book.sessions["Legend fixes"] = NameEntry(project: "Side projects")
        book.projects["field-notes"] = NameEntry(project: "Side projects")
        let now = local(2026, 10, 21, 12)
        let s = try store([session("sess-a", tide, [block(local(2026, 10, 20, 9), 60)], title: "Chart export"),
                           session("sess-b", light, [block(local(2026, 10, 20, 11), 60)], title: "Legend fixes"),
                           session("sess-c", notes, [block(local(2026, 10, 20, 13), 30)], title: "Notes")], names: book)
        let rows = s.nameRows(.projects, now: now)
        let side = try #require(rows.first { $0.key == "Side projects" })
        #expect(side.seconds == 5400)
        #expect(Set(rows.map(\.key)) == ["tide-tables", "lighthouse-api", "field-notes", "Side projects"])
        // A folder called Claude is listed like any other, as the sample data does.
        let cowork = try store([session("sess-d", "Cowork", [block(local(2026, 10, 20, 9), 30)], title: "Brief", folders: ["Claude"], origin: .cowork)])
        #expect(cowork.nameRows(.folders, now: now).map(\.key) == ["Claude"])
    }

    @Test func aBareStarIsNotARule() throws {
        var book = NameBook()
        book.sessions["*"] = NameEntry(name: "Everything", tags: ["all"])
        #expect(book.entry(.sessions, "Chart export") == NameEntry())
        #expect(WeekComputer.ruleKey(book.sessions, for: "Chart export") == nil)
        let parsed = LegacyImport.parseNames(#"const NAMES = {"sessions": {"*": {"name": "All"}, "Daily*": {"name": "Daily"}}};"#)
        #expect(parsed?.sessions.keys.sorted() == ["Daily*"])
    }

    @Test func anUntitledSessionIsLabelledByItsFirstFiveWords() throws {
        var first = session("sess-a", tide, [block(local(2026, 10, 6, 9), 60)], first: "Add the legend to the tide charts and more")
        first.title = nil
        let s = try store([first])
        let w = week(s)
        #expect(w.items.first?.title == "Add the legend to the…")
        #expect(!ClaudeCodeReport.summary(w, calendar: newYork).contains("charts and more"))
    }
}

