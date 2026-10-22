import Foundation
import Testing
@testable import TidemarkCore

let personal = Org(id: "personal", name: "Personal", billingType: "team")
let harbor = Org(id: "harbor", name: "Harbor Labs", billingType: "team")
let friday4am = local(2026, 10, 9, 4, 0)
let wednesday9pm = local(2026, 10, 7, 21, 0)
let monday9am = local(2026, 10, 12, 9, 0)

func status(_ org: Org, _ role: Role, week: Double, reset: Date?, session: Double = 0,
            sessionReset: Date? = nil) -> OrgStatus {
    let r = reading(org: org.id, week: week, weekResetsAt: reset, session: session, sessionResetsAt: sessionReset)
    let f = Pace.forecast(r, history: [], now: designNow, calendar: newYork)
    return OrgStatus(org: org, role: role, reading: r, state: PlanStates.state(r, f))
}

func advise(_ orgs: [OrgStatus], cc: String? = "personal") -> Advice? {
    SwitchAdvisor.advice(orgs, claudeCodeOrg: cc, now: designNow, formatting: fmt, Thresholds())
}

@Suite struct SwitchAdvisorTests {
    // The design-day numbers: the overflow org has only 5% left, so stay put.
    let today = [
        status(personal, .primary, week: 55, reset: friday4am, session: 1, sessionReset: designNow.addingTimeInterval(4.8 * 3600)),
        status(harbor, .overflow, week: 95, reset: wednesday9pm),
    ]

    @Test func overflowAtFivePercentMeansNoAdvice() {
        #expect(advise(today) == nil)
        #expect(SwitchAdvisor.statusLine(today, claudeCodeOrg: "personal", advice: nil, now: designNow, formatting: fmt, Thresholds())
                == "Claude Code is on Personal, the right place right now.")
    }

    // An org that stopped reading keeps its last reading; once its 5-hour window has passed
    // it looks empty, but that's not a reason to move there.
    @Test func aStaleOrgIsNeverAdvised() {
        let busy = status(personal, .primary, week: 60, reset: friday4am, session: 85,
                          sessionReset: designNow.addingTimeInterval(1.5 * 3600))
        var stale = status(harbor, .overflow, week: 60, reset: monday9am)
        stale.reading.time = designNow.addingTimeInterval(-20 * 60)
        #expect(advise([busy, stale]) == nil)
        stale.reading.time = designNow.addingTimeInterval(-5 * 60)
        #expect(advise([busy, stale])?.target == harbor)
    }

    // With one org there's nothing to switch between, so no line about switching.
    @Test func oneOrgNeedsNoStatusLine() {
        let one = [status(personal, .primary, week: 95, reset: friday4am)]
        #expect(SwitchAdvisor.statusLine(one, claudeCodeOrg: "personal", advice: nil, now: designNow, formatting: fmt, Thresholds()) == "")
    }

    @Test func claudeCodeOnAHiddenOrgIsExplained() {
        let lighthouse = Org(id: "lighthouse", name: "Lighthouse Co")
        #expect(SwitchAdvisor.statusLine(today, claudeCodeOrg: "lighthouse", advice: nil, now: designNow, formatting: fmt, Thresholds(),
                                         hidden: [lighthouse])
                == "Claude Code is on Lighthouse Co, which isn’t shown here. Turn it on in Settings to follow it.")
    }

    @Test func busyPrimarySessionMovesToOverflow() {
        let orgs = [
            status(personal, .primary, week: 60, reset: friday4am, session: 85, sessionReset: designNow.addingTimeInterval(1.5 * 3600)),
            status(harbor, .overflow, week: 60, reset: monday9am),
        ]
        let advice = advise(orgs)
        #expect(advice?.target == harbor)
        #expect(advice?.reason == "Personal 5h at 85%, desktop app needs room")
        #expect(SwitchAdvisor.statusLine(orgs, claudeCodeOrg: "personal", advice: advice, now: designNow, formatting: fmt, Thresholds())
                == "Move Claude Code to Harbor Labs: Personal 5h at 85%, desktop app needs room.")
    }

    @Test func useWhatExpiresFirst() {
        let orgs = [
            status(personal, .primary, week: 30, reset: friday4am, session: 10, sessionReset: designNow.addingTimeInterval(3 * 3600)),
            status(harbor, .overflow, week: 70, reset: wednesday9pm),
        ]
        #expect(advise(orgs) == Advice(target: harbor, reason: "Harbor Labs has 30% expiring Wed 9 PM"))
    }

    @Test func primaryKeepsABufferForTheDesktopApp() {
        let orgs = [
            status(personal, .primary, week: 86, reset: friday4am),
            status(harbor, .overflow, week: 50, reset: monday9am),
        ]
        #expect(advise(orgs) == Advice(target: harbor, reason: "Personal is down to 14%, keep it for the desktop app"))
    }

    @Test func bothLowSaysWhichComesBackFirst() {
        let orgs = [
            status(personal, .primary, week: 92, reset: friday4am),
            status(harbor, .overflow, week: 96, reset: wednesday9pm),
        ]
        #expect(advise(orgs) == nil)
        #expect(SwitchAdvisor.statusLine(orgs, claudeCodeOrg: "personal", advice: nil, now: designNow, formatting: fmt, Thresholds())
                == "Both orgs are low. Harbor Labs is back first, Wed 9 PM.")
    }

    @Test func unknownClaudeCodeOrgMeansNoAdvice() {
        let orgs = [
            status(personal, .primary, week: 60, reset: friday4am, session: 85, sessionReset: designNow.addingTimeInterval(3600)),
            status(harbor, .overflow, week: 10, reset: monday9am),
        ]
        #expect(advise(orgs, cc: nil) == nil)
        #expect(advise(orgs, cc: "someone-else") == nil)
    }

    @Test func tiesGoToOverflow() {
        let orgs = [
            status(personal, .primary, week: 10, reset: friday4am),
            status(harbor, .overflow, week: 10, reset: friday4am),
        ]
        #expect(SwitchAdvisor.best(orgs, now: designNow, Thresholds())?.org == harbor)
    }
}

