import Foundation
import Testing
@testable import TidemarkCore

@Suite struct LimitDetailTests {
    let week = LimitID(org: "personal", kind: .week)

    func detail(_ r: Reading, history: [Reading] = [], id: LimitID? = nil) -> LimitDetail? {
        LimitDetails.make(id ?? week, reading: r, history: history, now: forecastNow, calendar: newYork)
    }

    @Test func chartForALimitThatRunsOut() throws {
        let reset = local(2026, 10, 21, 21)
        let mid = reading(week: 20, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-20 * 3600))
        let d = try #require(detail(reading(week: 41, weekResetsAt: reset, at: forecastNow), history: [mid]))
        let nowX = (41.0 + 40.0 / 60) / 168
        #expect(near(d.nowX, nowX, 1e-9))
        #expect(near(d.elapsedFraction, nowX, 1e-9))
        #expect(d.usedLine.first == ChartPoint(x: 0, y: 0))
        #expect(d.usedLine.count == 3)
        #expect(near(d.usedLine.last!.y, 0.41, 1e-9))
        #expect(d.useItAll.last == ChartPoint(x: 1, y: 1))
        let out = try #require(d.runsOutAt)
        #expect(near(d.runsOut!.x, out.timeIntervalSince(d.windowStart) / Pace.window, 1e-9))
        #expect(d.lockedFromX == d.runsOut?.x)
        #expect(d.yourPace.count == 3)
        #expect(d.unused.isEmpty)
        #expect(near(d.paceMultiple!, d.forecast!.pacePerHour / d.forecast!.useItAllPerHour, 1e-9))
    }

    @Test func unusedWedgeOnlyFromTheThreshold() throws {
        let reset = local(2026, 10, 19, 4)
        let slow = try #require(detail(reading(week: 40, weekResetsAt: reset, at: forecastNow),
                                       history: [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600))]))
        #expect(slow.unused.count == 3)
        #expect(near(slow.unused[1].y, slow.forecast!.forecastAtReset / 100, 1e-9))
        #expect(slow.unused[2] == ChartPoint(x: 1, y: 1))
        #expect(slow.runsOut == nil)
        // About 97% at reset: 3% unused is under the 5% threshold.
        let close = try #require(detail(reading(week: 80, weekResetsAt: reset, at: forecastNow),
                                        history: [reading(week: 57.82, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600))]))
        #expect(near(close.forecast!.unused, 3, 0.1))
        #expect(close.unused.isEmpty)
    }

    @Test func noDetailBeforeTheWindowStarts() {
        #expect(detail(reading(week: 0, weekResetsAt: nil, at: forecastNow)) == nil)
    }

    @Test func ticksAtLocalNoonsForAWeek() throws {
        let d = try #require(detail(reading(week: 41, weekResetsAt: local(2026, 10, 21, 21), at: forecastNow)))
        #expect(d.ticks.map(\.date) == (15...21).map { local(2026, 10, $0, 12) })
    }

    @Test func ticksOnTheHourForFiveHours() throws {
        let r = reading(week: 10, weekResetsAt: local(2026, 10, 21, 21), session: 62,
                        sessionResetsAt: local(2026, 10, 16, 17, 20), at: forecastNow)
        let d = try #require(detail(r, id: LimitID(org: "personal", kind: .session)))
        #expect(d.ticks.map(\.date) == (13...17).map { local(2026, 10, 16, $0) })
        #expect(d.perDayLine == nil)
    }

    @Test func dailyRisesAcrossAReset() {
        let r1 = local(2026, 10, 15, 12), r2 = local(2026, 10, 22, 12)
        let series = [
            SeriesPoint(time: local(2026, 10, 14, 10), value: 10, resetsAt: r1),
            SeriesPoint(time: local(2026, 10, 14, 18), value: 30, resetsAt: r1),
            SeriesPoint(time: local(2026, 10, 15, 9), value: 35, resetsAt: r1),
            SeriesPoint(time: local(2026, 10, 15, 14), value: 4, resetsAt: r2),
            SeriesPoint(time: local(2026, 10, 16, 9), value: 20, resetsAt: r2),
            SeriesPoint(time: local(2026, 10, 16, 11), value: 18, resetsAt: r2),
        ]
        let days = LimitDetails.dailyRises(series, now: forecastNow, calendar: newYork)
        #expect(days.map(\.day) == (10...16).map { local(2026, 10, $0) })
        #expect(days.map(\.value) == [0, 0, 0, 0, 20, 9, 16])
    }

    @Test func dailyRisesAcrossMidnight() {
        let r = local(2026, 10, 20, 12)
        let series = [SeriesPoint(time: local(2026, 10, 15, 23, 50), value: 10, resetsAt: r),
                      SeriesPoint(time: local(2026, 10, 16, 0, 10), value: 12, resetsAt: r)]
        #expect(LimitDetails.dailyRises(series, now: forecastNow, calendar: newYork).map(\.value) == [0, 0, 0, 0, 0, 0, 2])
    }

    @Test func noUnusedWedgeForAModelLimit() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600), scoped: ["Fable": 0])]
        let r = reading(week: 40, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 1])
        let d = try #require(detail(r, history: history, id: LimitID(org: "personal", kind: .model("Fable"))))
        #expect(d.unused.isEmpty)
        let unused = try #require(UsageCopy.stats(d, now: forecastNow, formatting: fmt).first { $0.label == "Left at reset" })
        #expect(!unused.value.isEmpty)
    }

    @Test func modelLimitBarsAreNeverUnder() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600), scoped: ["Fable": 0]),
                       reading(week: 20, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-50 * 3600), scoped: ["Fable": 1]),
                       reading(week: 30, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-26 * 3600), scoped: ["Fable": 2])]
        let r = reading(week: 40, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 3])
        let d = try #require(detail(r, history: history, id: LimitID(org: "personal", kind: .model("Fable"))))
        #expect(d.bars.contains { ($0.value ?? 0) > 0 })
        #expect(d.bars.allSatisfy { $0.tone != .under })
        #expect(LimitDetails.tone(1, line: 70, today: false, kind: .model("Fable")) == .withinLimit)
        #expect(LimitDetails.tone(100, line: 70, today: false, kind: .model("Fable")) == .hitLimit)
    }

    @Test func tones() {
        #expect(LimitDetails.tone(5, line: 11.2, today: false, kind: .week) == .under)
        #expect(LimitDetails.tone(11, line: 11.2, today: false, kind: .week) == .onPace)
        #expect(LimitDetails.tone(15, line: 11.2, today: false, kind: .week) == .over)
        #expect(LimitDetails.tone(15, line: 11.2, today: true, kind: .week) == .today)
    }

    @Test func dailyBarsOnTheDetail() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600)),
                       reading(week: 40, weekResetsAt: reset, at: forecastNow)]
        let d = try #require(detail(reading(week: 40, weekResetsAt: reset, at: forecastNow), history: history))
        #expect(d.bars.count == 7)
        #expect(d.bars.last?.tone == .today)
        #expect(near(d.perDayLine!, d.forecast!.useItAllPerDay, 1e-9))
    }

    @Test func recentWindowsPeaksOldestFirst() {
        func p(_ h: Int, _ v: Double, _ reset: Date?) -> SeriesPoint {
            SeriesPoint(time: local(2026, 10, 16, h), value: v, resetsAt: reset)
        }
        let a = local(2026, 10, 16, 5), b = local(2026, 10, 16, 11), c = local(2026, 10, 16, 17)
        let series = [p(1, 30, a), p(4, 100, a), p(7, 20, b), p(9, 45, b), p(13, 10, c), p(14, 0, nil)]
        let bars = LimitDetails.recentWindows(series)
        #expect(bars.map(\.date) == [a, b, c].map { $0.addingTimeInterval(-5 * 3600) })
        #expect(bars.map(\.value) == [100, 45, 10])
        #expect(bars.map(\.tone) == [.hitLimit, .plain, .plain])
        #expect(LimitDetails.recentWindows(series, count: 2).map(\.value) == [45, 10])
        // The window still open at `now` is marked, not counted as a past one (S3.11).
        let open = LimitDetails.recentWindows(series, now: local(2026, 10, 16, 15))
        #expect(open.map(\.tone) == [.hitLimit, .plain, .openWindow])
    }

    // MARK: Usage pane honesty (S3.1, S3.3, S3.4, S3.5, S3.9 to S3.12)

    @Test func noBarsBeforeTheFirstReading() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 9, weekResetsAt: reset, at: local(2026, 10, 14, 10)),
                       reading(week: 20, weekResetsAt: reset, at: local(2026, 10, 14, 18)),
                       reading(week: 30, weekResetsAt: reset, at: local(2026, 10, 15, 12)),
                       reading(week: 40, weekResetsAt: reset, at: forecastNow)]
        let d = try #require(detail(reading(week: 40, weekResetsAt: reset, at: forecastNow), history: history))
        #expect(d.bars.count == 7)
        // 10 to 13 Oct came before Tidemark's first reading: no value, no tone.
        #expect(d.bars.prefix(4).allSatisfy { $0.value == nil && $0.tone == .noData })
        // The day of the first reading and everything after has a bar, even a zero one.
        #expect(d.bars.suffix(3).allSatisfy { $0.value != nil })
        #expect(d.bars[4].value == 11)
        #expect(UsageCopy.barsSummary(d, now: forecastNow, formatting: fmt).contains("Sat no data"))
    }

    @Test func todayHasItsOwnKey() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600)),
                       reading(week: 40, weekResetsAt: reset, at: forecastNow)]
        let d = try #require(detail(reading(week: 40, weekResetsAt: reset, at: forecastNow), history: history))
        #expect(d.bars.last?.tone == .today)
        #expect(UsageCopy.barKeys(d) == ["On pace", "Under", "Over", "Today so far", "Use-it-all/day"])
    }

    @Test func modelLimitHasNoUseItAll() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600), scoped: ["Fable": 0]),
                       reading(week: 20, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-26 * 3600), scoped: ["Fable": 4])]
        let r = reading(week: 40, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 9])
        let d = try #require(detail(r, history: history, id: LimitID(org: "personal", kind: .model("Fable"))))
        #expect(d.perDayLine == nil)
        #expect(d.useItAll.isEmpty)
        #expect(UsageCopy.barsCaption(d) == nil)
        #expect(UsageCopy.barKeys(d) == ["Within limit", "Reached 100%", "Today so far"])
        #expect(d.bars.allSatisfy { [.withinLimit, .today, .noData, .hitLimit].contains($0.tone) })
        #expect(UsageCopy.stats(d, now: forecastNow, formatting: fmt).map(\.label) == ["At reset", "Left at reset"])
    }

    @Test func refusedPlanSaysWhy() {
        #expect(UsageCopy.unreadLine(.refused) == "Couldn’t read: access refused · trying again")
        #expect(UsageCopy.unreadLine(.offline) == "Couldn’t read: no connection · trying again")
        #expect(UsageCopy.unreadLine(.http(503)) == "Couldn’t read: claude.ai error 503 · trying again")
        #expect(UsageCopy.unreadLine(nil) == "No reading yet")
    }

    @Test func todayLineReadsAfterItsLabel() {
        let main = UsageCopy.todayLine(Copy.Today(main: "Only 5% left until Wed 9 PM, about 2 hours at your recent pace.", warning: nil))
        #expect(main.main == "Today: only 5% left until Wed 9 PM, about 2 hours at your recent pace.")
        #expect(UsageCopy.todayLine(Copy.Today(main: "Use the last 12% before Fri 4 AM.", warning: "At your current ~4% a day, ...")).main
                == "Today: use the last 12% before Fri 4 AM.")
        #expect(UsageCopy.todayLine(Copy.Today(main: "This week hasn’t started. Nothing is used yet.", warning: nil)).main
                == "Today: this week hasn’t started. Nothing is used yet.")
    }

    @Test func asOfIsItsOwnLine() {
        #expect(UsageCopy.asOfLine(local(2026, 10, 21, 11, 32), now: local(2026, 10, 21, 12), formatting: fmt) == "As of 11:32 AM")
    }

    @Test func sessionBarsKeyPeakAndTheOpenWindow() throws {
        let r = reading(week: 10, weekResetsAt: local(2026, 10, 21, 21), session: 62,
                        sessionResetsAt: local(2026, 10, 16, 17, 20), at: forecastNow)
        let past = reading(week: 5, weekResetsAt: local(2026, 10, 21, 21), session: 100,
                           sessionResetsAt: local(2026, 10, 16, 9), at: local(2026, 10, 16, 6))
        let d = try #require(detail(r, history: [past, r], id: LimitID(org: "personal", kind: .session)))
        #expect(d.bars.map(\.tone) == [.hitLimit, .openWindow])
        #expect(UsageCopy.barKeys(d) == ["Peak", "Reached 100%", "Open window"])
    }

    @Test func headlineIgnoresTheRowsFilter() {
        // Personal’s Fable limit is nearly used up and runs out early; the model rows are hidden.
        let reset = local(2026, 10, 21, 21)
        let personal = Org(id: "personal", name: "Personal")
        let r = reading(week: 30, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 70])
        let old = reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-76 * 3600), scoped: ["Fable": 10])
        let input = UsageInput(orgs: [personal], latest: ["personal": r], history: [old, r], states: ["personal": .fine],
                               claudeCodeOrg: "personal", signedIn: true, showModelLimits: false, showSessionLimits: false,
                               now: forecastNow, formatting: fmt, calendar: newYork)
        let summary = UsageSummary.make(input)
        #expect(summary.headline.title.contains("Fable"))
        #expect(summary.limits.allSatisfy { $0.id.kind == .week })
    }

    // M4: days with no reading aren't zeros, and the day after a gap says it holds them.
    @Test func daysWithoutReadingsAreNotZeros() throws {
        let reset = local(2026, 10, 22, 4)
        // Read on Mon 12, then not again until Thu 15 (the Mac slept), then now (Fri 16).
        let history = [reading(week: 10, weekResetsAt: reset, at: local(2026, 10, 12, 9)),
                       reading(week: 40, weekResetsAt: reset, at: local(2026, 10, 15, 9)),
                       reading(week: 46, weekResetsAt: reset, at: forecastNow)]
        let d = try #require(detail(reading(week: 46, weekResetsAt: reset, at: forecastNow), history: history))
        let byDay = Dictionary(uniqueKeysWithValues: d.bars.map { (newYork.component(.day, from: $0.date), $0) })
        #expect(byDay[13]?.tone == .noData && byDay[13]?.value == nil)
        #expect(byDay[14]?.tone == .noData && byDay[14]?.value == nil)
        // Thursday holds the use of three days: no verdict, and it says so.
        #expect(byDay[15]?.value == 30)
        #expect(byDay[15]?.includesDays == 3)
        #expect(byDay[15]?.tone == .plain)
        #expect(byDay[16]?.tone == .today && byDay[16]?.includesDays == 1)
        #expect(UsageCopy.gapNote(d, formatting: fmt) == "Thu holds 3 days of use: nothing was read on Tue or Wed.")
    }

    @Test func noGapNoteWhenEveryDayWasRead() throws {
        let reset = local(2026, 10, 19, 4)
        let history = [-80.0, -56, -32, -8].map { reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval($0 * 3600)) }
            + [reading(week: 40, weekResetsAt: reset, at: forecastNow)]
        let d = try #require(detail(reading(week: 40, weekResetsAt: reset, at: forecastNow), history: history))
        #expect(UsageCopy.gapNote(d, formatting: fmt) == nil)
    }
}
