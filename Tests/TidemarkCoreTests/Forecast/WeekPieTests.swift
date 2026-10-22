import Testing
import Foundation
@testable import TidemarkCore

@Suite struct WeekPieSuite {
    static let day: TimeInterval = 86_400

    // Personal: week from Fri 4 AM, now Wed 11:32, 58% used, no run-out.
    static let personalStart = local(2026, 10, 2, 4)
    static let personalReset = local(2026, 10, 9, 4)
    static let personalNow = local(2026, 10, 7, 11, 32)

    static func personal(_ week: Double, at time: Date, org: String = "personal") -> Reading {
        reading(org: org, week: week, weekResetsAt: personalReset, at: time)
    }

    static var personalHistory: [Reading] {
        let s = personalStart
        return [personal(8, at: s.addingTimeInterval(day)), personal(12, at: s.addingTimeInterval(2 * day)),
                personal(22, at: s.addingTimeInterval(3 * day)), personal(36, at: s.addingTimeInterval(4 * day)),
                personal(50, at: s.addingTimeInterval(5 * day))]
    }

    // Harbor Labs: week from Sun 9 AM, 81% used, runs out Thursday evening.
    static let harborStart = local(2026, 10, 4, 9)
    static let harborReset = local(2026, 10, 11, 9)
    static let harborNow = local(2026, 10, 7, 11, 32)

    static func harbor(_ week: Double, at time: Date, reset: Date = harborReset) -> Reading {
        reading(org: "harbor", week: week, weekResetsAt: reset, at: time)
    }

    static var harborHistory: [Reading] {
        [harbor(40, at: local(2026, 10, 4, 10)), harbor(55, at: local(2026, 10, 5, 9)),
         harbor(66, at: local(2026, 10, 6, 9)), harbor(74, at: local(2026, 10, 7, 9))]
    }

    static func heavy(_ use: Double) -> Double { min(1, use / (100.0 / 7)) }

    @Test func personalIsFiveDaysDoneTodayAndTwoAhead() throws {
        let now = Self.personalNow
        let pie = try #require(WeekPie.make(reading: Self.personal(58, at: now), history: Self.personalHistory, now: now))
        #expect(pie.segments.count == 7)
        // The first reading came on day 1, so day 0 is not guessed at.
        #expect(pie.segments[0] == .unseen)
        let uses: [Double] = [4, 10, 14, 14]
        for (n, use) in uses.enumerated() {
            let i = n + 1
            guard case .used(let h) = pie.segments[i] else { Issue.record("day \(i) is \(pie.segments[i])"); continue }
            #expect(near(h, Self.heavy(use), 0.001))
        }
        guard case .today(let elapsed, let heaviness) = pie.segments[5] else { Issue.record("today is \(pie.segments[5])"); return }
        #expect(near(elapsed, 7.533 / 24, 0.002))
        #expect(near(heaviness, Self.heavy(8), 0.001))
        #expect(pie.segments[6] == .ahead)
        #expect(pie.now.day == 5)
        #expect(near(pie.now.fraction, 7.533 / 24, 0.002))
        #expect(pie.runsOut == nil)
        #expect(pie.used == 58)
    }

    @Test func harborRunsOutThursdayAndLocksTheRest() throws {
        let now = Self.harborNow
        let r = Self.harbor(81, at: now)
        let pie = try #require(WeekPie.make(reading: r, history: Self.harborHistory, now: now))
        let out = try #require(Pace.forecast(r, history: Self.harborHistory, now: now)?.runsOutAt)
        let outFraction = out.timeIntervalSince(Self.harborStart.addingTimeInterval(4 * Self.day)) / Self.day
        #expect(near(outFraction, 0.525, 0.01))   // Thu ~9:36 PM
        for i in 0..<3 { if case .used = pie.segments[i] {} else { Issue.record("day \(i) is \(pie.segments[i])") } }
        #expect(pie.segments[3] == .today(elapsed: pie.now.fraction, heaviness: Self.heavy(7)))
        guard case .runsOut(let at) = pie.segments[4] else { Issue.record("Thursday is \(pie.segments[4])"); return }
        #expect(near(at, outFraction, 0.001))
        #expect(pie.segments[5] == .locked)
        #expect(pie.segments[6] == .locked)
        #expect(pie.now.day == 3)
        #expect(pie.runsOut?.day == 4)
        #expect(near(pie.runsOut?.fraction ?? 0, outFraction, 0.001))
        #expect(pie.used == 81)
    }

