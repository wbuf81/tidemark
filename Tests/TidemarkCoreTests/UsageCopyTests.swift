import Foundation
import Testing
@testable import TidemarkCore

/// A row with a hand-made forecast, for copy tests.
func copyRow(_ kind: LimitKind = .week, org: String = "personal", used: Double = 40, reset: Date?,
             runsOutAt: Date? = nil, atReset: Double = 100, stale: Bool = false) -> ForecastRow {
    let forecast = reset.map { reset in
        WeekForecast(used: used, hoursLeft: reset.timeIntervalSince(forecastNow) / 3600, elapsedFraction: 0.5,
                     pacePerHour: 1, forecastAtReset: atReset, unused: 100 - atReset,
                     runsOutEarlyByHours: runsOutAt.map { reset.timeIntervalSince($0) / 3600 }, runsOutAt: runsOutAt,
                     useItAllPerHour: 1, byMidnight: 0)
    }
    return ForecastRow(id: LimitID(org: org, kind: kind), used: used, resetsAt: reset, forecast: forecast,
                       runsOutAt: runsOutAt, isStale: stale, since: stale ? forecastNow.addingTimeInterval(-3600) : nil)
}

@Suite struct UsageCopyTests {
    let names = ["personal": "Personal", "harbor": "Harbor Labs"]
    let wed9 = local(2026, 10, 21, 21)
    let fri4 = local(2026, 10, 23, 4)
    let tue6 = local(2026, 10, 20, 18)

    func headline(_ rows: [ForecastRow], signedIn: Bool = true, problem: String? = nil) -> Headline {
        UsageCopy.headline(rows, names: names, signedIn: signedIn, problem: problem, now: forecastNow, formatting: fmt)
    }

    @Test func headlineOneRunsOut() {
        let h = headline([copyRow(reset: wed9, runsOutAt: tue6), copyRow(org: "harbor", reset: fri4, atReset: 64)])
        #expect(h.title == "Personal runs out Tue 6 PM, 27 h before reset")
        #expect(h.subtitle == "Harbor Labs would leave about 36% unused at Fri 23 Oct, 4 AM.")
        #expect(h.focus == LimitID(org: "personal", kind: .week))
    }

    @Test func headlineTwoRunOut() {
        let h = headline([copyRow(org: "harbor", reset: fri4, runsOutAt: local(2026, 10, 21, 8)),
                          copyRow(reset: wed9, runsOutAt: tue6)])
        #expect(h.title == "2 limits run out before reset")
        #expect(h.subtitle == "Personal first, Tue 6 PM, then locked 27 h")
        #expect(h.focus == LimitID(org: "personal", kind: .week))
    }

    @Test func headlineFiveHourSubtitleIsTheSoonest() {
        let h = headline([copyRow(reset: fri4),
                          copyRow(.session, org: "personal", reset: forecastNow.addingTimeInterval(4 * 3600), runsOutAt: forecastNow.addingTimeInterval(1800 + 1500)),
                          copyRow(.session, org: "harbor", reset: forecastNow.addingTimeInterval(4 * 3600), runsOutAt: forecastNow.addingTimeInterval(1200))])
        #expect(h.subtitle == "Harbor Labs’s 5-hour window runs out at 3 PM.")
    }

