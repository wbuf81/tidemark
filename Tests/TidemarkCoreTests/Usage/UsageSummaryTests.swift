import Foundation
import Testing
@testable import TidemarkCore

@Suite struct UsageSummaryTests {
    let personal = Org(id: "personal", name: "Personal")
    let harbor = Org(id: "harbor", name: "Harbor Labs")
    let fri23 = local(2026, 10, 23, 4)
    let sat17 = local(2026, 10, 17, 14)
    let mon19 = local(2026, 10, 19, 9)

    /// A reading taken right now (the shared helper's default is the design's moment, over a week earlier).
    func fresh(org: String, week: Double, weekResetsAt: Date?, session: Double = 0, sessionResetsAt: Date? = nil,
               at time: Date = forecastNow, scoped: [String: Double] = [:]) -> Reading {
        reading(org: org, week: week, weekResetsAt: weekResetsAt, session: session, sessionResetsAt: sessionResetsAt,
                at: time, scoped: scoped)
    }

    /// Readings every day of this week for `org`, rising to `week` now.
    func history(_ org: String, to week: Double, reset: Date) -> [Reading] {
        (1...3).map { back in
            fresh(org: org, week: week * (1 - Double(back) * 0.2), weekResetsAt: reset,
                    at: forecastNow.addingTimeInterval(-Double(back) * 26 * 3600))
        }.reversed()
    }

    func input(orgs: [Org]? = nil, latest: [Reading], history: [Reading] = [], states: [String: PlanState] = [:],
               claudeCode: String? = "personal", advice: Org? = nil, signedIn: Bool = true, limitsOff: Bool = false,
               orgProblems: [String: RefreshProblem] = [:], showModel: Bool = true, showSession: Bool = true) -> UsageInput {
        UsageInput(orgs: orgs ?? [personal, harbor], latest: Dictionary(uniqueKeysWithValues: latest.map { ($0.org, $0) }),
                   history: history, states: states, claudeCodeOrg: claude(claudeCode), adviceTarget: advice, signedIn: signedIn,
                   limitsOff: limitsOff, orgProblems: orgProblems, showModelLimits: showModel, showSessionLimits: showSession,
                   now: forecastNow, formatting: fmt, calendar: newYork)
    }

    private func claude(_ id: String?) -> String? { id }

    var twoPlans: [Reading] {
        [fresh(org: "personal", week: 58, weekResetsAt: fri23, session: 34, sessionResetsAt: local(2026, 10, 16, 16, 20), scoped: ["Fable": 12]),
         fresh(org: "harbor", week: 81, weekResetsAt: mon19, scoped: ["Fable": 3])]
    }

    @Test func tilesForTwoPlans() {
        let h = history("personal", to: 58, reset: fri23) + history("harbor", to: 81, reset: mon19)
        let s = UsageSummary.make(input(latest: twoPlans, history: h, states: ["personal": .fine, "harbor": .runsOutEarly]))
        #expect(s.mode == .ready)
        #expect(s.tiles.map(\.label) == ["Personal · week", "Harbor Labs · week", "Personal · 5 hours", "Claude Code is on"])
        #expect(s.tiles.map(\.value) == ["58%", "81%", "34%", "Personal"])
        #expect(s.tiles[2].caption == "resets 4:20 PM")
        #expect(s.tiles[3].caption == "")
        #expect(s.tiles[0].state == .fine && s.tiles[1].state == .runsOutEarly)
        #expect(s.plans.map(\.name) == ["Personal", "Harbor Labs"])
        #expect(s.plans.map(\.state) == [.fine, .runsOutEarly])
        #expect(s.plans.allSatisfy { $0.days.count == 7 })
    }

    @Test func adviceSaysHowInTheBrief() {
        let s = UsageSummary.make(input(latest: twoPlans, states: ["personal": .fine, "harbor": .runsOutEarly],
                                        claudeCode: "harbor", advice: personal))
        #expect(s.switchHow == "Move Claude Code to Personal: run /login in Claude Code and pick Personal.")
        #expect(s.lede.hasSuffix(" " + s.switchHow!))
        #expect(s.tiles.last?.caption == "switch suggested")
        #expect(s.tiles.last?.value == "Harbor Labs")
        #expect(s.tiles[2].label == "Harbor Labs · 5 hours")
    }

    @Test func onePlanHasNothingToSwitchTo() {
        let s = UsageSummary.make(input(orgs: [personal], latest: [twoPlans[0]], states: ["personal": .fine]))
        #expect(s.tiles.map(\.label) == ["Personal · week", "Personal · 5 hours", "Claude Code is on"])
        #expect(s.tiles.last?.caption == "")
        #expect(s.switchHow == nil)
    }

