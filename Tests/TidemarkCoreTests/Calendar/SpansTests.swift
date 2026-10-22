import Foundation
import Testing
@testable import TidemarkCore

@Suite struct SpansTests {
    private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> DateInterval {
        DateInterval(start: local(2026, 10, 12, h1, m1), end: local(2026, 10, 12, h2, m2))
    }

    @Test func unionCountsOverlapsOnce() {
        let spans = [span(9, 0, 11, 0), span(10, 0, 12, 0), span(12, 0, 12, 30)]
        #expect(Spans.union(spans) == 3.5 * 3600)
    }

    @Test func touchingSpansMerge() {
        let merged = Spans.merged([span(10, 0, 11, 0), span(9, 0, 10, 0)])
        #expect(merged.count == 1)
        #expect(merged[0] == span(9, 0, 11, 0))
    }

    @Test func clipKeepsOnlyTheOverlap() {
        let clipped = Spans.clip([span(8, 0, 10, 0), span(11, 0, 12, 0), span(13, 0, 14, 0)], to: span(9, 0, 11, 30))
        #expect(clipped == [span(9, 0, 10, 0), span(11, 0, 11, 30)])
    }

    @Test func clipKeepsAZeroLengthSpanInside() {
        let point = DateInterval(start: local(2026, 10, 12, 10), duration: 0)
        #expect(Spans.clip([point], to: span(9, 0, 11, 0)) == [point])
    }

    @Test func mondayAndSundayWeeks() {
        let wed = local(2026, 10, 21, 11, 32)
        let monday = WeekDays.midnights(containing: wed, weekStart: .monday, calendar: newYork)
        let sunday = WeekDays.midnights(containing: wed, weekStart: .sunday, calendar: newYork)
        #expect(monday.count == 8 && sunday.count == 8)
        #expect(monday[0] == local(2026, 10, 19))
        #expect(monday[7] == local(2026, 10, 26))
        #expect(sunday[0] == local(2026, 10, 18))
    }

    @Test func sundayStartsItsOwnWeek() {
        let sun = local(2026, 10, 25, 12)
        #expect(WeekDays.midnights(containing: sun, weekStart: .monday, calendar: newYork)[0] == local(2026, 10, 19))
        #expect(WeekDays.midnights(containing: sun, weekStart: .sunday, calendar: newYork)[0] == local(2026, 10, 25))
    }

    @Test func regionFollowsTheCalendarsFirstWeekday() {
        var cal = newYork
        cal.firstWeekday = 2
        let wed = local(2026, 10, 21, 11, 32)
        #expect(WeekDays.midnights(containing: wed, weekStart: .region, calendar: cal)[0] == local(2026, 10, 19))
        cal.firstWeekday = 1
        #expect(WeekDays.midnights(containing: wed, weekStart: .region, calendar: cal)[0] == local(2026, 10, 18))
    }

    @Test func dstWeekHasSevenDays() {
        func hours(_ zone: String, _ y: Int, _ m: Int, _ d: Int) -> [Double] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: zone)!
            let day = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
            let mids = WeekDays.midnights(containing: day, weekStart: .monday, calendar: cal)
            #expect(mids.count == 8)
            return zip(mids, mids.dropFirst()).map { $1.timeIntervalSince($0) / 3600 }
        }
        let london = hours("Europe/London", 2026, 10, 21)
        #expect(london.count == 7 && london[6] == 25 && london[0] == 24)
        #expect(london.reduce(0, +) == 169)
        let ny = hours("America/New_York", 2026, 10, 28)
        #expect(ny.count == 7 && ny[6] == 25)
        let spring = hours("America/New_York", 2026, 3, 4)
        #expect(spring.contains(23))
    }

    @Test func hoursText() {
        #expect(HoursText.format(0) == "0h 00m")
        #expect(HoursText.format(5430) == "1h 30m")
        #expect(HoursText.format(5490) == "1h 32m")
        #expect(HoursText.format(32700) == "9h 05m")
    }
}