    @Test func barsSummaryForDays() throws {
        let reset = local(2026, 10, 19, 4)
        var d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .week), reading: reading(week: 40, weekResetsAt: reset, at: forecastNow),
                                               history: [], now: forecastNow, calendar: newYork))
        d.bars = [DetailBar(date: local(2026, 10, 14), value: 2.4, tone: .under),
                  DetailBar(date: local(2026, 10, 15), value: 16.6, tone: .over),
                  DetailBar(date: local(2026, 10, 16), value: 13, tone: .today)]
        d.perDayLine = 3.64
        #expect(UsageCopy.barsSummary(d, now: forecastNow, formatting: fmt)
                == "Recent pace: Wed 2 under, Thu 17 over, Today 13; use-it-all 3.6% a day")
    }

    @Test func barsSummaryForWindows() throws {
        let reset = local(2026, 10, 16, 17)
        var d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .session),
                                               reading: reading(week: 40, weekResetsAt: local(2026, 10, 19, 4), session: 30, sessionResetsAt: reset, at: forecastNow),
                                               history: [], now: forecastNow, calendar: newYork))
        d.bars = [DetailBar(date: local(2026, 10, 16, 9), value: 100, tone: .hitLimit),
                  DetailBar(date: local(2026, 10, 16, 14), value: 45, tone: .plain)]
        #expect(UsageCopy.barsSummary(d, now: forecastNow, formatting: fmt) == "Recent windows: 9 AM 100 full, 2 PM 45; peak use")
    }

    @Test func headlineOutNow() {
        let h = headline([copyRow(used: 100, reset: wed9, runsOutAt: forecastNow)])
        #expect(h.title == "Personal is out until Wed 9 PM")
    }

    @Test func headlineModelLimit() {
        let h = headline([copyRow(.model("Fable"), reset: wed9, runsOutAt: tue6)])
        #expect(h.title == "Personal’s Fable limit runs out Tue 6 PM, 27 h before reset")
    }

    @Test func runningOutUnderAnHourEarlyIsOnPace() {
        let h = headline([copyRow(reset: wed9, runsOutAt: wed9.addingTimeInterval(-1800))])
        #expect(h.title == "Every limit is on pace to be used by reset")
        #expect(h.focus == nil)
    }

    @Test func headlineUnused() {
        let h = headline([copyRow(reset: wed9, atReset: 98), copyRow(org: "harbor", reset: fri4, atReset: 64)])
        #expect(h.title == "About 36% of Harbor Labs’s week would go unused")
        #expect(h.subtitle == "At your pace it reaches ~64% by Fri 23 Oct, 4 AM.")
        #expect(h.focus == LimitID(org: "harbor", kind: .week))
    }

    @Test func oneOrgHasNoOtherOrgSubtitle() {
        let h = headline([copyRow(reset: wed9, atReset: 60), copyRow(.model("Fable"), reset: wed9, atReset: 70)])
        #expect(h.title == "About 40% of Personal’s week would go unused")
        #expect(h.subtitle == "At your pace it reaches ~60% by Wed 9 PM.")
        let onPace = headline([copyRow(reset: wed9, atReset: 99), copyRow(.model("Fable"), reset: wed9, atReset: 70)])
        #expect(onPace.title == "Every limit is on pace to be used by reset")
    }

    @Test func modelLimitsNeverGoUnused() {
        let h = headline([copyRow(reset: wed9, atReset: 98), copyRow(.model("Fable"), reset: wed9, atReset: 0)])
        #expect(h.title == "Every limit is on pace to be used by reset")
    }

    @Test func headlineOnPaceWithAFiveHourWindowRunningOut() {
        let h = headline([copyRow(reset: wed9, atReset: 98),
                          copyRow(.session, used: 90, reset: local(2026, 10, 16, 17, 20), runsOutAt: local(2026, 10, 16, 15, 10))])
        #expect(h.title == "Every limit is on pace to be used by reset")
        #expect(h.subtitle == "Personal’s 5-hour window runs out at 3:10 PM.")
    }

    @Test func headlineNoFreshReadings() {
        let stale = [copyRow(reset: wed9, atReset: 10, stale: true)]
        #expect(headline(stale, signedIn: false) == Headline(title: "No fresh readings", subtitle: "Sign in to claude.ai to see the forecast", focus: nil))
        #expect(headline([], problem: "claude.ai isn't answering") == Headline(title: "No readings yet", subtitle: "claude.ai isn't answering", focus: nil))
    }

    @Test func staleRowsDontCount() {
        let h = headline([copyRow(reset: wed9, atReset: 98), copyRow(org: "harbor", reset: fri4, atReset: 10, stale: true)])
        #expect(h.title == "Every limit is on pace to be used by reset")
    }

    @Test func zeroThresholdIgnoresRowsWithoutAForecast() {
        var thresholds = Thresholds()
        thresholds.onPaceUnused = 0
        let rows = [copyRow(reset: nil), copyRow(org: "harbor", reset: fri4, atReset: 64),
                    copyRow(.model("Fable"), reset: wed9, atReset: 98)]
        let h = UsageCopy.headline(rows, names: names, signedIn: true, problem: nil, now: forecastNow, formatting: fmt, thresholds)
        #expect(h.title == "About 36% of Harbor Labs’s week would go unused")
        #expect(h.focus == LimitID(org: "harbor", kind: .week))
    }

    @Test func labelsAndNames() {
        #expect(UsageCopy.rowLabel(.week, org: "Personal") == "Personal")
        #expect(UsageCopy.rowLabel(.model("Fable"), org: "Personal") == "Fable")
        #expect(UsageCopy.rowLabel(.session, org: "Personal") == "5 hours")
        #expect(UsageCopy.limitName(.session, org: "Personal") == "Personal’s 5-hour window")
        #expect(UsageCopy.detailTitle(.model("Fable"), org: "Personal") == "Personal · Fable")
        #expect(UsageCopy.detailTitle(.week, org: "Personal") == "Personal · week")
    }

    @Test func voiceOverSentences() {
        #expect(UsageCopy.voiceOver(copyRow(reset: wed9, runsOutAt: tue6), org: "Personal", now: forecastNow, formatting: fmt)
                == "Personal, week: runs out Tue 6 PM, 27 h before it resets Wed 9 PM.")
        #expect(UsageCopy.voiceOver(copyRow(org: "harbor", reset: fri4, atReset: 64), org: "Harbor Labs", now: forecastNow, formatting: fmt)
                == "Harbor Labs, week: about 64% at reset, about 36% unused. Resets Fri 23 Oct, 4 AM.")
        #expect(UsageCopy.voiceOver(copyRow(.session, reset: nil), org: "Personal", now: forecastNow, formatting: fmt)
                == "Personal, 5 hours: not started.")
    }

    @Test func detailText() throws {
        let reset = local(2026, 10, 21, 21)
        let d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .week), reading: reading(week: 41, weekResetsAt: reset, at: forecastNow),
                                               history: [], now: forecastNow, calendar: newYork))
        #expect(UsageCopy.lead(d) == "Used 41% in 25% of the window.")
        let stats = UsageCopy.stats(d, now: forecastNow, formatting: fmt)
        #expect(stats.map(\.label) == ["Pace", "Runs out", "Locked before reset"])
        #expect(stats[0].note == "vs use-it-all")
        #expect(stats[1].note == nil)
        #expect(stats[0].value == String(format: "%.1f×", d.paceMultiple!))
        #expect(stats[1].value == "Mon 2:37 AM")
        #expect(UsageCopy.barsTitle(.week).title == "Recent pace")
        #expect(UsageCopy.barsTitle(.week).note == "% used per day")
        #expect(UsageCopy.barsTitle(.session).title == "Recent windows")
        #expect(UsageCopy.barsTitle(.session).note == "peak use")
        #expect(UsageCopy.barsCaption(d) == String(format: "Use-it-all from now: %.1f%% a day", d.perDayLine!))
        #expect(UsageCopy.barLabel(d.bars.last!, kind: .week, now: forecastNow, formatting: fmt) == "Today")
        #expect(UsageCopy.barLabel(d.bars.first!, kind: .week, now: forecastNow, formatting: fmt) == "Sat")
        #expect(UsageCopy.tickLabel(d.ticks.first!, kind: .week, formatting: fmt) == "Thu")
    }

    @Test func unusedStats() throws {
        let reset = local(2026, 10, 19, 4)
        let d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .week), reading: reading(week: 40, weekResetsAt: reset, at: forecastNow),
                                               history: [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600))],
                                               now: forecastNow, calendar: newYork))
        let stats = UsageCopy.stats(d, now: forecastNow, formatting: fmt)
        #expect(stats.map(\.label) == ["Pace", "At reset", "Unused"])
        #expect(stats[1].value == "~63%")
        #expect(stats[2] == DetailStat(label: "Unused", value: "~37%"))
    }

    @Test func modelLimitThatLastsSaysLeftAtReset() throws {
        let reset = local(2026, 10, 19, 4)
        let d = try #require(LimitDetails.make(LimitID(org: "personal", kind: .model("Fable")),
                                               reading: reading(week: 40, weekResetsAt: reset, at: forecastNow, scoped: ["Fable": 1]),
                                               history: [reading(week: 10, weekResetsAt: reset, at: forecastNow.addingTimeInterval(-80 * 3600), scoped: ["Fable": 0])],
                                               now: forecastNow, calendar: newYork))
        let stats = UsageCopy.stats(d, now: forecastNow, formatting: fmt)
        // A model limit is a cap: no pace to compare with use-it-all (S3.4).
        #expect(stats.map(\.label) == ["At reset", "Left at reset"])
    }

    @Test func adviceSaysHow() {
        #expect(UsageCopy.switchHow(to: "Personal") == "Move Claude Code to Personal: run /login in Claude Code and pick Personal.")
        #expect(UsageCopy.switchHow(to: "Harbor Labs") == "Move Claude Code to Harbor Labs: run /login in Claude Code and pick Harbor Labs.")
        // With the reason first, for the window's brief and the notice's body.
        #expect(UsageCopy.switchHow(to: "Personal", reason: "Harbor Labs is nearly out")
                == "Harbor Labs is nearly out. Move Claude Code to Personal: run /login in Claude Code and pick Personal.")
    }

    @Test func modelToggleNamesTheModels() {
        #expect(UsageCopy.modelToggle(names: ["Fable"]) == "Show model limits (Fable)")
        #expect(UsageCopy.modelToggle(names: ["Sonnet", "Fable"]) == "Show model limits (Fable and Sonnet)")
        #expect(UsageCopy.modelToggle(names: ["Opus", "Sonnet", "Fable"]) == "Show model limits (Fable, Opus and Sonnet)")
        #expect(UsageCopy.modelToggle(names: []) == "Show model limits")
    }

    @Test func limitsOffAndSignedOutWords() {
        #expect(UsageCopy.limitsOff.title == "Plan limits are off")
        #expect(UsageCopy.limitsOff.detail == "Turn them on in Settings → General to see each plan’s 5-hour window and week.")
        #expect(UsageCopy.limitsOff.button == "Turn on…")
        #expect(UsageCopy.signedOut.title == "Sign in to claude.ai")
        #expect(UsageCopy.signedOut.button == "Sign in…")
    }
}
