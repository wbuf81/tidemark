import Foundation
import Testing
@testable import TidemarkCore

@Suite struct PanesCopyTests {
    private let cal = newYork

    private func day(_ d: Int, month: Int = 10, seconds: TimeInterval = 0, top: [MonthItem] = []) -> MonthDay {
        MonthDay(date: local(2026, month, d), inMonth: month == 10, isToday: false, seconds: seconds, top: top)
    }

    // MARK: Month

    @Test func monthTitleAndNeighbours() {
        let october = local(2026, 10, 1)
        #expect(PanesCopy.monthTitle(october, calendar: cal) == "October 2026")
        #expect(PanesCopy.previousMonth(october, calendar: cal) == "‹ Sep")
        #expect(PanesCopy.nextMonth(october, calendar: cal) == "Nov ›")
        #expect(PanesCopy.previousMonth(local(2026, 1, 1), calendar: cal) == "‹ Dec")
    }

    @Test func weekdayHeadersFollowTheFirstWeek() {
        let monday = (0..<7).map { day(28 + $0 > 30 ? 28 + $0 - 30 : 28 + $0, month: 9 + ($0 > 2 ? 1 : 0)) }
        #expect(PanesCopy.weekdayHeaders(monday, calendar: cal) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        let sunday = (0..<7).map { MonthDay(date: local(2026, 10, 25 + $0), inMonth: true, isToday: false, seconds: 0, top: []) }
        #expect(PanesCopy.weekdayHeaders(sunday, calendar: cal).first == "Sun")
    }

    @Test func dayVoiceOverNamesTheDayItsTimeAndItems() {
        let d = MonthDay(date: local(2026, 10, 21), inMonth: true, isToday: true, seconds: 5520,
                         top: [MonthItem(title: "Release notes", colorIndex: 1), MonthItem(title: "Daily brief", colorIndex: 4)])
        #expect(PanesCopy.dayVoiceOver(d, calendar: cal) == "Wednesday 21 October, today, 1 hour 32 minutes: Release notes, Daily brief. Opens that week.")
        #expect(PanesCopy.dayVoiceOver(day(3), calendar: cal) == "Saturday 3 October, nothing recorded. Opens that week.")
    }

    // MARK: Trends

