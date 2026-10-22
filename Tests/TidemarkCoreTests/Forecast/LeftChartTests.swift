import Testing
import Foundation
@testable import TidemarkCore

@Suite struct LeftChartSuite {
    static let start = local(2026, 10, 4, 9)
    static let reset = local(2026, 10, 11, 9)
    static let now = local(2026, 10, 7, 11, 32)
    static let window = 168.0 * 3600

    static func r(_ week: Double, _ time: Date, reset: Date = reset) -> Reading {
        reading(org: "harbor", week: week, weekResetsAt: reset, at: time)
    }

    static let harborHistory = [r(40, local(2026, 10, 4, 10)), r(55, local(2026, 10, 5, 9)),
                                r(66, local(2026, 10, 6, 9)), r(74, local(2026, 10, 7, 9))]

    @Test func whatIsLeftThroughTheWeekWithTheRunOutAhead() throws {
        let current = Self.r(81, Self.now)
        let chart = try #require(LeftChart.make(reading: current, history: Self.harborHistory, now: Self.now))
        #expect(chart.start == Self.start)
        #expect(chart.reset == Self.reset)
        #expect(chart.left.first == ChartPoint(x: 0, y: 1))
        #expect(chart.left.count == 6)   // start, four readings, now
        #expect(near(chart.left[1].y, 0.60, 0.0001))
        let nowX = Self.now.timeIntervalSince(Self.start) / Self.window
        let now = try #require(chart.now)
        #expect(near(now.x, nowX, 0.0001))
        #expect(near(now.y, 0.19, 0.0001))
        #expect(chart.left.last == now)

        let out = try #require(Pace.forecast(current, history: Self.harborHistory, now: Self.now)?.runsOutAt)
        let outX = out.timeIntervalSince(Self.start) / Self.window
        let end = try #require(chart.forecastEnd)
        #expect(near(end.x, outX, 0.0001))
        #expect(end.y == 0)
        #expect(near(chart.lockedFrom ?? 0, outX, 0.0001))
        #expect(near(outX, 0.646, 0.002))
    }

    @Test func daysAreThePlansOwnAndHoursAddUp() throws {
        let chart = try #require(LeftChart.make(reading: Self.r(81, Self.now), history: Self.harborHistory, now: Self.now))
        #expect(chart.days.count == 8)
        #expect(chart.days.map(\.date) == (0...7).map { Self.start.addingTimeInterval(Double($0) * 86_400) })
        #expect(chart.days.first?.x == 0)
        #expect(near(chart.days.last?.x ?? 0, 1, 0.0001))
        #expect(near(chart.hours.reduce(0) { $0 + $1.used }, 81, 0.001))
        #expect(chart.hours.allSatisfy { $0.x >= 0 && $0.x + $0.width <= 1.0001 && $0.width <= 3600 / Self.window + 0.0001 })
    }

    @Test func aPlanHeadingForSpareEndsTheDashedLineAtTheReset() throws {
        let personalReset = local(2026, 10, 9, 4)
        let now = local(2026, 10, 7, 11, 32)
        let r = reading(week: 58, weekResetsAt: personalReset, at: now)
        let chart = try #require(LeftChart.make(reading: r, history: [], now: now))
        let forecast = try #require(Pace.forecast(r, history: [], now: now))
        #expect(forecast.runsOutAt == nil)
        let end = try #require(chart.forecastEnd)
        #expect(end.x == 1)
        #expect(near(end.y, 1 - forecast.forecastAtReset / 100, 0.0001))
        #expect(chart.lockedFrom == nil)
    }

    // An hour after a reset: no dashed line ahead and nothing locked.
    @Test func aWeekThatJustResetDrawsNoForecast() throws {
        let fresh = Self.now.addingTimeInterval(167 * 3600)
        let chart = try #require(LeftChart.make(reading: reading(week: 2, weekResetsAt: fresh, at: Self.now), history: [], now: Self.now))
        #expect(chart.forecastEnd == nil)
        #expect(chart.lockedFrom == nil)
        #expect(chart.now != nil)
    }

    @Test func alreadyOutLocksFromWhenItRanOut() throws {
        let history = [Self.r(40, local(2026, 10, 4, 10)), Self.r(100, local(2026, 10, 5, 18))]
        let chart = try #require(LeftChart.make(reading: Self.r(100, Self.now), history: history, now: Self.now))
        #expect(near(chart.lockedFrom ?? 0, 33.0 / 168, 0.0001))
        #expect(chart.forecastEnd == nil)
        #expect(chart.now?.y == 0)
    }

    @Test func nilWithoutAnOpenWeek() {
        #expect(LeftChart.make(reading: reading(week: 0, weekResetsAt: nil), history: [], now: designNow) == nil)
        #expect(LeftChart.make(reading: Self.r(50, Self.now), history: [], now: Self.reset) == nil)
    }

    @Test func lastWeekIsReadBackFromHistory() throws {
        let lastReset = Self.start
        let history = [Self.r(30, local(2026, 9, 29, 12), reset: lastReset), Self.r(60, local(2026, 10, 1, 12), reset: lastReset),
                       Self.r(90, local(2026, 10, 3, 20), reset: lastReset)] + Self.harborHistory
        let chart = try #require(LeftChart.lastWeek(reading: Self.r(81, Self.now), history: history))
        #expect(chart.start == local(2026, 9, 27, 9))
        #expect(chart.reset == lastReset)
        #expect(chart.now == nil)
        #expect(chart.forecastEnd == nil)
        #expect(chart.lockedFrom == nil)
        #expect(chart.left.count == 4)   // start and three readings
        #expect(near(chart.left.last?.y ?? 1, 0.10, 0.0001))
        #expect(near(chart.hours.reduce(0) { $0 + $1.used }, 90, 0.001))
        #expect(chart.days.count == 8)
    }

    @Test func lastWeekIsNilWithoutReadingsInIt() {
        #expect(LeftChart.lastWeek(reading: Self.r(81, Self.now), history: Self.harborHistory) == nil)
        #expect(LeftChart.lastWeek(reading: reading(week: 0, weekResetsAt: nil), history: []) == nil)
    }
}
