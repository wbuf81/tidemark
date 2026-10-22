import Foundation
import Testing
@testable import TidemarkCore

@Suite struct PaceTests {
    // The spec's worked example: 55% used, 103.4 h elapsed, 64.6 h left, 11:32 AM.
    let reset = designNow.addingTimeInterval(64.6 * 3600)

    @Test func workedExample() throws {
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        #expect(near(f.useItAllPerDay, 16.72))
        #expect(near(f.pacePerDay, 12.77))
        #expect(near(f.unused, 10.64))
        #expect(near(f.byMidnight, 8.68))
        #expect(near(f.elapsedFraction, 103.4 / 168, 0.001))
        #expect(f.runsOutEarlyByHours == nil)
    }

    // S1.1: an old reading kept moving its run-out time later while the app was offline.
    @Test func staleReadingKeepsItsRunOutTime() throws {
        let r = reading(week: 90, weekResetsAt: reset)
        let first = try #require(Pace.forecast(r, history: [], now: designNow, calendar: newYork))
        let later = try #require(Pace.forecast(r, history: [], now: designNow.addingTimeInterval(40 * 60), calendar: newYork))
        #expect(first.runsOutAt != nil)
        #expect(later.runsOutAt == first.runsOutAt)
        #expect(later.runsOutEarlyByHours == first.runsOutEarlyByHours)
        // The same through a limit's state (the 5-hour window and model limits).
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .week), reading: r, history: [], now: designNow))
        let a = try #require(Limits.forecast(state, now: designNow, calendar: newYork))
        let b = try #require(Limits.forecast(state, now: designNow.addingTimeInterval(40 * 60), calendar: newYork))
        #expect(a.runsOutAt == b.runsOutAt)
    }

    @Test func usesTheReadingFrom72HoursAgo() throws {
        let old = reading(week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerHour, 35.0 / 80, 0.0001))
        #expect(near(f.unused, 100 - (55 + 35.0 / 80 * 64.6)))
    }

    @Test func ignoresReadingsFromAnotherWindow() throws {
        let old = reading(week: 20, weekResetsAt: reset.addingTimeInterval(-Pace.window), at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func ignoresOtherOrgs() throws {
        let old = reading(org: "harbor", week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func runsOutEarly() throws {
        let f = try #require(Pace.forecast(reading(week: 90, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        let pace = 90 / 103.4
        #expect(near(f.runsOutEarlyByHours!, 64.6 - 10 / pace))
        #expect(f.unused == 0)
        #expect(f.forecastAtReset == 100)
        #expect(near(f.runsOutAt!.timeIntervalSince(designNow) / 3600, 10 / pace))
    }

    // An hour into a new week, 2% used: that first hour's pace says nothing about the week yet.
    @Test func aNewWeekSettlesBeforeItForecastsARunOut() throws {
        let fresh = designNow.addingTimeInterval(167 * 3600)
        let f = try #require(Pace.forecast(reading(week: 2, weekResetsAt: fresh), history: [], now: designNow, calendar: newYork))
        #expect(f.settling)
        #expect(f.runsOutAt == nil)
        #expect(f.runsOutEarlyByHours == nil)
        #expect(PlanStates.state(reading(week: 2, weekResetsAt: fresh), f) == .fine)
    }

    @Test func aHeavyStartStillWarnsAndTwelveHoursEndsTheSettling() throws {
        let sixHoursIn = designNow.addingTimeInterval(162 * 3600)
        let heavy = try #require(Pace.forecast(reading(week: 60, weekResetsAt: sixHoursIn), history: [], now: designNow, calendar: newYork))
        #expect(!heavy.settling)
        #expect(heavy.runsOutAt != nil)
        let thirteenHoursIn = designNow.addingTimeInterval(155 * 3600)
        let later = try #require(Pace.forecast(reading(week: 10, weekResetsAt: thirteenHoursIn), history: [], now: designNow, calendar: newYork))
        #expect(!later.settling)
        #expect(later.runsOutAt != nil)
    }

    // The 5-hour window is short enough to forecast from the start.
    @Test func fiveHourWindowsDoNotSettle() throws {
        let r = reading(week: 10, weekResetsAt: reset, session: 40, sessionResetsAt: designNow.addingTimeInterval(4.5 * 3600))
        let state = try #require(Limits.state(LimitID(org: "personal", kind: .session), reading: r, history: [], now: designNow))
        let f = try #require(Limits.forecast(state, now: designNow, calendar: newYork))
        #expect(!f.settling)
        #expect(f.runsOutAt != nil)
    }

    // Review Focus 3
    @Test func zeroPaceMeansEverythingLeftGoesUnused() throws {
        let old = reading(week: 55, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(f.pacePerHour == 0)
        #expect(f.unused == 45)
        #expect(f.runsOutEarlyByHours == nil)
    }

    // Review Focus 1
    @Test func noForecastBeforeTheWeekStartsOrAfterItEnds() {
        #expect(Pace.forecast(reading(week: 0, weekResetsAt: nil), history: [], now: designNow, calendar: newYork) == nil)
        #expect(Pace.forecast(reading(week: 50, weekResetsAt: designNow.addingTimeInterval(-60)), history: [], now: designNow, calendar: newYork) == nil)
    }

    @Test func byMidnightIsCappedAtReset() throws {
        let soon = local(2026, 10, 6, 16, 0)
        let f = try #require(Pace.forecast(reading(week: 70, weekResetsAt: soon), history: [], now: designNow, calendar: newYork))
        #expect(near(f.byMidnight, 30))
    }
}
