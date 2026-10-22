import Foundation
import Testing
@testable import TidemarkCore

/// The menu bar's batteries: which plans get one, their labels, the left %, the colour state, and the migration of the old switch.
struct MenuBarBatteriesTests {
    private func plan(_ id: String, _ name: String, used: Double?, _ state: PlanState? = .fine, old: Bool = false, mood: CodeMood? = nil) -> MenuBarBatteries.Plan {
        MenuBarBatteries.Plan(id: id, name: name, weekUsed: used, state: state, isOld: old, codeMood: mood)
    }

    @Test func oneBatteryPerReadPlanWhileLimitsAreOn() {
        let plans = [plan("a", "Personal", used: 58), plan("b", "Harbor Labs", used: nil, nil)]
        let items = MenuBarBatteries.make(plans, limitsOn: true, names: .names)
        #expect(items.map(\.id) == ["a"])
        #expect(MenuBarBatteries.make(plans, limitsOn: false, names: .names).isEmpty)
    }

    @Test func leftPercentIsTheWeekLeftRoundedAndClamped() {
        let items = MenuBarBatteries.make([plan("a", "A", used: 57.6), plan("b", "B", used: 120), plan("c", "C", used: -3)], limitsOn: true, names: .names)
        #expect(items.map(\.left) == [42, 0, 100])
        #expect(items.map(\.percentText) == ["42%", "Out", "100%"])
    }

    @Test func labelsAreNamesOrFirstLetters() {
        let p = [plan("a", "Harbor Labs", used: 10)]
        #expect(MenuBarBatteries.make(p, limitsOn: true, names: .names)[0].label == "Harbor Labs")
        #expect(MenuBarBatteries.make(p, limitsOn: true, names: .letters)[0].label == "H")
        #expect(MenuBarBatteries.make([plan("a", " ward", used: 10)], limitsOn: true, names: .letters)[0].label == "W")
    }

    @Test func stateDecidesColourAndTheWordOut() {
        let items = MenuBarBatteries.make([plan("a", "A", used: 50, .fine), plan("b", "B", used: 81, .runsOutEarly), plan("c", "C", used: 100, .out)], limitsOn: true, names: .names)
        #expect(items.map(\.fill) == [.ink, .amber, .red])
        #expect(items[2].percentText == "Out")
        #expect(items[1].percentText == "19%")
    }

    @Test func oldReadingsDimAndSayWhatVoiceOverReads() {
        let items = MenuBarBatteries.make([plan("a", "Personal", used: 58), plan("b", "Harbor Labs", used: 100, .out), plan("c", "Old", used: 58, old: true)], limitsOn: true, names: .letters)
        #expect(items[0].accessibility == "Personal: 42% of the week left")
        #expect(items[1].accessibility == "Harbor Labs: out")
        #expect(items[2].accessibility == "Old: 42% of the week left, old reading")
        #expect(items.map(\.dimmed) == [false, false, true])
    }

    @Test func theOldSwitchMigrates() {
        #expect(MenuBarMode.migrated(saved: nil, legacyIcon: true) == .batteries)
        #expect(MenuBarMode.migrated(saved: nil, legacyIcon: false) == .off)
        #expect(MenuBarMode.migrated(saved: nil, legacyIcon: nil) == .batteries)
        #expect(MenuBarMode.migrated(saved: "icon", legacyIcon: false) == .icon)
        #expect(MenuBarMode.migrated(saved: "nonsense", legacyIcon: nil) == .batteries)
        #expect(MenuBarMode.allCases.map(\.title) == ["A battery per plan", "Tidemark icon", "Off"])
        #expect(PlanNameStyle.allCases.map(\.title) == ["Names", "First letters"])
    }

    @Test func theBatteryShowsTheWeekOnlyAndSaysOutOnlyWhenItIsFull() {
        // 92% used: red, but 8% is still there.
        let nearly = MenuBarBatteries.make([plan("a", "Harbor Labs", used: 92, .out)], limitsOn: true, names: .names)[0]
        #expect(nearly.fill == .red)
        #expect(nearly.percentText == "8%")
        #expect(nearly.out == false)
        #expect(nearly.accessibility == "Harbor Labs: 8% of the week left")
        let full = MenuBarBatteries.make([plan("a", "Harbor Labs", used: 100, .out)], limitsOn: true, names: .names)[0]
        #expect(full.percentText == "Out")
        #expect(full.out)
    }

