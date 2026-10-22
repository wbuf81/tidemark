import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ForecastRowsTests {
    func rows(_ latest: [Reading], history: [Reading] = [], orgs: [String]? = nil, now: Date = forecastNow) -> [ForecastRow] {
        ForecastRows.make(orgs: orgs ?? latest.map(\.org), latest: Dictionary(uniqueKeysWithValues: latest.map { ($0.org, $0) }),
                          history: history, now: now, calendar: newYork)
    }

    @Test func weekRowStaysWhenStale() {
        let old = reading(week: 30, weekResetsAt: local(2026, 10, 23, 4), at: forecastNow.addingTimeInterval(-20 * 60))
        let latest = [old.org: old]
        let row = ForecastRows.weekRow(org: old.org, latest: latest, history: [], now: forecastNow, calendar: newYork)
        #expect(row?.used == 30 && row?.isStale == false)
        #expect(ForecastRows.weekRow(org: "nobody", latest: latest, history: [], now: forecastNow, calendar: newYork) == nil)
    }

    @Test func usedCarriesForwardUntilItsReset() {
        let r = local(2026, 10, 14, 21)
        let series = [SeriesPoint(time: local(2026, 10, 13, 9), value: 50, resetsAt: r)]
        #expect(ForecastRows.used(at: local(2026, 10, 13, 8), series) == nil)
        #expect(ForecastRows.used(at: local(2026, 10, 14, 20), series) == 50)
        #expect(ForecastRows.used(at: local(2026, 10, 14, 22), series) == 0)
    }

    @Test func staleOrg() {
        let time = forecastNow.addingTimeInterval(-20 * 60)
        let row = rows([reading(week: 41, weekResetsAt: local(2026, 10, 21, 21), at: time)]).first
        #expect(row?.since == time)
        #expect(row?.isStale == true)
        #expect(row?.forecast != nil)
    }

    @Test func neverReadOrg() {
        let r = rows([], orgs: ["harbor"])
        #expect(r.count == 1)
        #expect(r.first?.id == LimitID(org: "harbor", kind: .week))
        #expect(r.first?.isStale == true && r.first?.since == nil)
    }

    @Test func rowOrderAcrossOrgs() {
        let reset = local(2026, 10, 21, 21)
        let r = rows([reading(week: 10, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 3, "Atlas": 1]),
                      reading(org: "harbor", week: 10, weekResetsAt: reset, at: forecastNow)])
        #expect(r.map(\.id) == [
            LimitID(org: "personal", kind: .week), LimitID(org: "personal", kind: .model("Atlas")),
            LimitID(org: "personal", kind: .model("Fable")), LimitID(org: "personal", kind: .session),
            LimitID(org: "harbor", kind: .week), LimitID(org: "harbor", kind: .session),
        ])
    }

    @Test func alreadyUsedUpIsLockedFromNow() {
        let row = rows([reading(week: 100, weekResetsAt: local(2026, 10, 21, 21), at: forecastNow)]).first
        #expect(row?.runsOutAt == forecastNow)
    }

    // MARK: Day bars (the Usage pane's per-plan rows): seven 24-hour days of the plan's own week

    func bars(_ latest: Reading, history: [Reading]) -> [DayBar] {
        ForecastRows.dayBars(org: latest.org, latest: [latest.org: latest], history: history, now: forecastNow, calendar: newYork)
    }

    @Test func dayBarsPastSolidAndForecastPaler() throws {
        // The window runs Wed 14 Oct 9 PM to Wed 21 Oct 9 PM; now is Fri 16 Oct 2:40 PM, in its second day.
        let reset = local(2026, 10, 21, 21)
        let history = [reading(week: 5, weekResetsAt: reset, at: local(2026, 10, 14, 22)),
                       reading(week: 30, weekResetsAt: reset, at: local(2026, 10, 15, 20))]
        let days = bars(reading(week: 40, weekResetsAt: reset, at: forecastNow), history: history)
        #expect(days.count == 7)
        #expect(days.map(\.date) == (0..<7).map { local(2026, 10, 14, 21).addingTimeInterval(Double($0) * 86400) })
        #expect(days[0].value == 30 && !days[0].isForecast && !days[0].isToday)
        #expect(days[1].value == 40 && days[1].isToday && !days[1].isForecast)
        // 40% in 41 h 40 min is 0.96 a point an hour: 69% by the end of the third day, 92% by the fourth,
        // out on Monday 19 Oct at 5 AM.
        #expect(near(days[2].value!, 40 + 0.96 * (30 + 20.0 / 60), 0.01) && days[2].isForecast)
        #expect(near(days[3].value!, 40 + 0.96 * (54 + 20.0 / 60), 0.01))
        #expect(days[4...].allSatisfy { $0.value == 100 && $0.isForecast })
    }

    @Test func dayBarsNoBarsBeforeTheFirstReading() {
        let days = bars(reading(week: 50, weekResetsAt: local(2026, 10, 21, 21), at: forecastNow), history: [])
        #expect(days[0].value == nil)
        #expect(days[1].value == 50 && days[1].isToday)
        #expect(days.filter { $0.value != nil && !$0.isForecast }.count == 1)
    }

    @Test func dayBarsLockAtOneHundredOnceItRunsOut() {
        let days = bars(reading(week: 90, weekResetsAt: local(2026, 10, 21, 21), at: forecastNow), history: [])
        #expect(days[2].value == 100 && days[2].isForecast)
        #expect(days[6].value == 100)
    }

    @Test func dayBarsLastingToTheResetStayBelowTheTop() {
        let reset = local(2026, 10, 21, 21)
        let calm = [reading(week: 2, weekResetsAt: reset, at: local(2026, 10, 14, 22))]
        let days = bars(reading(week: 10, weekResetsAt: reset, at: forecastNow), history: calm)
        #expect(days[2...].allSatisfy { $0.isForecast && $0.value! < 100 })
        #expect(days[2].value! < days[6].value!)
    }

    @Test func dayBarsForAWeekThatHasNotStartedOrAPlanNeverRead() {
        #expect(bars(reading(week: 0, weekResetsAt: nil, at: forecastNow), history: []).isEmpty)
        #expect(ForecastRows.dayBars(org: "nobody", latest: [:], history: [], now: forecastNow, calendar: newYork).isEmpty)
    }

    @Test func dayBarsAfterAResetCountTheNewWindow() {
        let r1 = local(2026, 10, 14, 4), r2 = local(2026, 10, 21, 4)
        let history = [reading(week: 80, weekResetsAt: r1, at: local(2026, 10, 13, 20)),
                       reading(week: 5, weekResetsAt: r2, at: local(2026, 10, 14, 9))]
        let days = bars(reading(week: 30, weekResetsAt: r2, at: forecastNow), history: history)
        // The old window's 80% belongs to last week's row, not this one's.
        #expect(days[0].value == 5)
        #expect(days[1].value == 5)
        #expect(days[2].value == 30 && days[2].isToday)
    }

    // L7: an old reading's paler bars come from the reading's time, so they don't drift as the clock moves.
    @Test func dayBarsForAnOldReadingDoNotDrift() {
        let reset = local(2026, 10, 21, 21)
        let read = forecastNow.addingTimeInterval(-3 * 3600)
        let old = reading(week: 40, weekResetsAt: reset, at: read)
        func later(_ hours: Double) -> [DayBar] {
            ForecastRows.dayBars(org: old.org, latest: [old.org: old], history: [old],
                                 now: forecastNow.addingTimeInterval(hours * 3600), calendar: newYork)
        }
        let a = later(0), b = later(1)
        #expect(a.map(\.value) == b.map(\.value))
        #expect(a.filter(\.isForecast).count == b.filter(\.isForecast).count)
    }
}
