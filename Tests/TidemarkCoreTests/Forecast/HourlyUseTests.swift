import Testing
import Foundation
@testable import TidemarkCore

@Suite struct HourlyUseSuite {
    static let reset = local(2026, 10, 11, 9)
    static let start = local(2026, 10, 4, 9)
    static let now = local(2026, 10, 7, 12)

    static func r(_ week: Double, _ time: Date, reset: Date = reset) -> Reading {
        reading(org: "harbor", week: week, weekResetsAt: reset, at: time)
    }

    @Test func spreadsAGrowthEvenlyOverTheTimeBetweenReadings() {
        // 6% over 1:30 PM to 3:30 PM: 1.5% in 1 PM, 3% in 2 PM, 1.5% in 3 PM.
        let history = [Self.r(10, local(2026, 10, 7, 13, 30)), Self.r(16, local(2026, 10, 7, 15, 30))]
        let now = local(2026, 10, 7, 16)
        let hours = HourlyUse.hours(reading: Self.r(16, local(2026, 10, 7, 15, 30)), history: history, now: now, calendar: newYork)
        let pm1 = hours.first { $0.start == local(2026, 10, 7, 13) }
        let pm2 = hours.first { $0.start == local(2026, 10, 7, 14) }
        let pm3 = hours.first { $0.start == local(2026, 10, 7, 15) }
        #expect(near(pm1?.used ?? 0, 1.5 + 10 / 76.5 * 0.5, 0.001))   // plus the tail of the earlier stretch
        #expect(near(pm2?.used ?? 0, 3, 0.001))
        #expect(near(pm3?.used ?? 0, 1.5, 0.001))
        // Before the first reading it spreads from 0 at the window's start: 10% over 76.5 h.
        let first = hours.first
        #expect(first?.start == Self.start)
        #expect(near(first?.used ?? 0, 10 / 76.5, 0.001))
        #expect(hours == hours.sorted { $0.start < $1.start })
    }

    @Test func totalIsWhatWasUsedAndQuietHoursAreLeftOut() {
        let history = [Self.r(10, local(2026, 10, 7, 13, 30)), Self.r(16, local(2026, 10, 7, 15, 30)),
                       Self.r(16, local(2026, 10, 7, 20))]
        let current = Self.r(18, local(2026, 10, 7, 21))
        let now = local(2026, 10, 7, 21)
        let hours = HourlyUse.hours(reading: current, history: history, now: now, calendar: newYork)
        #expect(near(hours.reduce(0) { $0 + $1.used }, 18, 0.001))
        #expect(hours.allSatisfy { $0.used > 0 })
        #expect(!hours.contains { $0.start == local(2026, 10, 7, 17) })
    }

    @Test func ignoresOtherWindowsAndStopsAtNow() {
        let old = Self.r(97, local(2026, 10, 3, 12), reset: Self.start)
        let history = [old, Self.r(10, local(2026, 10, 7, 9)), Self.r(30, local(2026, 10, 7, 13))]
        // `now` is 11:00, halfway through the 9→13 stretch: only 5 of the 20 used by then.
        let now = local(2026, 10, 7, 10)
        let hours = HourlyUse.hours(reading: Self.r(10, local(2026, 10, 7, 9)), history: history, now: now, calendar: newYork)
        #expect(near(hours.reduce(0) { $0 + $1.used }, 10, 0.001))
        #expect(hours.last.map { $0.start <= now } == true)
    }

    @Test func nothingWithoutAnOpenWeek() {
        let r = reading(week: 0, weekResetsAt: nil)
        #expect(HourlyUse.hours(reading: r, history: [], now: designNow, calendar: newYork).isEmpty)
    }

    @Test func busiestAreMostFirstTiesToTheEarlierHourAndAtLeastATenth() {
        let h = (0..<6).map { HourUse(start: Self.start.addingTimeInterval(Double($0) * 3600), used: [1, 3.8, 3.8, 0.05, 2, 0.1][$0]) }
        let top = HourlyUse.busiest(h)
        #expect(top.map(\.start) == [h[1].start, h[2].start, h[4].start])
        #expect(HourlyUse.busiest(h, count: 10).map(\.start) == [h[1], h[2], h[4], h[0], h[5]].map(\.start))
        #expect(HourlyUse.busiest([]).isEmpty)
    }

    @Test func hourRangeCopy() {
        let tue4 = local(2026, 10, 6, 16)
        #expect(UsageCopy.hourRange(tue4, formatting: fmt) == "Tue 4–5 PM")
        #expect(UsageCopy.hourRange(tue4, formatting: Formatting(calendar: newYork, twentyFourHour: true)) == "Tue 16:00–17:00")
        #expect(UsageCopy.hourRange(local(2026, 10, 6, 11), formatting: fmt) == "Tue 11 AM–12 PM")
        #expect(UsageCopy.hourRange(local(2026, 10, 6, 23), formatting: fmt) == "Tue 11 PM–12 AM")
    }

    @Test func busiestHoursSkipTheStretchBeforeTheFirstReading() {
        // First reading ever: 58% on day 4. Nothing before it was seen, so no hour is "busy".
        let only = Self.r(58, local(2026, 10, 7, 12))
        let now = local(2026, 10, 7, 12, 30)
        #expect(HourlyUse.measuredBusiest(reading: only, history: [], now: now, calendar: newYork).isEmpty)
        // Two readings two hours apart: only those hours count, not the first 76 invented ones.
        let history = [Self.r(58, local(2026, 10, 7, 12)), Self.r(64, local(2026, 10, 7, 14))]
        let busy = HourlyUse.measuredBusiest(reading: Self.r(64, local(2026, 10, 7, 14)), history: history, now: local(2026, 10, 7, 15), calendar: newYork)
        #expect(busy.map(\.start) == [local(2026, 10, 7, 12), local(2026, 10, 7, 13)])
        #expect(busy.allSatisfy { near($0.used, 3, 0.001) })
        // The bars still take everything.
        let all = HourlyUse.hours(reading: Self.r(64, local(2026, 10, 7, 14)), history: history, now: local(2026, 10, 7, 15), calendar: newYork)
        #expect(all.first?.start == Self.start)
    }

    @Test func busiestHoursSkipAGapLongerThanThreeHours() {
        // 20% over 6 hours with nobody looking (the Mac asleep) is not a busy hour.
        let history = [Self.r(40, local(2026, 10, 7, 6)), Self.r(60, local(2026, 10, 7, 12)), Self.r(63, local(2026, 10, 7, 13))]
        let busy = HourlyUse.measuredBusiest(reading: Self.r(63, local(2026, 10, 7, 13)), history: history, now: local(2026, 10, 7, 13, 30), calendar: newYork)
        #expect(busy.map(\.start) == [local(2026, 10, 7, 12)])
        #expect(near(busy.first?.used ?? 0, 3, 0.001))
        // Exactly three hours still counts.
        let edge = [Self.r(40, local(2026, 10, 7, 6)), Self.r(46, local(2026, 10, 7, 9))]
        let counted = HourlyUse.measuredBusiest(reading: Self.r(46, local(2026, 10, 7, 9)), history: edge, now: local(2026, 10, 7, 10), calendar: newYork)
        #expect(counted.count == 3)
    }
}
