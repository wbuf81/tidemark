import Foundation
import Testing
@testable import TidemarkCore

@Suite struct CopyTests {
    let primary = reading(week: 55, weekResetsAt: local(2026, 10, 9, 4), session: 1,
                          sessionResetsAt: local(2026, 10, 6, 16, 20))
    let overflow = reading(org: "harbor", week: 95, weekResetsAt: local(2026, 10, 7, 21))

    func forecast(_ r: Reading) -> WeekForecast? { Pace.forecast(r, history: [], now: designNow, calendar: newYork) }

    @Test func todayForTheDesignDayPrimary() {
        let today = Copy.today(primary, forecast: forecast(primary), now: designNow, formatting: fmt)
        #expect(today.main == "Use about 9% more by midnight (to ~64% used), then about 17% a day.")
        #expect(today.warning == "At your current ~13% a day, about 11% goes unused by Fri 4 AM.")
        // D6: "would go unused" is words in a neutral ink; only a run-out warns in amber.
        #expect(today.warningRunsOut == false)
    }

    @Test func todayForANearlyOutOrg() {
        let today = Copy.today(overflow, forecast: forecast(overflow), now: designNow, formatting: fmt)
        #expect(today.main == "Only 5% left until Wed 9 PM, about 7 hours at your recent pace.")
        #expect(today.warning == nil)
    }

    @Test func todayWhenResetComesBeforeMidnight() {
        let r = reading(week: 70, weekResetsAt: local(2026, 10, 6, 16))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Use the last 30% before 4 PM.")
        #expect(today.warning == "At your current ~10% a day, about 28% goes unused by 4 PM.")
    }

    @Test func todayWhenRunningOutEarly() {
        let r = reading(week: 80, weekResetsAt: local(2026, 10, 9, 4))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Ease off to about 7% a day to last until Fri 4 AM.")
        #expect(today.warning?.hasPrefix("At your current ~19% a day it runs out ") == true)
        #expect(today.warningRunsOut)
        // One formatter for every run-out gap (M5): "2 d 7 h", the same as the headline and the stats.
        let early = Pace.forecast(r, history: [], now: designNow, calendar: newYork)!.runsOutEarlyByHours!
        #expect(today.warning?.hasSuffix(", \(Formatting.duration(early * 3600)) early.") == true)
    }

    // Review Focus 1
    @Test func todayBeforeTheWeekStarts() {
        let r = reading(week: 0, weekResetsAt: nil)
        #expect(Copy.today(r, forecast: nil, now: designNow, formatting: fmt).main
                == "This week hasn’t started. Nothing is used yet.")
    }
}

/// The widget's notes beside each bar.
@Suite struct GlanceNoteTests {
    func limit(_ kind: LimitKind, _ note: GlanceNote) -> GlanceLimit {
        GlanceLimit(kind: kind, used: 50, elapsed: 0.5, tone: .green, note: note)
    }

    @Test func fiveHourNotesUseTheShortClock() {
        #expect(Copy.glanceNote(limit(.session, .resets(local(2026, 10, 6, 14, 20))), now: designNow, formatting: fmt, capitalized: false) == "↺ 2:20pm")
        #expect(Copy.glanceNote(limit(.session, .fullAt(local(2026, 10, 6, 11, 57))), now: designNow, formatting: fmt, capitalized: false) == "full 11:57am")
        #expect(Copy.glanceNote(limit(.session, .backAt(local(2026, 10, 6, 15, 0))), now: designNow, formatting: fmt, capitalized: true) == "back 3pm")
        #expect(Copy.glanceNote(limit(.session, .notStarted), now: designNow, formatting: fmt, capitalized: false) == "not started")
    }

    @Test func weekNotesUseTheDay() {
        let friday = local(2026, 10, 9, 4)
        #expect(Copy.glanceNote(limit(.week, .resets(friday)), now: designNow, formatting: fmt, capitalized: false) == "↺ fri")
        #expect(Copy.glanceNote(limit(.week, .resets(friday)), now: designNow, formatting: fmt, capitalized: true) == "↺ Fri")
        #expect(Copy.glanceNote(limit(.week, .backAt(friday)), now: designNow, formatting: fmt, capitalized: false) == "back fri")
        #expect(Copy.glanceNote(limit(.week, .runsOut(local(2026, 10, 8, 7, 54))), now: designNow, formatting: fmt, capitalized: false) == "out thu")
        #expect(Copy.glanceNote(limit(.week, .runsOut(local(2026, 10, 6, 21, 0))), now: designNow, formatting: fmt, capitalized: false) == "out 9pm")
    }

    @Test func twentyFourHourClock() {
        let f24 = Formatting(calendar: newYork, twentyFourHour: true)
        #expect(Copy.glanceNote(limit(.session, .resets(local(2026, 10, 6, 14, 20))), now: designNow, formatting: f24, capitalized: false) == "↺ 14:20")
    }
}