@Suite struct AdviceGateTests {
    let toHarbor = Advice(target: harbor, reason: "x")
    let toPersonal = Advice(target: personal, reason: "y")

    @Test func needsTwoReadingsInARow() {
        var gate = AdviceGate()
        #expect(gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == nil)
        #expect(gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == toHarbor)
        #expect(gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == toHarbor)
    }

    @Test func flipFloppingNeverShows() {
        var gate = AdviceGate()
        for advice in [toHarbor, toPersonal, toHarbor, toPersonal] {
            #expect(gate.update(advice, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == nil)
        }
    }

    @Test func noAdviceClearsIt() {
        var gate = AdviceGate()
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        #expect(gate.update(nil, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == nil)
        #expect(gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow) == nil)
    }

    @Test func holdsSwitchingBackForAnHour() {
        var gate = AdviceGate()
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        // The owner moved to Harbor Labs; ten minutes later the advice flips back.
        let later = designNow.addingTimeInterval(600)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: false, now: later) == nil)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: false, now: later) == nil)
        // After the hour it's allowed (still needing two readings).
        let afterHour = designNow.addingTimeInterval(3700)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: false, now: afterHour) == nil)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: false, now: afterHour) == toPersonal)
    }

    @Test func redOverridesTheHold() {
        var gate = AdviceGate()
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        _ = gate.update(toHarbor, claudeCodeOrg: "personal", currentIsRed: false, now: designNow)
        let later = designNow.addingTimeInterval(600)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: true, now: later) == nil)
        #expect(gate.update(toPersonal, claudeCodeOrg: "harbor", currentIsRed: true, now: later) == toPersonal)
    }
}
