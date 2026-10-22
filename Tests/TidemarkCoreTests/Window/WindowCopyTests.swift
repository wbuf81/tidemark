import Foundation
import Testing
@testable import TidemarkCore

@Suite struct WindowCopyTests {
    let now = DemoCalendar.now
    var cal: Calendar { .current }

    func date(_ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: mi))!
    }

    func week(_ day: Date) -> WeekModel { DemoCalendar.store().week(containing: day, weekStart: .monday, now: now) }

    @Test func rangeInOneMonth() { #expect(WindowCopy.range(week(now), calendar: cal) == "19 – 25 Oct") }

    @Test func rangeAcrossMonths() { #expect(WindowCopy.range(week(date(9, 30)), calendar: cal) == "28 Sep – 4 Oct") }

    @Test func tilesForTheMockupWeek() {
        let w = week(now)
        #expect(WindowCopy.sessionsDetail(w) == "11 Claude Code · 4 Cowork")
        #expect(WindowCopy.commitsDetail(w) == "in 3 repos")
        #expect(WindowCopy.projectsDetail(w) == "tide-tables took 52%")
        #expect(WindowCopy.projectsDetailParts(w)?.name == "tide-tables")
        #expect(WindowCopy.projectsDetailParts(w)?.rest == " took 52%")
    }

    @Test func singularRepo() {
        var w = week(now)
        w.repos = 1
        #expect(WindowCopy.commitsDetail(w) == "in 1 repo")
        w.repos = 0
        w.commits = 0
        #expect(WindowCopy.commitsDetail(w) == "none")
    }

    @Test func emptyWeekTiles() {
        let w = WeekModel(start: date(10, 19), days: (0...7).map { date(10, 19 + $0) })
        #expect(WindowCopy.sessionsDetail(w) == "none yet")
        #expect(WindowCopy.projectsDetail(w) == "none yet")
    }

    @Test func dayHeadings() {
        let w = week(now)
        #expect(WindowCopy.dayHeading(w, day: 0, now: now, calendar: cal) == "Mon 19")
        #expect(WindowCopy.dayHeading(w, day: 2, now: now, calendar: cal) == "Wed 21")
        #expect(WindowCopy.dayHours(w, day: 0, now: now, calendar: cal) == "7h 10m · 52 commits")
        #expect(WindowCopy.dayHours(w, day: 2, now: now, calendar: cal) == "3h 05m so far · 14 commits")
        #expect(WindowCopy.dayHours(w, day: 3, now: now, calendar: cal) == "")
    }

    @Test func voiceOverSentence() {
        let w = week(now)
        let item = w.items.first { $0.id.hasPrefix("demo-chart-1|") }!
        let text = WindowCopy.voiceOver(item, calendar: cal, twentyFourHour: false)
        #expect(text == "Add chart export, tide-tables, Monday 9:30 AM to 12:30 PM, 3 hours, 20 commits")
        let lone = WeekItem(id: "x|2026-10-19", sessionID: "x", day: 0, title: "Quick fix", project: "field-notes", colorIndex: 2,
                            spans: [DateInterval(start: date(10, 19, 9, 0), end: date(10, 19, 9, 45))], seconds: 2700, commits: 1)
        #expect(WindowCopy.voiceOver(lone, calendar: cal, twentyFourHour: false) == "Quick fix, field-notes, Monday 9 AM to 9:45 AM, 45 minutes, 1 commit")
        var none = lone
        none.commits = 0
        none.noCommit = true
        none.seconds = 5400
        #expect(WindowCopy.voiceOver(none, calendar: cal, twentyFourHour: false).hasSuffix("1 hour 30 minutes, no commits"))
    }

    @Test func voiceOverListsWhatSharesItsLane() {
        let w = week(now)
        let item = w.items[0]
        let text = WindowCopy.voiceOver(item, sharing: ["Offline mode", "Release notes"], calendar: cal, twentyFourHour: false)
        #expect(text.hasSuffix("also running: Offline mode, Release notes"))
    }

    @Test func reportWords() {
        #expect(WindowCopy.reportFailure(.notInstalled) == "Claude Code isn’t installed. Install it, sign in, then try again.")
        #expect(WindowCopy.reportFailure(.timedOut) == "Claude Code didn’t answer within 2 minutes.")
        #expect(WindowCopy.reportFailure(.failed("exit 1")) == "Claude Code couldn’t write it: exit 1")
        #expect(WindowCopy.reportFailure(.failed("Claude Code couldn’t start.")) == "Claude Code couldn’t start.")
        let report = WeekReport(weekStart: "2026-10-12", lines: [], author: .claudeCode, written: date(10, 19, 9, 2))
        #expect(WindowCopy.writtenBy(report, calendar: cal, twentyFourHour: false) == "Written by Claude Code, Mon 19 Oct 9:02 AM")
    }
}
