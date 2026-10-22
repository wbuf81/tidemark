import Testing
import Foundation
@testable import TidemarkCore

@Suite struct UsageHeadlineSuite {
    static let now = local(2026, 10, 7, 11, 32)   // Wednesday morning

    static func plan(_ name: String, _ r: Reading, history: [Reading] = []) -> UsageHeadline.Plan {
        let f = Pace.forecast(r, history: history, now: now)
        return UsageHeadline.Plan(name: name, reading: r, forecast: f, state: PlanStates.state(r, f))
    }

    /// Fine, about 20% to spare at Fri 4 AM.
    static var personal: UsageHeadline.Plan {
        plan("Personal", reading(week: 60.7, weekResetsAt: local(2026, 10, 9, 4), at: now))
    }

    /// Runs out Thursday at about 9:36 PM; back Sunday 9 AM.
    static var harborEarly: UsageHeadline.Plan {
        let reset = local(2026, 10, 11, 9)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: reset, at: local(2026, 10, 4, 10))]
        return plan("Harbor Labs", reading(org: "harbor", week: 81, weekResetsAt: reset, at: now), history: history)
    }

    static func headline(_ plans: [UsageHeadline.Plan], now: Date = now) -> UsageHeadline? {
        UsageHeadline.make(plans, now: now, formatting: fmt, calendar: newYork)
    }

    @Test func runsOutEarlyNamesThePlanAndWhoCovers() throws {
        let h = try #require(Self.headline([Self.personal, Self.harborEarly]))
        #expect(Self.harborEarly.state == .runsOutEarly)
        #expect(h.title == "Harbor Labs runs out tomorrow night")
        #expect(h.detail == "Empty Thu 9:36 PM, if the pace holds. Personal covers until Harbor Labs is back Sun 9 AM.")
    }

    @Test func nobodyCoversWhenNoOtherPlanIsFine() throws {
        let h = try #require(Self.headline([Self.harborEarly]))
        #expect(h.title == "Harbor Labs runs out tomorrow night")
        #expect(h.detail == "Empty Thu 9:36 PM, if the pace holds.")
    }

    @Test func outSaysWhenItIsBack() throws {
        let out = Self.plan("Harbor Labs", reading(org: "harbor", week: 100, weekResetsAt: local(2026, 10, 7, 21), at: Self.now))
        let h = try #require(Self.headline([Self.personal, out]))
        #expect(h.title == "Harbor Labs is out until tonight")
        #expect(h.detail == "Back 9 PM. Personal covers.")
        let alone = try #require(Self.headline([out]))
        #expect(alone.detail == "Back 9 PM.")
    }

    @Test func outComesBeforeRunsOutEarly() throws {
        let out = Self.plan("Work", reading(org: "work", week: 100, weekResetsAt: local(2026, 10, 11, 9), at: Self.now))
        let h = try #require(Self.headline([Self.harborEarly, out]))
        #expect(h.title == "Work is out until Sunday morning")
        #expect(h.detail == "Back Sun 9 AM.")
    }

    @Test func allFineSaysHowMuchSpareAtTheFirstReset() throws {
        let h = try #require(Self.headline([Self.personal]))
        #expect(h.title == "Personal lasts the week")
        #expect(h.detail == "About 20% to spare at Fri 4 AM.")
        let other = Self.plan("Work", reading(org: "work", week: 45, weekResetsAt: local(2026, 10, 10, 9), at: Self.now))
        let both = try #require(Self.headline([other, Self.personal]))
        #expect(both.title == "Every plan lasts the week")
        #expect(both.detail == "About 20% to spare at Fri 4 AM.")   // the plan with the least to spare
    }

    @Test func aPlanThatJustResetIsNotTheOneWithTheLeastToSpare() throws {
        let fresh = Self.plan("Lighthouse", reading(org: "lighthouse", week: 2, weekResetsAt: Self.now.addingTimeInterval(167 * 3600), at: Self.now))
        let both = try #require(Self.headline([fresh, Self.personal]))
        #expect(both.title == "Every plan lasts the week")
        #expect(both.detail == "About 20% to spare at Fri 4 AM.")
        let alone = try #require(Self.headline([fresh]))
        #expect(alone.title == "Lighthouse lasts the week")
        #expect(alone.detail == "A new week just started.")
    }

    @Test func nilWithNoPlans() {
        #expect(Self.headline([]) == nil)
    }

    @Test func partsOfTheDay() {
        func said(_ date: Date) -> String { UsageHeadline.when(date, now: Self.now, calendar: newYork) }
        #expect(said(local(2026, 10, 7, 12)) == "this afternoon")
        #expect(said(local(2026, 10, 7, 11, 59)) == "this morning")
        #expect(said(local(2026, 10, 7, 5)) == "this morning")
        #expect(said(local(2026, 10, 7, 16, 59)) == "this afternoon")
        #expect(said(local(2026, 10, 7, 17)) == "this evening")
        #expect(said(local(2026, 10, 7, 21)) == "tonight")
        #expect(said(local(2026, 10, 7, 3)) == "tonight")
        #expect(said(local(2026, 10, 8, 9)) == "tomorrow morning")
        #expect(said(local(2026, 10, 8, 22)) == "tomorrow night")
        #expect(said(local(2026, 10, 9, 15)) == "Friday afternoon")
        #expect(said(local(2026, 10, 11, 9)) == "Sunday morning")
    }

    @Test func nearlyOutIsNotOut() throws {
        let nearly = Self.plan("Harbor Labs", reading(org: "harbor", week: 92, weekResetsAt: local(2026, 10, 11, 9), at: Self.now))
        #expect(nearly.state == .out)
        let h = try #require(Self.headline([Self.personal, nearly]))
        #expect(h.title == "Harbor Labs is nearly out")
        #expect(h.detail == "8% left until Sun 9 AM. Personal covers.")
        let alone = try #require(Self.headline([nearly]))
        #expect(alone.detail == "8% left until Sun 9 AM.")
    }

    @Test func reallyOutComesBeforeNearlyOut() throws {
        let nearly = Self.plan("Harbor Labs", reading(org: "harbor", week: 92, weekResetsAt: local(2026, 10, 11, 9), at: Self.now))
        let out = Self.plan("Work", reading(org: "work", week: 100, weekResetsAt: local(2026, 10, 7, 21), at: Self.now))
        #expect(try #require(Self.headline([nearly, out])).title == "Work is out until tonight")
    }

    @Test func theOwnersRedLineDecidesNearlyOut() throws {
        let t = { var t = Thresholds(); t.redWeekLeft = 20; return t }()
        let r = reading(org: "harbor", week: 82, weekResetsAt: local(2026, 10, 11, 9), at: Self.now)
        let plan = UsageHeadline.Plan(name: "Harbor Labs", reading: r, forecast: nil, state: PlanStates.state(r, nil, t))
        let h = try #require(UsageHeadline.make([plan], now: Self.now, formatting: fmt, thresholds: t, calendar: newYork))
        #expect(h.title == "Harbor Labs is nearly out")
        #expect(h.detail == "18% left until Sun 9 AM.")
    }

    @Test func nearlyFullFiveHoursSaysSo() throws {
        let r = reading(org: "harbor", week: 40, weekResetsAt: local(2026, 10, 11, 9), session: 96,
                        sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        let h = try #require(Self.headline([Self.plan("Harbor Labs", r)]))
        #expect(h.title == "Harbor Labs has nearly used its 5 hours")
        #expect(h.detail == "Back 2:05 PM.")
    }

    @Test func anOldForecastAlreadyOverIsNotSaidInTheFuture() throws {
        let then = local(2026, 10, 6, 9)
        let reset = local(2026, 10, 11, 9)
        let r = reading(org: "harbor", week: 81, weekResetsAt: reset, at: then)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: reset, at: local(2026, 10, 4, 10))]
        let f = Pace.forecast(r, history: history, now: then)
        let plan = UsageHeadline.Plan(name: "Harbor Labs", reading: r, forecast: f, state: .runsOutEarly)
        let h = try #require(UsageHeadline.make([plan], now: local(2026, 10, 8, 20), formatting: fmt, calendar: newYork))
        #expect(h.title == "Harbor Labs may have run out")
        #expect(h.detail.hasPrefix("Empty about "))
    }

    @Test func nightsAfterMidnightBelongToThePreviousDay() {
        // Wednesday 11 PM: 1 AM Thursday is still tonight; 2 AM Friday is tomorrow night.
        let late = local(2026, 10, 7, 23)
        func said(_ date: Date, from now: Date = late) -> String { UsageHeadline.when(date, now: now, calendar: newYork) }
        #expect(said(local(2026, 10, 8, 1)) == "tonight")
        #expect(said(local(2026, 10, 9, 2)) == "tomorrow night")
        #expect(said(local(2026, 10, 10, 2)) == "Friday night")
        // Wednesday 11:32 AM: Friday 2 AM is Thursday night, which is tomorrow night.
        #expect(said(local(2026, 10, 9, 2), from: Self.now) == "tomorrow night")
        #expect(said(local(2026, 10, 10, 2), from: Self.now) == "Friday night")
        // 4:59 AM is still night, 5 AM is morning.
        #expect(said(local(2026, 10, 9, 4, 59), from: Self.now) == "tomorrow night")
        #expect(said(local(2026, 10, 9, 5), from: Self.now) == "Friday morning")
    }
}