    @Test func threePlansGetThreeWeekTiles() {
        let third = Org(id: "lighthouse", name: "Lighthouse Co")
        let s = UsageSummary.make(input(orgs: [personal, harbor, third],
                                        latest: twoPlans + [fresh(org: "lighthouse", week: 30, weekResetsAt: fri23)]))
        #expect(s.tiles.filter { $0.id.hasPrefix("week-") }.count == 3)
        #expect(s.plans.count == 3)
    }

    @Test func outPlanSaysOutNow() {
        let out = fresh(org: "harbor", week: 100, weekResetsAt: mon19)
        let s = UsageSummary.make(input(latest: [twoPlans[0], out], states: ["personal": .fine, "harbor": .out]))
        let plan = s.plans[1]
        #expect(plan.state == .out)
        #expect(plan.end == "out now")
        #expect(plan.days.last?.value == 100)
        #expect(s.tiles[1].caption == "out until Mon 9 AM")
    }

    @Test func runningOutSaysWhichDay() {
        let h = [fresh(org: "harbor", week: 40, weekResetsAt: mon19, at: forecastNow.addingTimeInterval(-80 * 3600))]
        let s = UsageSummary.make(input(latest: [twoPlans[0], fresh(org: "harbor", week: 88, weekResetsAt: mon19)], history: h,
                                        states: ["harbor": .runsOutEarly]))
        #expect(s.plans[1].end.hasPrefix("out "))
        #expect(s.plans[1].end != "out now")
        #expect(s.tiles[1].caption.hasPrefix("runs out "))
        #expect(s.tiles[1].caption.hasSuffix(", resets Mon 9 AM"))
    }

    @Test func fineSaysItsForecast() {
        let h = history("personal", to: 30, reset: fri23)
        let calm = fresh(org: "personal", week: 30, weekResetsAt: fri23)
        let s = UsageSummary.make(input(latest: [calm], history: h, states: ["personal": .fine]))
        #expect(s.plans[0].end.hasPrefix("~"))
        #expect(s.plans[0].end.hasSuffix("%"))
    }

    @Test func stalePlanKeepsItsBarsAndSaysAsOf() {
        let old = fresh(org: "personal", week: 58, weekResetsAt: fri23, at: forecastNow.addingTimeInterval(-40 * 60))
        let s = UsageSummary.make(input(orgs: [personal], latest: [old], states: ["personal": .fine]))
        let plan = s.plans[0]
        #expect(plan.stale)
        #expect(plan.end == "as of 2 PM")
        #expect(plan.days.count == 7)
        #expect(s.tiles[0].caption.hasPrefix("as of 2 PM"))
    }

    @Test func unreadPlanSaysWhy() {
        let s = UsageSummary.make(input(latest: [twoPlans[0]], states: ["personal": .fine], orgProblems: ["harbor": .refused]))
        let plan = s.plans[1]
        #expect(plan.state == nil)
        #expect(plan.days.isEmpty)
        #expect(plan.end == "Couldn’t read: access refused · trying again")
        #expect(plan.voiceOver.hasPrefix("Harbor Labs: couldn’t read"))
    }

    @Test func noHistoryIsOnlyTodaysBar() {
        let s = UsageSummary.make(input(orgs: [personal], latest: [twoPlans[0]], states: ["personal": .fine]))
        let days = s.plans[0].days
        #expect(days.filter { $0.value != nil }.count >= 1)
        #expect(days.filter { $0.value != nil && !$0.isForecast }.count == 1)
    }

    @Test func signedOutAndLimitsOffAreModes() {
        #expect(UsageSummary.make(input(latest: twoPlans, signedIn: false)).mode == .signedOut)
        #expect(UsageSummary.make(input(latest: twoPlans, limitsOff: true)).mode == .limitsOff)
        // Plan limits off wins over signed out: it's the setting the user can change.
        #expect(UsageSummary.make(input(latest: [], signedIn: false, limitsOff: true)).mode == .limitsOff)
    }

    @Test func modelLimitsAreNamedFromTheReadings() {
        let s = UsageSummary.make(input(latest: twoPlans))
        #expect(s.modelNames == ["Fable"])
        #expect(s.modelToggle == "Show model limits (Fable)")
        #expect(s.limits.contains { $0.id.kind == .model("Fable") })
        let hidden = UsageSummary.make(input(latest: twoPlans, showModel: false, showSession: false))
        #expect(hidden.limits.allSatisfy { $0.id.kind == .week })
        // The names stay, so the toggle can still say what it turns on.
        #expect(hidden.modelNames == ["Fable"])
    }

    @Test func noReadingsYetHasAHeadlineAndNoTiles() {
        let s = UsageSummary.make(input(latest: []))
        #expect(s.headline.title == "No readings yet" || s.headline.title == "No fresh readings")
        #expect(s.tiles.filter { $0.id.hasPrefix("week-") }.allSatisfy { $0.value == "—" })
    }
}
