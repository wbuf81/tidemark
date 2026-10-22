import Foundation
import Testing
@testable import TidemarkCore

/// The week-summary file a week calendar writes, and how the widget and Insights read it.
@Suite struct WeekSummaryTests {
    static let sample = """
    {
     "format": "week-summary/1",
     "generated": "2026-10-06T11:30:00-04:00",
     "week": {
      "start": "2026-10-05", "end": "2026-10-11", "seconds": 37800, "sessions": 9, "commits": 51,
      "days": [{"date": "2026-10-05", "seconds": 14400, "commits": 30}, {"date": "2026-10-06", "seconds": 23400, "commits": 21},
               {"date": "2026-10-07", "seconds": 0, "commits": 0}],
      "projects": [{"name": "tide-tables", "seconds": 21600}, {"name": "lighthouse-api", "seconds": 9000}],
      "previous_seconds": 230885,
      "something_newer": true
     },
     "weeks": [{"start": "2026-09-28", "seconds": 230885}],
     "problems": [{"title": "The calendar hasn’t been rebuilt", "detail": "Last built Sun."}],
     "links": {"week": "http://localhost:8790/week.html", "week_file": "file:///tmp/week.html"}
    }
    """

    private func decode(_ text: String) throws -> WeekSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WeekSummary.self, from: Data(text.utf8))
    }

    @Test func readsTheFile() throws {
        let summary = try decode(Self.sample)
        #expect(summary.week.seconds == 37800)
        #expect(summary.week.days.count == 3)
        #expect(summary.week.projects.first?.name == "tide-tables")
        #expect(summary.week.previousSeconds == 230885)
        #expect(summary.problems.first?.title == "The calendar hasn’t been rebuilt")
        #expect(summary.links?.weekFile == "file:///tmp/week.html")
        #expect(summary.generated == utc("2026-10-06T15:30:00Z"))
    }

    @Test func aBareFileStillReads() throws {
        let summary = try decode(#"{"format": "week-summary/1.2", "week": {"start": "2026-10-05"}}"#)
        #expect(summary.week.end == "2026-10-05")
        #expect(summary.week.days.isEmpty && summary.problems.isEmpty && summary.links == nil)
        #expect(summary.isStale(now: designNow))   // never said when it was written
    }

    @Test func hoursText() {
        #expect(WeekSummary.shortHours(0) == "0m")
        #expect(WeekSummary.shortHours(45 * 60) == "45m")
        #expect(WeekSummary.shortHours(59 * 60 + 59) == "59m")
        #expect(WeekSummary.shortHours(3 * 3600 + 5 * 60) == "3h")
        #expect(WeekSummary.shortHours(4 * 3600) == "4h")
        // Rounded down, never up: 19 h 20 m is "19h", and so is 19 h 59 m.
        #expect(WeekSummary.shortHours(19 * 3600 + 20 * 60) == "19h")
        #expect(WeekSummary.shortHours(19 * 3600 + 59 * 60) == "19h")
        #expect(WeekSummary.shortHours(31 * 3600 + 20 * 60) == "31h")
        #expect(WeekSummary.hours(31 * 3600 + 5 * 60) == "31h 05m")
        #expect(WeekSummary.hours(45 * 60) == "0h 45m")
    }

    @Test func daysAndToday() throws {
        let summary = try decode(Self.sample)
        #expect(summary.dayLevels.map { ($0 * 100).rounded() } == [62, 100, 0])
        #expect(summary.todayIndex(now: designNow, calendar: newYork) == 1)
        #expect(summary.todayIndex(now: local(2026, 10, 20, 9), calendar: newYork) == nil)
        #expect(!summary.isStale(now: designNow))
        #expect(summary.isStale(now: local(2026, 10, 8, 9)))
        #expect(!summary.isPast(now: designNow, calendar: newYork))
        #expect(summary.isPast(now: local(2026, 10, 12, 0, 5), calendar: newYork))
    }

    @Test func theWeekAsASentence() throws {
        let summary = try decode(Self.sample)
        #expect(summary.sentence == "This week: 10h 30m over 9 sessions, 51 commits. Most time: tide-tables, 6h 00m. "
                + "Last week: 64h 08m. The calendar hasn’t been rebuilt.")
    }
}

/// The week band on the widget: only where each org keeps an L slot.
@Suite struct WeekBandTests {
    @Test func needsRoomForLargeOrgs() {
        // Two orgs: 2 × 165 + 96 = 426 pt before the week fits.
        #expect(WidgetSizing.layout(width: 425, orgs: 2, advice: false, week: true).weekWidth == 0)
        let fits = WidgetSizing.layout(width: 426, orgs: 2, advice: false, week: true)
        #expect(fits.weekWidth == WidgetSizing.weekBand)
        #expect(fits.slot == 165 && fits.size == .l)
        #expect(fits.width == 426)
    }

    @Test func noWeekNoBand() {
        #expect(WidgetSizing.layout(width: 560, orgs: 2, advice: false, week: false)
                == WidgetSizing.layout(width: 560, orgs: 2, advice: false))
    }

    @Test func sharesTheBarWithAdvice() {
        let layout = WidgetSizing.layout(width: 560, orgs: 2, advice: true, week: true)
        #expect(layout.band == .wide && layout.weekWidth == WidgetSizing.weekBand)
        #expect(layout.slot == (560 - 70 - 96) / 2.0)
        #expect(WidgetSizing.layout(width: 480, orgs: 2, advice: true, week: true).weekWidth == 0)
    }

    @Test func oneOrgAtTheDefaultWidth() {
        let layout = WidgetSizing.layout(width: 280, orgs: 1, advice: false, week: true)
        #expect(layout.weekWidth == WidgetSizing.weekBand && layout.size == .l)
    }
}
