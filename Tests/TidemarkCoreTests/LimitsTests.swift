import Foundation
import Testing
@testable import TidemarkCore

@Suite struct LimitsTests {
    let reset = designNow.addingTimeInterval(64.6 * 3600)

    @Test func kindsInRowOrder() {
        let r = reading(week: 1, weekResetsAt: reset, scoped: ["Fable": 1, "Atlas": 2])
        #expect(Limits.kinds(of: r) == [.week, .model("Atlas"), .model("Fable"), .session])
    }

    @Test func valuesForEachKind() throws {
        var r = reading(week: 55, weekResetsAt: reset, session: 12, sessionResetsAt: designNow.addingTimeInterval(3600),
                        scoped: ["Fable": 31, "Atlas": 4])
        r.scopedResetsAt = ["Atlas": reset.addingTimeInterval(-3600)]
        let week = try #require(Limits.value(.week, in: r))
        #expect(week.used == 55 && week.resetsAt == reset)
        let fable = try #require(Limits.value(.model("Fable"), in: r))
        #expect(fable.used == 31 && fable.resetsAt == reset)
        let atlas = try #require(Limits.value(.model("Atlas"), in: r))
        #expect(atlas.used == 4 && atlas.resetsAt == reset.addingTimeInterval(-3600))
        let session = try #require(Limits.value(.session, in: r))
        #expect(session.used == 12 && session.resetsAt == designNow.addingTimeInterval(3600))
        #expect(Limits.value(.model("Nope"), in: r) == nil)
    }

    @Test func stateKeepsOnlyThisWindowOfThisOrg() throws {
        let r = reading(week: 55, weekResetsAt: reset, scoped: ["Fable": 30])
        let history = [
            reading(week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-3 * 3600), scoped: ["Fable": 10]),
            reading(week: 90, weekResetsAt: reset.addingTimeInterval(-Pace.window), at: designNow.addingTimeInterval(-90 * 3600)),
            reading(org: "harbor", week: 5, weekResetsAt: reset, at: designNow.addingTimeInterval(-3600)),
            reading(week: 60, weekResetsAt: reset, at: designNow.addingTimeInterval(60)),
            reading(week: 10, weekResetsAt: reset, at: designNow.addingTimeInterval(-6 * 3600), scoped: ["Fable": 2]),
        ]
        let week = try #require(Limits.state(LimitID(org: "personal", kind: .week), reading: r, history: history, now: designNow))
        #expect(week.past.map(\.value) == [10, 20])
        #expect(week.windowStart == reset.addingTimeInterval(-Pace.window))
        let fable = try #require(Limits.state(LimitID(org: "personal", kind: .model("Fable")), reading: r, history: history, now: designNow))
        #expect(fable.past.map(\.value) == [2, 10])
        #expect(fable.used == 30)
    }

    @Test func modelLimitPacesFromItsOwnHistory() throws {
        var r = reading(week: 55, weekResetsAt: reset, scoped: ["Fable": 30])
        r.scopedResetsAt = ["Fable": reset]
        let old = reading(week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600), scoped: ["Fable": 10])
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .model("Fable")), reading: r, history: [old], now: designNow))
        let f = try #require(Limits.forecast(state, now: designNow, calendar: newYork))
        #expect(near(f.pacePerHour, 20.0 / 80, 0.0001))
    }

    @Test func sessionForecastAveragesSinceTheWindowOpened() throws {
        // 50% used 2 h into the window: 25%/h, so the last 50% lasts 2 h of the 3 h left.
        let r = reading(week: 10, weekResetsAt: reset, session: 50, sessionResetsAt: designNow.addingTimeInterval(3 * 3600))
        let earlier = reading(week: 10, weekResetsAt: reset, session: 45, sessionResetsAt: designNow.addingTimeInterval(3 * 3600),
                              at: designNow.addingTimeInterval(-3600))
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .session), reading: r, history: [earlier], now: designNow))
        let f = try #require(Limits.forecast(state, now: designNow, calendar: newYork))
        #expect(near(f.pacePerHour, 25, 0.0001))
        #expect(f.runsOutAt == designNow.addingTimeInterval(2 * 3600))
        #expect(near(f.runsOutEarlyByHours!, 1, 0.0001))
    }

    @Test func noForecastBeforeTheWindowStarts() throws {
        let r = reading(week: 0, weekResetsAt: nil)
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .week), reading: r, history: [], now: designNow))
        #expect(state.past.isEmpty)
        #expect(Limits.forecast(state, now: designNow) == nil)
    }

    @Test func seriesSpansWindowsOldestFirst() {
        let history = [
            reading(week: 30, weekResetsAt: reset, at: designNow),
            reading(week: 90, weekResetsAt: reset.addingTimeInterval(-Pace.window), at: designNow.addingTimeInterval(-90 * 3600)),
            reading(org: "harbor", week: 5, weekResetsAt: reset, at: designNow),
        ]
        let s = Limits.series(LimitID(org: "personal", kind: .week), history: history)
        #expect(s.map(\.value) == [90, 30])
        #expect(s.map(\.resetsAt) == [reset.addingTimeInterval(-Pace.window), reset])
    }

    // H2: one rule for the 5-hour window everywhere: no forecast in its first 30 minutes.
    @Test func sessionForecastWaitsForTheFirstThirtyMinutes() throws {
        let id = LimitID(org: "personal", kind: .session)
        func forecast(minutesIn: Double) -> WeekForecast? {
            let r = reading(week: 10, weekResetsAt: reset, session: 34,
                            sessionResetsAt: designNow.addingTimeInterval(5 * 3600 - minutesIn * 60))
            let state = Limits.state(id, reading: r, history: [], now: designNow)!
            return Limits.forecast(state, now: designNow, calendar: newYork)
        }
        #expect(forecast(minutesIn: 12) == nil)
        #expect(forecast(minutesIn: 29) == nil)
        #expect(forecast(minutesIn: 30) != nil)
        #expect(forecast(minutesIn: 120) != nil)
    }

    @Test func theWeekForecastHasNoSuchWait() throws {
        let r = reading(week: 10, weekResetsAt: reset.addingTimeInterval(-60))
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .week), reading: r, history: [], now: designNow))
        #expect(Limits.forecast(state, now: designNow, calendar: newYork) != nil)
    }
}
