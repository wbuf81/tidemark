import Testing
import Foundation
@testable import TidemarkCore

@Suite struct PlanVerdictSuite {
    static let now = local(2026, 10, 7, 11, 32)
    static let reset = local(2026, 10, 11, 9)

    /// Harbor Labs' week: 81% used, runs out Thursday evening, back Sunday 9 AM.
    static var harbor: (reading: Reading, forecast: WeekForecast?) {
        let r = reading(org: "harbor", week: 81, weekResetsAt: reset, at: now)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: reset, at: local(2026, 10, 4, 10))]
        return (r, Pace.forecast(r, history: history, now: now))
    }

    static func verdict(_ r: Reading, _ f: WeekForecast?, _ state: PlanState, _ formatting: Formatting = fmt) -> PlanVerdict {
        PlanVerdict.make(reading: r, forecast: f, state: state, now: now, formatting: formatting)
    }

    /// A week half gone with `used` % used and no history: what would be left at reset follows.
    static func halfWeek(_ used: Double, session: Double = 0, sessionResetsAt: Date? = nil) -> (Reading, WeekForecast?) {
        let r = reading(week: used, weekResetsAt: now.addingTimeInterval(84 * 3600), session: session,
                        sessionResetsAt: sessionResetsAt, at: now)
        return (r, Pace.forecast(r, history: [], now: now))
    }

    @Test func aNewWeekSaysSoInsteadOfForecasting() {
        let r = reading(week: 2, weekResetsAt: Self.now.addingTimeInterval(167 * 3600), at: Self.now)
        let f = Pace.forecast(r, history: [], now: Self.now)
        let v = Self.verdict(r, f, PlanStates.state(r, f))
        #expect(v.state == .fine)
        #expect(v.line == "New week · 98% left")
        #expect(v.short == ["New week", "98% left"])
        #expect(v.untilEmpty == nil)
        #expect(v.locked == nil)
    }

    @Test func fineWithSomethingLeftSaysHowMuchIsSpare() {
        let (r, f) = Self.halfWeek(40)
        let v = Self.verdict(r, f, PlanStates.state(r, f))
        #expect(v.state == .fine)
        #expect(v.line == "~20% left at reset")
        #expect(v.short == ["~20%", "spare"])
        #expect(v.untilEmpty == nil)
        #expect(v.locked == nil)
    }

    @Test func fineAndUsingItAllIsOnPace() {
        let (r, f) = Self.halfWeek(50)
        let v = Self.verdict(r, f, .fine)
        #expect(v.line == "On pace to use it all")
        #expect(v.short == ["On", "pace"])
    }

    @Test func runsOutEarlySaysWhenAndHowLongItIsLocked() throws {
        let (r, f) = Self.harbor
        #expect(try #require(f).runsOutEarlyByHours != nil)
        let v = Self.verdict(r, f, .runsOutEarly)
        #expect(v.line == "Runs out Thu 9:36 PM")
        #expect(v.short == ["Empty", "Thu 9:36 PM"])
        #expect(v.untilEmpty == "34 h until empty, if the pace holds")
        #expect(v.locked == "Locked 59 h, back Sun 9 AM")
    }

    @Test func twentyFourHourClockTimes() {
        let (r, f) = Self.harbor
        let v = Self.verdict(r, f, .runsOutEarly, Formatting(calendar: newYork, twentyFourHour: true))
        #expect(v.line == "Runs out Thu 21:36")
        #expect(v.locked == "Locked 59 h, back Sun 09:00")
    }

    @Test func underAnHourToEmptyIsInMinutes() {
        // 99% used 66 hours into the week: empty in 40 minutes.
        let reset = Self.now.addingTimeInterval(102 * 3600)
        let r = reading(week: 99, weekResetsAt: reset, at: Self.now)
        let f = Pace.forecast(r, history: [], now: Self.now)
        let v = Self.verdict(r, f, .runsOutEarly)
        #expect(v.untilEmpty == "40 min until empty, if the pace holds")
    }

    @Test func fiveHoursNearlyUsedWithTheWeekFine() {
        let (r, f) = Self.halfWeek(40, session: 85, sessionResetsAt: Self.now.addingTimeInterval(3600))
        let v = Self.verdict(r, f, PlanStates.state(r, f))
        #expect(v.state == .runsOutEarly)
        #expect(v.line == "5 hours nearly used")
        #expect(v.short == ["5h", "nearly used"])
        #expect(v.untilEmpty == nil)
        #expect(v.locked == nil)
    }

    @Test func outForTheWeekSaysWhenItIsBack() {
        let tonight = reading(week: 100, weekResetsAt: local(2026, 10, 7, 21), at: Self.now)
        let a = Self.verdict(tonight, nil, .out)
        #expect(a.line == "Out until 9 PM")
        #expect(a.short == ["Out", "9 PM"])
        let sunday = reading(week: 100, weekResetsAt: Self.reset, at: Self.now)
        let b = Self.verdict(sunday, nil, .out)
        #expect(b.line == "Out until Sun 9 AM")
        #expect(b.short == ["Out", "Sun 9 AM"])
    }

    @Test func outForFiveHoursOnly() {
        let r = reading(week: 40, weekResetsAt: Self.reset, session: 100, sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        let v = Self.verdict(r, nil, .out)
        #expect(v.line == "5 hours out until 2:05 PM")
        #expect(v.short == ["5h out", "2:05 PM"])
    }

    @Test func noOpenWeekIsNotStarted() {
        let r = reading(week: 0, weekResetsAt: nil, at: Self.now)
        let v = Self.verdict(r, nil, .fine)
        #expect(v.line == "Not started")
        #expect(v.short == ["Not", "started"])
        #expect(v.untilEmpty == nil)
        #expect(v.locked == nil)
    }

    @Test func nearlyOutWeekSaysHowMuchIsLeftNotOut() {
        // 92% used: under the 10% red line, but not empty.
        let r = reading(week: 92, weekResetsAt: Self.reset, at: Self.now)
        let v = Self.verdict(r, nil, PlanStates.state(r, nil))
        #expect(v.state == .out)
        #expect(v.line == "Nearly out · 8% left")
        #expect(v.short == ["Nearly out", "8% left"])
    }

    @Test func nearlyOutFollowsTheOwnersRedLine() {
        let t = { var t = Thresholds(); t.redWeekLeft = 20; return t }()
        let r = reading(week: 82, weekResetsAt: Self.reset, at: Self.now)
        let state = PlanStates.state(r, nil, t)
        #expect(state == .out)
        let v = PlanVerdict.make(reading: r, forecast: nil, state: state, now: Self.now, formatting: fmt, thresholds: t)
        #expect(v.line == "Nearly out · 18% left")
        // At the default line the same reading is not red at all.
        #expect(PlanStates.state(r, nil) != .out)
    }

    @Test func aWeekAlmostGoneNeverSaysZeroLeft() {
        let r = reading(week: 99.8, weekResetsAt: Self.reset, at: Self.now)
        #expect(Self.verdict(r, nil, .out).line == "Nearly out · 1% left")
    }

    @Test func fiveHoursFullIsOutButNearlyFullIsNot() {
        let full = reading(week: 40, weekResetsAt: Self.reset, session: 100, sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        #expect(Self.verdict(full, nil, .out).line == "5 hours out until 2:05 PM")
        let nearly = reading(week: 40, weekResetsAt: Self.reset, session: 96, sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        let v = Self.verdict(nearly, nil, PlanStates.state(nearly, nil))
        #expect(v.state == .out)
        #expect(v.line == "5 hours nearly used")
        #expect(v.short == ["5h", "nearly used"])
    }

    @Test func aFullFiveHoursBeatsANearlyOutWeek() {
        let r = reading(week: 92, weekResetsAt: Self.reset, session: 100, sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        #expect(Self.verdict(r, nil, .out).line == "5 hours out until 2:05 PM")
        let both = reading(week: 100, weekResetsAt: Self.reset, session: 100, sessionResetsAt: local(2026, 10, 7, 14, 5), at: Self.now)
        #expect(Self.verdict(both, nil, .out).line == "Out until Sun 9 AM")
    }

    @Test func anOldForecastThatIsAlreadyOverSaysItRanOut() throws {
        // The reading is from Tuesday; by Wednesday the forecast's run-out has passed.
        let then = local(2026, 10, 6, 9)
        let r = reading(org: "harbor", week: 81, weekResetsAt: Self.reset, at: then)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: Self.reset, at: local(2026, 10, 4, 10))]
        let f = try #require(Pace.forecast(r, history: history, now: then))
        let late = local(2026, 10, 8, 20)
        let out = try #require(f.runsOutAt)
        #expect(out < late)
        let v = PlanVerdict.make(reading: r, forecast: f, state: .runsOutEarly, now: late, formatting: fmt)
        #expect(v.line.hasPrefix("Ran out about "))
        #expect(v.line.hasSuffix(", if the pace held"))
        #expect(v.untilEmpty == nil)
    }
}
