import Foundation
import Testing
@testable import TidemarkCore

/// Each org's 5-hour window and week at a glance: % used, the time tick, the tone and the note.
/// The moment is `designNow`, Tuesday Oct 6 2026 11:32 AM in New York; the week resets
/// Friday Oct 9 at 4 AM (started Friday Oct 2 at 4 AM, so 103.53 of 168 hours have gone).
@Suite struct GlanceSessionTests {
    let friday = local(2026, 10, 9, 4)

    func session(_ used: Double, resets: Date?) -> GlanceLimit {
        Glance.make(reading(week: 40, weekResetsAt: friday, session: used, sessionResetsAt: resets),
                    history: [], now: designNow).session
    }

    @Test func theBarIsFiveHourCellsAndTheFillRunsAcrossThem() {
        let s = session(50, resets: local(2026, 10, 6, 14, 20))
        #expect(s.cells == 5)
        for (i, want) in [1.0, 1, 0.5, 0, 0].enumerated() {
            #expect(near(s.cellFill(i), want, 1e-9), "cell \(i)")
        }
        #expect((0..<5).allSatisfy { session(100, resets: local(2026, 10, 6, 14, 20)).cellFill($0) == 1 })
        #expect(session(0, resets: nil).cellFill(0) == 0)
    }

    @Test func theWeekIsSevenDayCells() {
        let week = Glance.make(reading(week: 50, weekResetsAt: friday, session: 0, sessionResetsAt: nil),
                               history: [], now: designNow).week
        #expect(week.cells == 7)
        #expect(week.cellFill(2) == 1)
        #expect(near(week.cellFill(3), 0.5, 1e-9))
        #expect(week.cellFill(4) == 0)
    }

    @Test func noOpenWindowIsNotStartedAtZero() {
        let s = session(0, resets: nil)
        #expect(s.used == 0)
        #expect(s.elapsed == nil)
        #expect(s.tone == .none)
        #expect(s.note == .notStarted)
    }

    @Test func aWindowThatResetSinceTheReadingIsNotStarted() {
        #expect(session(60, resets: local(2026, 10, 6, 11, 0)).note == .notStarted)
    }

    // Window 9:20 AM to 2:20 PM: 2.2 of 5 hours gone. 18% at 8.2%/h ends near 41%.
    @Test func plentyLeftIsGreenWithTheReset() {
        let s = session(18, resets: local(2026, 10, 6, 14, 20))
        #expect(s.used == 18)
        #expect(s.elapsed.map { near($0, 0.44, 0.001) } == true)
        #expect(s.tone == .green)
        #expect(s.note == .resets(local(2026, 10, 6, 14, 20)))
        #expect(!s.isUrgent)
    }

    // 84% in 2.2 hours is 38.2%/h: the last 16% goes in 25 minutes, at 11:57 AM.
    @Test func fillingBeforeTheResetIsAmberWithWhenItFills() {
        let s = session(84, resets: local(2026, 10, 6, 14, 20))
        #expect(s.tone == .amber)
        guard case .fullAt(let when) = s.note else { Issue.record("expected fullAt, got \(s.note)"); return }
        #expect(abs(when.timeIntervalSince(local(2026, 10, 6, 11, 57))) < 60)
    }

    @Test func fillingFromTheRedThresholdIsRed() {
        let s = session(96, resets: local(2026, 10, 6, 14, 20))
        #expect(s.tone == .red)
        guard case .fullAt = s.note else { Issue.record("expected fullAt, got \(s.note)"); return }
    }

    // Window 6:50 to 11:50 AM: 82% over 4.7 hours ends near 87%, so it won't fill.
    @Test func highButNotFillingIsAmberWithTheReset() {
        let s = session(82, resets: local(2026, 10, 6, 11, 50))
        #expect(s.tone == .amber)
        #expect(s.note == .resets(local(2026, 10, 6, 11, 50)))
    }

    @Test func fullIsRedUntilItComesBack() {
        let s = session(100, resets: local(2026, 10, 6, 14, 20))
        #expect(s.tone == .red)
        #expect(s.note == .backAt(local(2026, 10, 6, 14, 20)))
        #expect(s.isUrgent)
    }