    @Test func oneReadingLeavesTheDaysBeforeItEmpty() throws {
        // Tidemark's first reading of the week came on day 5: days 0 to 4 are not guessed at.
        let now = Self.personalNow
        let pie = try #require(WeekPie.make(reading: Self.personal(58, at: now), history: [], now: now))
        for i in 0..<5 { #expect(pie.segments[i] == .unseen, "day \(i) is \(pie.segments[i])") }
        if case .today = pie.segments[5] {} else { Issue.record("today is \(pie.segments[5])") }
        #expect(pie.segments[6] == .ahead)
        // A first reading in the week's first hour counts as the whole week.
        let early = Self.personalStart.addingTimeInterval(1800)
        let fresh = try #require(WeekPie.make(reading: Self.personal(1, at: early), history: [], now: early))
        if case .unseen = fresh.segments[0] { Issue.record("day 0 is unseen") }
        // Days after the first reading are drawn from what was read.
        let history = [Self.personal(8, at: Self.personalStart.addingTimeInterval(2 * Self.day))]
        let later = try #require(WeekPie.make(reading: Self.personal(58, at: now), history: history, now: now))
        #expect(later.segments[0] == .unseen)
        #expect(later.segments[1] == .unseen)
        if case .used = later.segments[2] {} else { Issue.record("day 2 is \(later.segments[2])") }
    }

    @Test func readingsFromAnEarlierWindowAreIgnored() throws {
        let now = Self.personalNow
        let oldReset = local(2026, 10, 2, 4)
        let old = [reading(org: "personal", week: 97, weekResetsAt: oldReset, at: local(2026, 10, 1, 20)),
                   reading(org: "other", week: 90, weekResetsAt: Self.personalReset, at: local(2026, 10, 3, 4))]
        let withOld = try #require(WeekPie.make(reading: Self.personal(58, at: now), history: old, now: now))
        let without = try #require(WeekPie.make(reading: Self.personal(58, at: now), history: [], now: now))
        #expect(withOld == without)
    }

    @Test func outSinceMondayEveningLocksTheDaysAfter() throws {
        let now = Self.harborNow
        let history = [Self.harbor(40, at: local(2026, 10, 4, 10)), Self.harbor(100, at: local(2026, 10, 5, 18)),
                       Self.harbor(100, at: local(2026, 10, 6, 12))]
        let pie = try #require(WeekPie.make(reading: Self.harbor(100, at: now), history: history, now: now))
        if case .used = pie.segments[0] {} else { Issue.record("\(pie.segments[0])") }
        guard case .ranOut(let at, let heaviness) = pie.segments[1] else { Issue.record("\(pie.segments[1])"); return }
        #expect(near(at, 9.0 / 24, 0.001))
        #expect(heaviness == 1)
        for i in 2...6 { #expect(pie.segments[i] == .locked) }
        #expect(pie.runsOut == WeekPie.Point(day: 1, fraction: at))
        #expect(pie.used == 100)
        #expect(pie.now.day == 3)
    }

    @Test func nilWithoutAnOpenWeek() {
        let now = Self.personalNow
        #expect(WeekPie.make(reading: reading(week: 0, weekResetsAt: nil, at: now), history: [], now: now) == nil)
        #expect(WeekPie.make(reading: Self.personal(58, at: now), history: [], now: Self.personalReset) == nil)
    }

    @Test func aRunOutTodayKeepsTodaysUseBoldThenTrackThenLocked() throws {
        // Thursday 11 AM, 94% used and climbing 20 points a day: the forecast empties it this evening, so
        // today is the day it runs out in.
        let now = local(2026, 10, 8, 11)
        let history = [Self.harbor(40, at: local(2026, 10, 4, 10)), Self.harbor(60, at: local(2026, 10, 6, 11)),
                       Self.harbor(80, at: local(2026, 10, 7, 11))]
        let r = Self.harbor(94, at: now)
        let out = try #require(Pace.forecast(r, history: history, now: now)?.runsOutAt)
        let start = Self.harborStart
        #expect(out > now && out < Self.harborReset)
        let pie = try #require(WeekPie.make(reading: r, history: history, now: now))
        #expect(pie.now.day == 4)
        guard case .todayRunsOut(let elapsed, let at, let heaviness) = pie.segments[4] else {
            Issue.record("today is \(pie.segments[4])"); return
        }
        #expect(near(elapsed, pie.now.fraction, 0.0001))
        #expect(near(at, out.timeIntervalSince(start.addingTimeInterval(4 * Self.day)) / Self.day, 0.001))
        #expect(at > elapsed)
        #expect(heaviness > 0)   // today's own use so far, not an empty day
        #expect(pie.segments[5] == .locked)
        #expect(pie.runsOut?.day == 4)
    }
}
