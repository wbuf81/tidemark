import Foundation
import Testing
@testable import TidemarkCore

@Suite struct WeekLayoutTests {
    var cal: Calendar { .current }

    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 19 + day, hour: h, minute: m))!
    }

    func item(_ id: String, day: Int = 0, _ from: (Int, Int), _ to: (Int, Int)) -> WeekItem {
        let span = DateInterval(start: at(day, from.0, from.1), end: at(day, to.0, to.1))
        return WeekItem(id: id, sessionID: id, day: day, title: id, project: "p", colorIndex: 0, spans: [span], seconds: span.duration)
    }

    @Test func separateItemsShareOneLane() {
        let out = WeekLayout.lanes([item("a", (9, 0), (10, 0)), item("b", (10, 0), (11, 0)), item("c", (12, 0), (13, 0))])
        for id in ["a", "b", "c"] { #expect(out[id]?.lane == 0); #expect(out[id]?.lanes == 1) }
    }

    @Test func twoOverlappingItemsGetTwoLanes() {
        let out = WeekLayout.lanes([item("a", (9, 0), (11, 0)), item("b", (10, 0), (12, 0))])
        #expect(out["a"]?.lane == 0)
        #expect(out["b"]?.lane == 1)
        #expect(out["a"]?.lanes == 2)
        #expect(out["b"]?.lanes == 2)
    }

    @Test func threeChainedOverlapsGetThreeLanes() {
        let out = WeekLayout.lanes([item("a", (9, 0), (11, 0)), item("b", (10, 0), (12, 0)), item("c", (10, 30), (11, 30))])
        #expect(Set(out.values.map(\.lane)) == [0, 1, 2])
        #expect(out.values.allSatisfy { $0.lanes == 3 })
    }

    @Test func overlapsOnDifferentDaysDontMix() {
        let out = WeekLayout.lanes([item("a", day: 0, (9, 0), (11, 0)), item("b", day: 1, (10, 0), (12, 0))])
        #expect(out["a"]?.lanes == 1)
        #expect(out["b"]?.lanes == 1)
    }

    @Test func laterItemReusesAFreedLane() {
        let out = WeekLayout.lanes([item("a", (9, 0), (12, 0)), item("b", (9, 30), (10, 0)), item("c", (10, 30), (11, 0))])
        #expect(out["c"]?.lane == 1)
        #expect(out["c"]?.lanes == 2)
    }

    @Test func laneTitlesNeverExceedTheirLane() {
        let items = (0..<6).map { item("s\($0)", (9, $0), (12, 0)) }
        let out = WeekLayout.lanes(items)
        #expect(out.values.allSatisfy { $0.lanes <= WeekLayout.maxLanes && $0.lane < $0.lanes })
        #expect(out["s5"]?.lane == WeekLayout.maxLanes - 1)
        #expect(out["s4"]?.lane == WeekLayout.maxLanes - 1)
        #expect(WeekLayout.hiddenBehind(items).count == 3)   // the last lane's three items each name the others
    }

    // MARK: Clock-time placement (daylight-saving days)

    func newYork() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func ny(_ month: Int, _ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        newYork().date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
    }

    @Test func offsetCountsClockHoursOnAnOrdinaryDay() {
        let cal = newYork()
        let day = ny(10, 21, 0)
        #expect(WeekLayout.hourOffset(ny(10, 21, 9, 30), onDay: day, firstHour: 9, calendar: cal) == 0.5)
        #expect(WeekLayout.hourOffset(ny(10, 21, 17), onDay: day, firstHour: 9, calendar: cal) == 8)
    }

    @Test func offsetOnAFallBackDayIsStillClockTime() {
        // 1 Nov 2026: 25 hours long. 9:00 is 9 clock hours after midnight, though 10 elapsed.
        let cal = newYork()
        let day = ny(11, 1, 0)
        #expect(WeekLayout.hourOffset(ny(11, 1, 9), onDay: day, firstHour: 9, calendar: cal) == 0)
        #expect(WeekLayout.hourOffset(ny(11, 1, 10, 15), onDay: day, firstHour: 9, calendar: cal) == 1.25)
        #expect(WeekLayout.hourOffset(ny(11, 1, 0, 30), onDay: day, firstHour: 0, calendar: cal) == 0.5)
    }

    @Test func offsetOnASpringForwardDayIsStillClockTime() {
        // 8 Mar 2026: 23 hours long. 9:00 is 9 clock hours after midnight, though 8 elapsed.
        let cal = newYork()
        let day = ny(3, 8, 0)
        #expect(WeekLayout.hourOffset(ny(3, 8, 9), onDay: day, firstHour: 9, calendar: cal) == 0)
        #expect(WeekLayout.hourOffset(ny(3, 8, 12), onDay: day, firstHour: 9, calendar: cal) == 3)
    }

    @Test func offsetAtTheNextMidnightIsTheDaysEnd() {
        let cal = newYork()
        let day = ny(11, 1, 0)
        #expect(WeekLayout.hourOffset(ny(11, 2, 0), onDay: day, firstHour: 9, calendar: cal) == 15)
        #expect(WeekLayout.hourOffset(ny(11, 2, 1), onDay: day, firstHour: 9, calendar: cal) == 15)
    }
}
