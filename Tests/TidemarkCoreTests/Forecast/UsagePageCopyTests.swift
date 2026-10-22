import Testing
import Foundation
@testable import TidemarkCore

@Suite struct UsagePageCopySuite {
    static let now = local(2026, 10, 7, 11, 32)
    static let reset = local(2026, 10, 11, 9)

    /// Harbor Labs: 81% used, empties Thursday evening, back Sunday 9 AM.
    static var harbor: (reading: Reading, history: [Reading], forecast: WeekForecast?) {
        let r = reading(org: "harbor", week: 81, weekResetsAt: reset, at: now)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: reset, at: local(2026, 10, 4, 10))]
        return (r, history, Pace.forecast(r, history: history, now: now))
    }

    @Test func lastsLineSaysWhenItResetsAndWhatIsSpare() {
        let r = reading(week: 40, weekResetsAt: Self.now.addingTimeInterval(84 * 3600), at: Self.now)
        let f = Pace.forecast(r, history: [], now: Self.now)
        #expect(UsageCopy.lastsLine(reading: r, forecast: f, now: Self.now, formatting: fmt)
                == "Lasts to reset Sat 11:32 PM, about 20% to spare")
    }

    @Test func lastsLineWhenUsingItAllHasNoSpare() {
        let r = reading(week: 50, weekResetsAt: Self.now.addingTimeInterval(84 * 3600), at: Self.now)
        let f = Pace.forecast(r, history: [], now: Self.now)
        #expect(UsageCopy.lastsLine(reading: r, forecast: f, now: Self.now, formatting: fmt)
                == "Lasts to reset Sat 11:32 PM, on pace to use it all")
    }

    @Test func lastsLineIsNilWhenItRunsOutOrHasNoWeek() {
        let h = Self.harbor
        #expect(UsageCopy.lastsLine(reading: h.reading, forecast: h.forecast, now: Self.now, formatting: fmt) == nil)
        let none = reading(week: 0, weekResetsAt: nil)
        #expect(UsageCopy.lastsLine(reading: none, forecast: nil, now: Self.now, formatting: fmt) == nil)
    }

    @Test func paceLineNamesTheLevelAndTheMultiple() throws {
        let light = try #require(PaceReading.make(reading: reading(week: 20, weekResetsAt: Self.now.addingTimeInterval(84 * 3600), at: Self.now), now: Self.now))
        #expect(UsageCopy.paceLine(light) == "Light pace: 0.4× even")
        let fast = try #require(PaceReading.make(reading: Self.harbor.reading, now: Self.now))
        #expect(UsageCopy.paceLine(fast) == "Fast pace: 1.8× even")
    }

    @Test func paceLeadIsUsedInShareOfTheWeek() {
        #expect(UsageCopy.paceLead(reading: Self.harbor.reading, now: Self.now) == "Used 81% in 44% of the week.")
        #expect(UsageCopy.paceLead(reading: reading(week: 0, weekResetsAt: nil), now: Self.now) == nil)
    }

    @Test func tipForAWeekThatRunsOutNamesTheEmptyTimeAndTheLock() throws {
        let h = Self.harbor
        let chart = try #require(LeftChart.make(reading: h.reading, history: h.history, now: Self.now, calendar: newYork))
        let tip = try #require(UsageCopy.chartTip(chart, now: Self.now, formatting: fmt))
        #expect(tip.title == "Empty Thu 9:36 PM")
        #expect(tip.detail == "Locked 59 h until Sun 9 AM")
    }

    @Test func tipForAWeekThatIsOutSaysWhenItRanOut() throws {
        let r = reading(org: "harbor", week: 100, weekResetsAt: Self.reset, at: Self.now)
        let history = [reading(org: "harbor", week: 70, weekResetsAt: Self.reset, at: local(2026, 10, 6, 12)), r]
        let chart = try #require(LeftChart.make(reading: r, history: history, now: Self.now, calendar: newYork))
        let tip = try #require(UsageCopy.chartTip(chart, now: Self.now, formatting: fmt))
        #expect(tip.title.hasPrefix("Ran out "))
        #expect(tip.detail.hasSuffix(" until Sun 9 AM"))
    }

    @Test func noTipForAWeekThatLastsOrOneWithoutALock() throws {
        let r = reading(week: 40, weekResetsAt: Self.now.addingTimeInterval(84 * 3600), at: Self.now)
        let chart = try #require(LeftChart.make(reading: r, history: [], now: Self.now, calendar: newYork))
        #expect(UsageCopy.chartTip(chart, now: Self.now, formatting: fmt) == nil)
    }

    @Test func busiestRowsGiveTheStartHourTheRangeAndOneDecimal() {
        let hours = [HourUse(start: local(2026, 10, 6, 16), used: 3.84), HourUse(start: local(2026, 10, 7, 9), used: 3.3)]
        let rows = UsageCopy.busiestRows(hours, formatting: fmt, calendar: newYork)
        #expect(rows == [UsageCopy.BusiestRow(hour: "16", range: "Tue 4–5 PM", used: "3.8%"),
                         UsageCopy.BusiestRow(hour: "09", range: "Wed 9–10 AM", used: "3.3%")])
    }
}