    // Filling before the reset is a forecast, not an emergency: the bar stays.
    @Test func fillingBeforeTheResetIsNotUrgent() {
        let s = session(84, resets: local(2026, 10, 6, 14, 20))
        guard case .fullAt = s.note else { Issue.record("expected fullAt, got \(s.note)"); return }
        #expect(!s.isUrgent)
    }

    // 12% ten minutes into the window would project past 100%, but that's a burst, not a pace.
    @Test func theFirstHalfHourDoesNotForecast() {
        let s = session(12, resets: local(2026, 10, 6, 16, 22))
        #expect(s.tone == .green)
        #expect(s.note == .resets(local(2026, 10, 6, 16, 22)))
    }
}

@Suite struct GlanceWeekTests {
    let friday = local(2026, 10, 9, 4)

    func week(_ used: Double, resets: Date?) -> GlanceLimit {
        Glance.make(reading(week: used, weekResetsAt: resets), history: [], now: designNow).week
    }

    @Test func notStartedIsZero() {
        let w = week(0, resets: nil)
        #expect(w.used == 0)
        #expect(w.tone == .none)
        #expect(w.note == .notStarted)
    }

    // 40% at 0.39%/h ends near 65%.
    @Test func plentyLeftIsGreenAndSaysWhatWouldGoUnused() {
        let w = week(40, resets: friday)
        #expect(w.tone == .green)
        guard case .unused(let unused, friday) = w.note else { Issue.record("expected unused, got \(w.note)"); return }
        #expect(unused > 30)
        #expect(w.elapsed.map { near($0, 103.53 / 168, 0.001) } == true)
    }

    // 63% at 0.61%/h runs out after 60.8 hours, Friday 12:20 AM, 3.7 hours early.
    @Test func runningOutALittleEarlyIsAmber() {
        let w = week(63, resets: friday)
        #expect(w.tone == .amber)
        guard case .runsOut(let when) = w.note else { Issue.record("expected runsOut, got \(w.note)"); return }
        #expect(abs(when.timeIntervalSince(local(2026, 10, 9, 0, 20))) < 120)
        #expect(w.isUrgent)
    }

    // 70% runs out Thursday about 7:54 AM, 20 hours early: still amber (a triangle); only out is red.
    @Test func runningOutWellEarlyIsStillAmber() {
        let w = week(70, resets: friday)
        #expect(w.tone == .amber)
        guard case .runsOut = w.note else { Issue.record("expected runsOut, got \(w.note)"); return }
    }

    // Two hours before the reset, 92% won't run out, but under 10% left is red.
    @Test func littleLeftIsRedAndSaysHowMuch() {
        let soon = local(2026, 10, 6, 13, 32)
        let w = week(92, resets: soon)
        #expect(w.tone == .red)
        #expect(w.note == .nearlyOut(left: 8, resets: soon))
    }

    @Test func fullIsRedUntilItComesBack() {
        let w = week(100, resets: friday)
        #expect(w.tone == .red)
        #expect(w.note == .backAt(friday))
    }
}

@Suite struct GlanceUrgencyTests {
    @Test func mostUrgentPrefersAHotFiveHourWindow() {
        let hot = Glance.make(reading(week: 40, weekResetsAt: local(2026, 10, 9, 4), session: 84,
                                      sessionResetsAt: local(2026, 10, 6, 14, 20)), history: [], now: designNow)
        #expect(hot.mostUrgent.kind == .session)
        let calm = Glance.make(reading(week: 40, weekResetsAt: local(2026, 10, 9, 4), session: 18,
                                       sessionResetsAt: local(2026, 10, 6, 14, 20)), history: [], now: designNow)
        #expect(calm.mostUrgent.kind == .week)
        let weekHot = Glance.make(reading(week: 70, weekResetsAt: local(2026, 10, 9, 4), session: 84,
                                          sessionResetsAt: local(2026, 10, 6, 14, 20)), history: [], now: designNow)
        #expect(weekHot.mostUrgent.kind == .week)
    }

    @Test func tonesOrderByUrgency() {
        #expect(GlanceTone.none < .green)
        #expect(GlanceTone.green < .amber)
        #expect(GlanceTone.amber < .red)
    }
}