    @Test func theFiveHourWindowNeverTurnsTheBatteryRedOrSaysOut() {
        // 96% of the 5 hours with 60% of the week left: the week state is fine, so the battery is plain.
        let r = reading(week: 40, weekResetsAt: local(2026, 10, 11, 9), session: 96, at: local(2026, 10, 7, 11))
        #expect(PlanStates.state(r, nil) == .out)
        let week = PlanStates.weekState(r, nil)
        #expect(week == .fine)
        let item = MenuBarBatteries.make([plan("a", "Personal", used: r.week, week)], limitsOn: true, names: .names)[0]
        #expect(item.fill == .ink)
        #expect(item.percentText == "60%")
        #expect(item.out == false)
    }

    @Test func weekStateFollowsTheOwnersRedLine() {
        let r = reading(week: 82, weekResetsAt: local(2026, 10, 11, 9), at: local(2026, 10, 7, 11))
        var t = Thresholds(); t.redWeekLeft = 20
        #expect(PlanStates.weekState(r, nil, t) == .out)
        #expect(PlanStates.weekState(r, nil) == .fine)
    }

    // MARK: What moves on a battery

    @Test func onlyThePlanClaudeCodeIsOnShowsBubblesOrTheDot() {
        let moods: [(CodeMood?, MenuBarBatteries.Activity)] = [
            (.thinking, .working), (.tool, .working), (.permission, .needsYou),
            (.idle, .none), (.done, .none), (nil, .none),
        ]
        for (mood, expected) in moods {
            // The other plan carries no mood (the app passes one only for Claude Code's plan).
            let items = MenuBarBatteries.make([plan("a", "Personal", used: 58, mood: mood), plan("b", "Harbor Labs", used: 58)], limitsOn: true, names: .names)
            #expect(items[0].activity == expected, "\(String(describing: mood))")
            #expect(items[1].activity == .none)
        }
    }

    @Test func limitsOffMeansNoBatteriesAndSoNothingMoves() {
        #expect(MenuBarBatteries.make([plan("a", "A", used: 10, mood: .tool)], limitsOn: false, names: .names).isEmpty)
    }

    @Test func voiceOverSaysWhatClaudeCodeIsDoingOnThatBattery() {
        let items = MenuBarBatteries.make([
            plan("a", "Personal", used: 58, mood: .thinking), plan("b", "Harbor Labs", used: 100, .out, mood: .permission),
            plan("c", "Old", used: 58, old: true, mood: .tool), plan("d", "Quiet", used: 58, mood: .idle),
        ], limitsOn: true, names: .names)
        #expect(items[0].accessibility == "Personal: 42% of the week left, Claude Code is working")
        #expect(items[1].accessibility == "Harbor Labs: out, Claude Code needs you")
        #expect(items[2].accessibility == "Old: 42% of the week left, old reading, Claude Code is working")
        #expect(items[3].accessibility == "Quiet: 42% of the week left")
    }

    @Test func bubblesRiseOnlyWhileWorkingAndTheGateRuns() {
        var gate = WaveGate()
        gate.windowVisible = true
        #expect(MenuBarBatteries.effect(.working, gate: gate) == .init(bubbles: true, dot: false, pulse: false))
        #expect(MenuBarBatteries.effect(.none, gate: gate) == .init(bubbles: false, dot: false, pulse: false))
        #expect(MenuBarBatteries.effect(.needsYou, gate: gate) == .init(bubbles: false, dot: true, pulse: true))
    }

    @Test func everyReasonToStandStillTakesTheMotionAway() {
        let reasons: [(String, (inout WaveGate) -> Void)] = [
            ("not on screen", { $0.windowVisible = false }),
            ("screens asleep", { $0.screensAwake = false }),
            ("session resigned", { $0.sessionActive = false }),
            ("Reduce Motion", { $0.reduceMotion = true }),
            ("a picture", { $0.stillPicture = true }),
        ]
        for (name, stop) in reasons {
            var gate = WaveGate()
            gate.windowVisible = true
            stop(&gate)
            #expect(MenuBarBatteries.effect(.working, gate: gate) == .init(bubbles: false, dot: false, pulse: false), "\(name): no bubbles")
            // The dot is a signal, not decoration: it stays, still.
            #expect(MenuBarBatteries.effect(.needsYou, gate: gate) == .init(bubbles: false, dot: true, pulse: false), "\(name): still dot")
        }
    }
}