    @Test func captionsAndHours() {
        #expect(PanesCopy.trendsCaption(.project)
            == "One row per project, every row on one scale; a paler column is this week so far. Click a row for its chart and weeks.")
        #expect(PanesCopy.trendsCaption(.tag)
            == "One row per tag, every row on one scale; a paler column is this week so far. Click a row for its chart and weeks.")
        #expect(PanesCopy.hours(84 * 3600) == "84h")
        #expect(PanesCopy.hours(84.4 * 3600) == "84h")
        #expect(PanesCopy.hours(30 * 60) == "30m")
        #expect(PanesCopy.hours(0) == "0h")
    }

    @Test func weekRanges() {
        #expect(PanesCopy.weekRange(start: local(2026, 10, 19), calendar: cal) == "19 – 25 Oct")
        #expect(PanesCopy.weekRange(start: local(2026, 9, 28), calendar: cal) == "28 Sep – 4 Oct")
    }

    @Test func rowVoiceOver() {
        let row = TrendRow(name: "tide-tables", seconds: [3600, 7200], total: 10800)
        #expect(PanesCopy.trendRowVoiceOver(row, weeks: 2, grouping: .project)
            == "tide-tables, 3 hours over 2 weeks. Opens its chart and weeks.")
        #expect(PanesCopy.trendRowVoiceOver(TrendRow(name: "bug", seconds: [60], total: 3600), weeks: 1, grouping: .tag)
            == "Tag bug, 1 hour over 1 week. Opens its chart and weeks.")
    }

    @Test func detailLines() {
        let row = TrendRow(name: "tide-tables", seconds: [], total: 84 * 3600)
        #expect(PanesCopy.detailSummary(row, weeks: 13) == "84h over 13 weeks")
        #expect(PanesCopy.detailWeekLabel(start: local(2026, 10, 19), isPartial: true, calendar: cal) == "19 – 25 Oct, so far")
        #expect(PanesCopy.detailWeekLabel(start: local(2026, 10, 12), isPartial: false, calendar: cal) == "12 – 18 Oct")
        #expect(PanesCopy.detailWeekVoiceOver(start: local(2026, 10, 12), seconds: 36000, isPartial: false, calendar: cal)
            == "12 – 18 Oct, 10 hours. Opens that week.")
    }

    // MARK: Names

    private func row(_ kind: NameKind, _ key: String, _ entry: NameEntry = NameEntry(), rule: String? = nil, project: String = "x") -> NameRow {
        NameRow(id: "\(kind.rawValue)|\(key)", kind: kind, key: key, entry: entry, ruleKey: rule, seconds: 3600, currentProject: project)
    }

    @Test func ruleRowsSayWhatTheyMatch() {
        let r = row(.sessions, "Email Brief Daily 19 Oct", NameEntry(name: "Daily email brief"), rule: "Email Brief Daily*")
        #expect(PanesCopy.subline(r, book: NameBook()) == "titles starting with \"Email Brief Daily\"")
    }

    @Test func renamedSessionsSayWhatTheyWere() {
        let r = row(.sessions, "Login loop on SSO", NameEntry(name: "Fix sign-in redirect"))
        #expect(PanesCopy.subline(r, book: NameBook()) == "was \"Login loop on SSO\"")
        #expect(PanesCopy.subline(row(.sessions, "Add chart export", NameEntry(tags: ["feature"])), book: NameBook()) == nil)
        // A name equal to the title isn't a rename.
        #expect(PanesCopy.subline(row(.sessions, "Same", NameEntry(name: "Same")), book: NameBook()) == nil)
    }

    @Test func hiddenProjectsCountThePersonalProjectsInIt() {
        var book = NameBook()
        book.projects["Side projects"] = NameEntry(hideTitles: true)
        for f in ["garden-planner", "recipe-box", "bike-log"] { book.projects[f] = NameEntry(project: "Side projects") }
        book.projects["other"] = NameEntry(project: "Elsewhere")
        let r = row(.projects, "Side projects", book.projects["Side projects"]!)
        #expect(PanesCopy.subline(r, book: book) == "3 personal projects, titles hidden")
        book.projects.removeValue(forKey: "recipe-box")
        book.projects.removeValue(forKey: "bike-log")
        #expect(PanesCopy.subline(r, book: book) == "1 personal project, titles hidden")
        book.projects.removeValue(forKey: "garden-planner")
        #expect(PanesCopy.subline(r, book: book) == "titles hidden")
        #expect(PanesCopy.subline(row(.projects, "tide-tables"), book: book) == nil)
    }

    @Test func foldersSayWhatTheyWere() {
        let r = row(.folders, "garden-planner", NameEntry(name: "Garden"))
        #expect(PanesCopy.subline(r, book: NameBook()) == "was \"garden-planner\"")
    }

    @Test func voiceOverLabelsCarryTheRowsName() {
        let r = row(.sessions, "Login loop on SSO", NameEntry(name: "Fix sign-in redirect"))
        #expect(PanesCopy.displayTitle(r) == "Fix sign-in redirect")
        #expect(PanesCopy.label(.name, for: r) == "Name for Fix sign-in redirect")
        #expect(PanesCopy.label(.tags, for: r) == "Tags for Fix sign-in redirect")
        #expect(PanesCopy.label(.project, for: r) == "Project for Fix sign-in redirect")
        #expect(PanesCopy.label(.hideTitles, for: r) == "Hide titles for Fix sign-in redirect")
        #expect(PanesCopy.displayTitle(row(.sessions, "Add chart export")) == "Add chart export")
    }

    @Test func saveErrorsGiveTheReason() {
        #expect(PanesCopy.saveError(NameBookError.badKey) == "Couldn’t save: That name can’t be used.")
        struct Plain: Error {}
        #expect(PanesCopy.saveError(NameBookError.unreadable("bad json")).hasPrefix("Couldn’t save: names.json"))
        #expect(PanesCopy.saveError(Plain()).hasPrefix("Couldn’t save: "))
    }

    @Test func tagsAndRules() {
        #expect(PanesCopy.parseTags(" bug, feature ,,bug") == ["bug", "feature"])
        #expect(PanesCopy.parseTags("  ") == [])
        #expect(PanesCopy.ruleKey(for: " Email Brief Daily ") == "Email Brief Daily*")
        #expect(PanesCopy.ruleKey(for: "Email*") == "Email*")
        #expect(PanesCopy.ruleKey(for: "  ") == nil)
        #expect(PanesCopy.ruleKey(for: "*") == nil)
    }
}
