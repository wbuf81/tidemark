import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ContractsTests {
    let now = DemoCalendar.now
    var cal: Calendar { .current }

    func date(_ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: mi))!
    }

    func week(_ day: Date) -> WeekModel {
        DemoCalendar.store().week(containing: day, weekStart: .monday, now: now)
    }

    @Test func calendarSessionRoundTrips() throws {
        let start = date(10, 19, 9, 30)
        let session = CalendarSession(
            id: "demo-1", origin: .claudeCode, title: "Add chart export", firstMessage: nil, command: nil, root: "tide-tables",
            folders: ["Claude"], isGit: true, scheduled: false, logged: false,
            blocks: [Block(start: start, end: start.addingTimeInterval(3600))],
            commits: [Commit(sha: "abc1234", time: start.addingTimeInterval(600), repo: "tide-tables", subject: "Add PNG export", files: ["a.swift"])],
            lastActivity: start.addingTimeInterval(3600))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(session)
        #expect(String(decoding: data, as: UTF8.self).contains("T"))
        #expect(try decoder.decode(CalendarSession.self, from: data) == session)
    }

    @Test func demoCalendarMatchesTheMockups() {
        let store = DemoCalendar.store()
        let this = week(date(10, 21, 11, 32))
        #expect(this.start == date(10, 19))
        #expect(this.days.count == 8)
        #expect(this.total == 69600)
        #expect(HoursText.format(this.total) == "19h 20m")
        #expect(this.perDay == [25800, 32700, 11100, 0, 0, 0, 0])
        #expect(this.sessions == 15)
        #expect(this.claudeCodeSessions == 11)
        #expect(this.coworkSessions == 4)
        #expect(this.commitsPerDay == [52, 61, 14, 0, 0, 0, 0])
        #expect(this.commits == 127)
        #expect(this.repos == 3)
        #expect(this.projects.map(\.name) == ["tide-tables", "lighthouse-api", "field-notes", "Daily briefs"])
        #expect(this.projects.map(\.seconds) == [36180, 16680, 9720, 7020])
        #expect(this.projects.map(\.colorIndex) == [0, 1, 2, 3])
        #expect(this.running == ["tide-tables"])
        #expect(this.brief == "Shipped chart export and offline mode for tide-tables, fixed sign-in redirects in lighthouse-api, and started the 2.3 release notes.")
        #expect(this.dayNotes == ["Chart export for tide-tables, with PNG and CSV.", "Offline mode; fixed lighthouse-api sign-in redirects.",
                                  "Release notes for tide-tables 2.3.", "", "", "", ""])
        #expect(this.plainReport == ["19h 20m of work across 15 sessions (11 Claude Code, 4 Cowork) and 127 commits in 3 repos.",
                                     "Most time on tide-tables (52%), then lighthouse-api (24%) and field-notes (14%).",
                                     "Busiest day Tuesday 20 Oct (9h 05m)."])
        #expect(this.report == nil)
        #expect(this.items.first { $0.sessionID == "demo-signin-1" }?.title == "Fix sign-in redirect")
        #expect(this.items.contains { $0.title == "Daily email brief" && $0.scheduled && $0.origin == .cowork })
        #expect(this.items.map { [$0.day] } == this.items.sorted { ($0.day, $0.spans[0].start) < ($1.day, $1.spans[0].start) }.map { [$0.day] })

        let last = week(date(10, 15, 12))
        #expect(last.start == date(10, 12))
        #expect(last.total == 112800)
        #expect(last.perDay == [25800, 32700, 27000, 18000, 9300, 0, 0])
        #expect(last.sessions == 24)
        #expect(last.claudeCodeSessions == 17)
        #expect(last.coworkSessions == 7)
        #expect(last.commitsPerDay == [40, 52, 48, 30, 16, 0, 0])
        #expect(last.commits == 186)
        #expect(last.repos == 4)
        #expect(last.projects.map(\.name) == ["tide-tables", "lighthouse-api", "field-notes", "Daily briefs", "harbor-site"])
        #expect(last.projects.map(\.seconds) == [42900, 24840, 18060, 14640, 12360])
        #expect(last.running.isEmpty)
        let lines = ["Shipped tide-tables 2.3 with chart export and offline mode, the bulk of the week at about 12 hours.",
                     "Fixed the sign-in redirect loop in lighthouse-api and drafted the field-notes release.",
                     "Started harbor-site’s navigation; daily email briefs ran every weekday."]
        #expect(last.brief == lines[0])
        #expect(last.report?.lines == lines)
        #expect(last.report?.author == .claudeCode)
        #expect(last.report?.written == date(10, 19, 9, 2))
        #expect(last.report?.days["2026-10-13"] == "Released tide-tables 2.3.")
        #expect(last.dayNotes == ["Offline cache for tide-tables; the SSO loop in lighthouse-api.", "Released tide-tables 2.3.",
                                  "field-notes drafts; lighthouse-api token refresh.", "harbor-site navigation.",
                                  "Chart axes for tide-tables.", "", ""])
        #expect(last.plainReport == ["31h 20m of work across 24 sessions (17 Claude Code, 7 Cowork) and 186 commits in 4 repos.",
                                     "Most time on tide-tables (38%), then lighthouse-api (22%) and field-notes (16%).",
                                     "Busiest day Tuesday 13 Oct (9h 05m); Daily briefs ran all five weekdays."])

        // Names, and what the store ignores.
        #expect(store.nameRows(.sessions, now: now).first?.ruleKey == "Email Brief Daily*")
        #expect(store.nameRows(.projects, now: now).last?.entry.hideTitles == true)
        #expect(store.nameRows(.folders, now: now).map(\.key) == ["tide-tables", "Claude"])
        #expect(store.findLegacy(in: URL(fileURLWithPath: "/tmp/none"))?.weeks == 39)
        #expect(store.lastCoworkLogEntry(in: URL(fileURLWithPath: "/tmp/none")) == date(10, 20, 18, 47))
        #expect(store.problems.isEmpty)
    }

    @Test func demoMonthOfOctober() {
        let month = DemoCalendar.store().month(containing: now, weekStart: .monday, now: now)
        #expect(month.weeks.allSatisfy { $0.count == 7 })
        #expect(month.weeks[0][0].date == date(9, 28))
        #expect(!month.weeks[0][0].inMonth)
        #expect(month.weeks[0][3].date == date(10, 1))
        #expect(month.weeks[0][3].top.first?.title == "Map tiles")
        let today = month.weeks.flatMap { $0 }.filter(\.isToday)
        #expect(today.count == 1)
        #expect(today.first?.date == date(10, 21))
        #expect(today.first?.seconds == 11100)
    }

    @Test func demoTrendsQuarter() {
        let store = DemoCalendar.store()
        let byProject = store.trends(endingWith: now, count: 13, grouping: .project, weekStart: .monday, now: now)
        #expect(byProject.weeks.count == 13)
        #expect(byProject.weeks.first == date(7, 27))
        #expect(byProject.weeks.last == date(10, 19))
        #expect(byProject.lastIsPartial)
        #expect(byProject.rows.first?.name == "tide-tables")
        #expect(byProject.rows.allSatisfy { $0.seconds.count == 13 })
        let byTag = store.trends(endingWith: now, count: 13, grouping: .tag, weekStart: .monday, now: now)
        #expect(Set(byTag.rows.map(\.name)) == ["feature", "bug", "routine", "docs"])
    }

    @Test func demoWeekSummary() {
        let summary = DemoCalendar.store().weekSummary(containing: now, weekStart: .monday, now: now)
        #expect(summary.format == "week-summary/1")
        #expect(summary.generated == now)
        #expect(summary.links == nil)
        #expect(summary.week.start == "2026-10-19")
        #expect(summary.week.seconds == 69600)
        #expect(summary.week.days.count == 7)
        #expect(summary.week.projects.count <= 6)
        #expect(summary.week.previousSeconds == 112800)
    }

    @Test func switchableCalendarForwards() {
        let switchable = SwitchableCalendar(EmptyCalendarStore())
        #expect(switchable.week(containing: now, weekStart: .monday, now: now).total == 0)
        switchable.target = DemoCalendar.store()
        #expect(switchable.week(containing: now, weekStart: .monday, now: now).total == 69600)
    }

    @Test func emptyStoreIsEmpty() throws {
        let store = EmptyCalendarStore()
        let w = store.week(containing: now, weekStart: .monday, now: now)
        #expect(w.total == 0 && w.items.isEmpty && w.days.count == 8)
        #expect(store.nameRows(.sessions, now: now).isEmpty)
        #expect(store.names == NameBook())
        #expect(store.findLegacy(in: URL(fileURLWithPath: "/tmp/none")) == nil)
        #expect(store.problems.isEmpty)
        try store.deleteAll()
    }
}
