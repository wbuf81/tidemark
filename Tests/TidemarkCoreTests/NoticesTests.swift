import Foundation
import Testing
@testable import TidemarkCore

@Suite struct NoticesTests {
    @Test func signedOut() {
        #expect(Copy.signedOutNotice == Notice(title: "Tidemark was signed out",
                                               body: "claude.ai ended the session. Click to sign in again."))
    }

    @Test func switchAdviceNamesTheTargetTheReasonAndHow() {
        let advice = Advice(target: harbor, reason: "Personal 5h at 85%, desktop app needs room")
        #expect(Copy.switchNotice(advice) == Notice(title: "Move Claude Code to Harbor Labs",
                                                    body: "Personal 5h at 85%, desktop app needs room. Run /login in Claude Code and pick Harbor Labs.",
                                                    plan: "Harbor Labs"))
    }

    // L17: the advice notice is posted once per target and week window, so a relaunch doesn't repeat it.
    @Test func adviceIsNoticedOncePerTargetAndWindow() {
        let advice = Advice(target: harbor, reason: "Personal is down to 14%")
        var log = NoticeLog()
        let reset = local(2026, 10, 9, 4)
        #expect(Notices.adviceDue(advice, claudeCodeOrg: "personal", weekResetsAt: reset, log: &log) == Copy.switchNotice(advice))
        // A relaunch: the log was saved with the settings, the same advice comes back, nothing is posted.
        var relaunched = try! JSONDecoder().decode(NoticeLog.self, from: JSONEncoder().encode(log))
        #expect(Notices.adviceDue(advice, claudeCodeOrg: "personal", weekResetsAt: reset, log: &relaunched) == nil)
        // Another target, or a new week, is news again.
        let other = Advice(target: personal, reason: "Harbor Labs is out")
        #expect(Notices.adviceDue(other, claudeCodeOrg: "harbor", weekResetsAt: reset, log: &log) != nil)
        #expect(Notices.adviceDue(advice, claudeCodeOrg: "personal", weekResetsAt: reset.addingTimeInterval(7 * 86400), log: &log) != nil)
    }

    // S4.5: "nearly out" says why.
    @Test func outNoticeSaysWhy() {
        let wed = local(2026, 10, 7, 11, 32)   // Monday is 5 days on; from Tuesday it would carry its date
        let nearly = Copy.nearlyOutNotice(harbor, left: 6, resets: monday9am, now: wed, formatting: fmt)
        #expect(nearly.title == "Harbor Labs is nearly out")
        #expect(nearly.body == "6% of its week left, back Mon 9 AM")
        #expect(nearly.plan == "Harbor Labs")
        let out = Copy.nearlyOutNotice(harbor, left: 0, resets: monday9am, now: wed, formatting: fmt)
        #expect(out == Notice(title: "Harbor Labs is out", body: "Back Mon 9 AM.", plan: "Harbor Labs"))
        let runs = Copy.runsOutNotice(harbor, at: local(2026, 10, 10, 14), early: 50 * 3600, now: designNow, formatting: fmt)
        #expect(runs.title == "Harbor Labs runs out Sat 2 PM")
        #expect(runs.body == "About 2 days before it resets.")
        let session = Copy.sessionNotice(harbor, used: 96, resets: local(2026, 10, 6, 16, 20), now: designNow, formatting: fmt)
        #expect(session.title == "Harbor Labs’s 5-hour window is at 96%")
        #expect(session.body == "Back at 4:20 PM.")
    }

    @Test func roughGaps() {
        #expect(Copy.roughly(30 * 60) == "30 minutes")
        #expect(Copy.roughly(3600) == "1 hour")
        #expect(Copy.roughly(14 * 3600) == "14 hours")
        #expect(Copy.roughly(36 * 3600) == "2 days")
    }

    @Test func weekAlertsFollowTheRedThresholds() {
        let reset = local(2026, 10, 9, 4)
        func alert(_ week: Double) -> Notices.WeekAlert? {
            let r = reading(week: week, weekResetsAt: reset)
            return Notices.weekAlert(r, Pace.forecast(r, history: [], now: designNow, calendar: newYork))
        }
        #expect(alert(94) == .nearlyOut)
        #expect(alert(70) == .runsOut)      // 20 hours early
        #expect(alert(63) == nil)           // 3.7 hours early: amber, but no notification
        #expect(alert(40) == nil)
        #expect(Notices.sessionNearlyFull(reading(week: 10, weekResetsAt: reset, session: 96, sessionResetsAt: reset)))
        #expect(!Notices.sessionNearlyFull(reading(week: 10, weekResetsAt: reset, session: 90, sessionResetsAt: reset)))
    }

    // B23: the plan Claude Code is on is read, and so warned about, even when its widget card is hidden.
    @Test func hiddenPlanStillWarns() {
        let lighthouse = Org(id: "lighthouse", name: "Lighthouse Co", billingType: "team")
        #expect(Notices.toRead(shown: [personal], known: [personal, harbor, lighthouse], claudeCodeOrg: "harbor") == [personal, harbor])
        #expect(Notices.toRead(shown: [personal, harbor], known: [personal, harbor, lighthouse], claudeCodeOrg: "harbor") == [personal, harbor])
        #expect(Notices.toRead(shown: [personal], known: [personal, harbor], claudeCodeOrg: nil) == [personal])
        #expect(Notices.toRead(shown: [personal], known: [personal], claudeCodeOrg: "elsewhere") == [personal])
    }

    @Test func aNoticeHasNoPlanUnlessGivenOne() {
        #expect(Copy.signedOutNotice.plan == nil)
        #expect(Notice(title: "t", body: "b", plan: "Personal").plan == "Personal")
    }

    // H5 / M2: a hidden Claude Code plan's reading raises the notice, once per week window.
    @Test func aHiddenPlansReadingRaisesTheOutNoticeOnce() {
        let reset = local(2026, 10, 9, 4)
        let latest = ["harbor": reading(org: "harbor", week: 95, weekResetsAt: reset)]
        var log = NoticeLog()
        func due() -> Notices.Due {
            Notices.due(claudeCodeOrg: "harbor", orgs: [personal, harbor], latest: latest, history: [],
                        now: designNow, formatting: fmt, log: &log)
        }
        let first = due()
        #expect(first.week?.title == "Harbor Labs is nearly out")
        #expect(first.sessionFull == nil)
        // The same alert in the same week window doesn't post again (a relaunch, the rule wobbling).
        #expect(due().week == nil)
        // A new week window is a new notice.
        let next = ["harbor": reading(org: "harbor", week: 96, weekResetsAt: reset.addingTimeInterval(Pace.window))]
        var later = log
        #expect(Notices.due(claudeCodeOrg: "harbor", orgs: [personal, harbor], latest: next, history: [],
                            now: designNow, formatting: fmt, log: &later).week != nil)
    }

    @Test func theLogSurvivesBeingSaved() throws {
        var log = NoticeLog()
        let first = log.firstTime("a")
        var copy = try JSONDecoder().decode(NoticeLog.self, from: JSONEncoder().encode(log))
        let again = copy.firstTime("a"), other = copy.firstTime("b")
        #expect(first && !again && other)
    }

    @Test func theLogKeepsOnlyTheNewest() {
        var log = NoticeLog()
        for i in 0..<100 { _ = log.firstTime("k\(i)") }
        let oldest = log.firstTime("k0"), newest = log.firstTime("k99")
        #expect(oldest && !newest)
    }

    @Test func nothingDueWithoutAReadingOrAPlan() {
        var log = NoticeLog()
        #expect(Notices.due(claudeCodeOrg: nil, orgs: [personal], latest: [:], history: [], now: designNow, formatting: fmt, log: &log).week == nil)
        #expect(Notices.due(claudeCodeOrg: "harbor", orgs: [personal], latest: ["harbor": reading(org: "harbor", week: 99, weekResetsAt: local(2026, 10, 9, 4))],
                            history: [], now: designNow, formatting: fmt, log: &log).week == nil)
    }

    @Test func theFiveHourWindowNoticeIsOncePerWindow() {
        let r = reading(org: "harbor", week: 10, weekResetsAt: local(2026, 10, 9, 4), session: 96,
                        sessionResetsAt: local(2026, 10, 6, 16, 20))
        var log = NoticeLog()
        func due() -> Notices.Due {
            Notices.due(claudeCodeOrg: "harbor", orgs: [harbor], latest: ["harbor": r], history: [], now: designNow, formatting: fmt, log: &log)
        }
        #expect(due().sessionFull?.title == "Harbor Labs’s 5-hour window is at 96%")
        #expect(due().sessionFull == nil)
    }
}
