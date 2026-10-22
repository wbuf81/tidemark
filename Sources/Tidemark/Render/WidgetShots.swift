import AppKit
import SwiftUI
import TidemarkCore

/// The widget and the vertical strip, in every state.
enum WidgetShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The widget and the strip", "The horizontal widget beside the Dock, on the theme's desktop gradient, 560 points wide unless the state says otherwise (`widget-*`): each plan a tide slot on the sky (water behind its name, the big used %, the verdict and the 5-hour line, Claude Code's chip on its plan), then the week band; Claude Code's status stays at the start only when plan limits are off or its plan isn't shown. Image renders can't draw the live frosted glass, so the cards are solid tiles; the in-use effect holds one still frame. `strip-*` is the widget as a strip on a side edge, 64 points (XS slots) or 112 (narrow slots stacked); `*-week-style` shots use Tide: Over the week.")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        widgetShots(stage) + stripShots(stage)
    }

    /// Every way a refresh can fail, with its file-name part.
    private static let problems: [(String, RefreshProblem)] = [
        ("offline", .offline), ("blocked", .blocked), ("unreadable", .changedShape(details: "")), ("refused", .refused),
        ("http-503", .http(503)), ("no-weekly-limit", .noWeeklyLimit),
    ]

    private static func widget(_ state: String, _ about: String, width: CGFloat = 560, _ make: @escaping RenderMake) -> Shot {
        Shot(screen: "widget", state: state, about: about) { dark in
            Renderer.picture(RenderWidgetScene(model: make(), width: width), dark: dark)
        }
    }

    /// The widget's and Usage's states before any reading: name, what it shows, how to build it. Plan
    /// limits are on in all of them (they are what the widget has nothing to show for).
    static func unread(_ stage: RenderStage) -> [(String, String, RenderMake)] {
        // Plan limits on, and Claude Code's hooks connected with nothing running: the status shows "Idle".
        func on(_ make: @escaping RenderMake) -> RenderMake {
            { let m = make(); m.settings.planLimits = true; m.hooksConnected = true; return m }
        }
        return [("signed-out", "Signed out of claude.ai: \"Sign in to claude.ai\" and Sign in…", on(stage.signedOut)),
                ("loading", "Signed in, before the first reading: \"Loading usage…\"", on(stage.model)),
                ("no-orgs", "Signed in, but the account has no plans: it says so instead of loading for good",
                 on({ stage.refreshed([], UsageRound.Outcome()) }))]
        + problems.map { name, problem in
            ("cant-read-\(name)", "Nothing could be read: \(GlanceCopy.problem(problem).title)", on({ stage.cantRead(problem) }))
        }
    }

    private static func widgetShots(_ stage: RenderStage) -> [Shot] {
        var shots = unread(stage).map { widget($0.0, $0.1, $0.2) }
        let (personal, harbor, lighthouse) = (DemoData.personal, DemoData.harbor, DemoData.lighthouse)
        shots += [
            widget("limits-off", "Plan limits off: Claude Code's status and the week, nothing else", width: 280) {
                let m = stage.mock([], mood: .tool, week: stage.mockWeek()); m.settings.planLimits = false; return m
            },
            widget("one-plan", "One plan, Personal: fine, with words for what would go unused", width: 320) {
                stage.mock([.personal], mood: .thinking)
            },
            widget("two-plans", "Two plans, Claude Code thinking: Personal fine (~20% would go unused), Harbor Labs runs out Sat 2 PM") {
                stage.mock([.personal, .harbor], mood: .thinking, week: stage.mockWeek())
            },
            widget("two-plans-no-week", "The same without a week calendar: no week band") { stage.mock([.personal, .harbor], mood: .thinking) },
            widget("two-plans-week-off", "Show the week turned off: no week band, the plans take its room") {
                let m = stage.mock([.personal, .harbor], mood: .thinking, week: stage.mockWeek()); m.settings.showWeekBand = false; return m
            },
            widget("two-plans-week-style", "Tide set to Over the week: the water traces the week to now, the paler forecast dashed ahead", width: 620) {
                let m = stage.mock([.personal, .harbor], mood: .thinking, week: stage.mockWeek()); m.settings.tideStyle = .week; return m
            },
            widget("narrow-badge", "Your width now (248 points): narrow slots, Claude Code's badge on Personal's corner", width: 248) {
                stage.mock([.personal, .harbor], mood: .permission)
            },
            widget("claude-on-hidden-plan", "Claude Code is on a plan that isn't shown: its status keeps the slot at the start", width: 520) {
                stage.mock([.personal, .harbor], mood: .thinking, claudeCode: DemoData.lighthouse)
            },
            widget("three-plans", "Three plans, Lighthouse Co's 5-hour window filling", width: 700) {
                stage.mock([.personal, .harbor, .lighthouse], mood: .tool)
            },
            widget("out", "One plan out, Claude Code needs you: the square, \"out until Mon 9 AM\", a 5-hour window not started") {
                stage.mock([.personal, .harborOut], mood: .permission, week: stage.mockWeek())
            },
            widget("not-started", "A week that hasn't started: 0% and an empty ring, \"week not started\"", width: 360) {
                stage.mock([.fresh], mood: .idle)
            },
            widget("three-digits", "A plan at 100%: the ring's three digits sit well inside it", width: 320) {
                stage.mock([.harborOut], mood: .done)
            },
            widget("org-cant-be-read", "Harbor Labs couldn't be read this round (access refused); Personal could") {
                let m = stage.mock([.personal, .harbor], mood: .idle, failing: [DemoData.harbor: .refused]); return m
            },
            widget("stale", "Every reading over 10 minutes old: hollow shapes, dimmed numbers, \"as of\"") {
                stage.mock([.personal, .harbor], mood: .idle, readAge: 50 * 60)
            },
            widget("one-plan-stale", "Harbor Labs's reading went stale while Personal's stayed fresh") {
                stage.mock([.personal, .harbor], mood: .idle, readAges: [DemoData.harbor: 50 * 60])
            },
            widget("advice", "Switch advice, the wide band: Personal's 5-hour window is busy, so Harbor Labs first", width: 600) {
                stage.mock([.personalBusy, .harbor], mood: .tool)
            },
            widget("advice-narrow-band", "Switch advice at M: the band shrinks to the arrow", width: 330) {
                stage.mock([.personalBusy, .harbor], mood: .tool)
            },
            widget("long-names", "Sixty-character plan names truncate; the ring and the next plan stay clear", width: 560) {
                stage.mock([.personal.named("Northern Harbor Maritime Research Laboratories, Lighthouse Division"),
                            .harbor.named("港湾研究所 — 灯台部門 — 潮汐表プロジェクト 🌊 Harbor Labs Extended Edition")], mood: .thinking)
            },
            widget("week-band-stale", "The week band dimmed: the calendar hasn't written its week in over 36 hours") {
                stage.mock([.personal, .harbor], mood: .thinking,
                           week: stage.mockWeek { $0.generated = stage.now.addingTimeInterval(-3 * 86400) })
            },
            widget("week-band-problems", "The week band with a ! : the calendar reports a problem") {
                stage.mock([.personal, .harbor], mood: .thinking,
                           week: stage.mockWeek { $0.problems = [.init(title: "The nightly build didn't run")] })
            },
            widget("in-use-effect", "Claude Code works on Personal: the in-use glow under its 5-hour cells (a still glow in renders)") {
                let m = stage.mock([.personal, .harbor], mood: .tool, working: true); return m
            },
        ]
        _ = (personal, harbor, lighthouse)
        for (name, width) in [("xs", 116), ("s", 200), ("m", 290), ("l", 400), ("xl", 560)] as [(String, CGFloat)] {
            let model = { stage.mock([.personal, .harbor], mood: .thinking) }
            let layout = WidgetSizing.layout(width: Double(width), orgs: 2, advice: false, week: false, status: .thinking)
            shots.append(widget("size-\(name)", "Two plans at \(Int(width)) points: size \(String(describing: layout.size).uppercased()) after the status slot", width: width, model))
        }
        // The widget at the heights real Docks give it: 16 pt is an auto-hiding Dock at its smallest, 64 and 72 pt
        // are Large icons. Height and scale are DockFit's own, so the slots are checked against what they get.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for (tile, reserved) in [(16.0, 0.0), (64.0, 106.0), (72.0, 114.0)] {
            let visible = CGRect(x: 0, y: reserved, width: 1512, height: 944 - reserved)
            let height = DockFit.height(screen: screen, visible: visible, tileSize: tile)
            let scale = DockFit.contentScale(screen: screen, visible: visible, tileSize: tile)
            for (name, width) in [("full", 560), ("narrow", 248)] as [(String, CGFloat)] {
                shots.append(widget("dock-\(Int(tile))-\(name)", "Dock icons \(Int(tile)) pt: the bar is \(Int(height)) pt, contents scaled \(String(format: "%.2f", scale)), so the slot has \(String(format: "%.1f", height / scale)) pt of room; the \(name) slots trim padding and drop the 5-hour row rather than cut off", width: width) {
                    let m = stage.mock([.personal, .harbor], mood: .thinking)
                    m.widgetHeight = CGFloat(height); m.widgetScale = CGFloat(scale)
                    return m
                })
            }
        }
        shots.append(widget("text-size-extra-large", "Text size Extra large (150%), 330 points wide", width: 330) {
            let m = stage.mock([.personal, .harbor], mood: .thinking); m.widgetScale = 1.5; m.widgetHeight = 82 * 1.5; return m
        })
        return shots
    }

    private static func stripShots(_ stage: RenderStage) -> [Shot] {
        func strip(_ state: String, _ about: String, width: CGFloat, _ make: @escaping RenderMake) -> Shot {
            Shot(screen: "strip", state: state, about: about) { dark in
                let model = make()
                model.vertical = true
                return Renderer.picture(RenderWidgetScene(model: model, width: width), dark: dark)
            }
        }
        var shots = [
            strip("narrow", "Two plans, narrow: Claude Code's status, then a shape, initial and two gauges each", width: 64) {
                stage.mock([.personal, .harbor], mood: .thinking)
            },
            strip("wide", "Two plans, wide: names, both percentages with bars, the one note that says which limit it means", width: 112) {
                stage.mock([.personal, .harbor], mood: .thinking)
            },
            strip("wide-week-style", "Narrow slots stacked, Tide set to Over the week", width: 112) {
                let m = stage.mock([.personal, .harbor], mood: .thinking); m.settings.tideStyle = .week; return m
            },
            strip("advice-narrow", "Switch advice atop the narrow strip: the arrow", width: 64) { stage.mock([.personalBusy, .harbor], mood: .tool) },
            strip("advice-wide", "Switch advice atop the wide strip: the arrow and the plan to move to", width: 112) {
                stage.mock([.personalBusy, .harbor], mood: .tool)
            },
            strip("three-plans", "Three plans, wide", width: 112) { stage.mock([.personal, .harbor, .lighthouse], mood: .tool) },
            strip("stale", "Every reading old: hollow shapes, dimmed numbers", width: 112) {
                stage.mock([.personal, .harbor], mood: .idle, readAge: 50 * 60)
            },
            strip("limits-off", "Plan limits off: the status and the week", width: 112) {
                let m = stage.mock([], mood: .tool, week: stage.mockWeek()); m.settings.planLimits = false; return m
            },
        ]
        for (state, about, make) in unread(stage) {
            for (name, width) in [("narrow", 64), ("wide", 112)] as [(String, CGFloat)] {
                shots.append(strip("\(state)-\(name)", "\(about) (\(name))", width: width, make))
            }
        }
        return shots
    }

    @MainActor static func notes(_ stage: RenderStage) -> [String: String] {
        ["notifications.md": notifications(stage), "menus.md": widgetMenu(stage)]
    }

    /// Every notification Tidemark can post.
    private static func notifications(_ stage: RenderStage) -> String {
        let (personal, harbor) = (DemoData.personal, DemoData.harbor)
        let s = stage.scenarios
        // One demo state per reason the switch advice can give, with when it's given.
        let reasons: [(String, DemoScenario)] = [
            ("Claude Code's org is red with under 10% of its week left (Settings → Plans → Show thresholds)",
             stage.scenario([personal, harbor], [stage.reading(personal, week: 95, weekReset: 33.5),
                                                   stage.reading(harbor, week: 40, weekReset: 64.5)])),
            ("Claude Code's org, shared with the desktop app, has its 5-hour window at 80% or more", s[1]),
            ("Claude Code's org is the extra one and has its 5-hour window at 80% or more",
             stage.scenario([personal, harbor], [stage.reading(personal, week: 30, weekReset: 64.5, session: 10, sessionReset: 3),
                                                   stage.reading(harbor, week: 40, weekReset: 40, session: 85, sessionReset: 2)],
                            claudeCode: harbor)),
            ("The org shared with the desktop app is under its 15% buffer", s[4]),
            ("Another org's week resets sooner, so its tokens would expire unused", s[2]),
            ("Neither week has started; ties go to the extra org", stage.scenario([personal, harbor], [
                stage.reading(personal, week: 0, weekReset: nil, fable: 0), stage.reading(harbor, week: 0, weekReset: nil, fable: 0)])),
        ]
        var text = """
            # Notifications

            Every notification Tidemark can post, with the demo names filled in. They come only from the \
            app bundle (a bare binary has no notification identity), and macOS asks for permission with the \
            first one. Clicking one opens Usage, or the sign-in window while signed out.

            ## Signed out

            When claude.ai ends a session that worked earlier in this run (not when the app launches signed \
            out, and not after Sign out).

            \(notice(Copy.signedOutNotice))

            ## Switch advice

            While Settings → Notifications → When Claude Code should move to another plan is on, when the switch \
            advice gets a new target (it must win two readings in a row, and advice to go back is held for \
            an hour unless the org Claude Code is on turns red). The body is the advice's reason, one of:

            """
        for (when, scenario) in reasons {
            let model = stage.demo(scenario)
            let line = model.advice.map { notice(Copy.switchNotice($0)) } ?? "(this demo state gives no advice any more: update `Renderer.notifications`)"
            text += "\n- \(when):\n\n  " + line.replacingOccurrences(of: "\n", with: "\n  ") + "\n"
        }
        text += """

            ## Claude Code's plan is nearly out

            While Settings → Notifications → When Claude Code’s plan runs low is on, when the plan Claude \
            Code is signed into (even if its card is hidden) drops below the red threshold for its week, or \
            its pace will run it out 12 or more hours before it resets, or its 5-hour window reaches the red \
            threshold. Each says why and when it is back.

            \(notice(Copy.nearlyOutNotice(harbor, left: 6, resets: stage.now.addingTimeInterval(4.9 * 86400), now: stage.now, formatting: Formatting())))

            \(notice(Copy.runsOutNotice(harbor, at: stage.now.addingTimeInterval(50.5 * 3600), early: 43 * 3600, now: stage.now, formatting: Formatting())))

            \(notice(Copy.sessionNotice(harbor, used: 96, resets: stage.now.addingTimeInterval(4.8 * 3600), now: stage.now, formatting: Formatting())))

            """
        return text
    }


    private static func notice(_ notice: Notice) -> String {
        "**\(notice.title)**\n\(notice.body)"
    }

    /// The widget's and the notch's menu: its items and when each shows.
    private static func widgetMenu(_ stage: RenderStage) -> String {
        var text = """
            # Menus

            ## The widget's and the notch's menu

            Right-click (or Control-click) the widget or the notch. Items in order, `—` for a separator:

            | Item | Shows |
            | --- | --- |

            """
        // Which of the four states (signed in or not, with a week calendar or not) each item shows in.
        let states = [false, true].flatMap { signedIn in [false, true].map { (signedIn: signedIn, calendar: $0) } }
        let all = WidgetMenuModel.entries(signedIn: false, calendar: true, tide: .level, showWeek: true)
        for item in all {
            guard let title = item.title else { text += "| — | |\n"; continue }
            let shown = states.filter { WidgetMenuModel.entries(signedIn: $0.signedIn, calendar: $0.calendar, tide: .level, showWeek: true).contains { $0.title == title } }
            let when: String
            switch (shown.count, shown.allSatisfy(\.calendar), shown.allSatisfy { !$0.signedIn }) {
            case (4, _, _): when = "Always"
            case (2, true, false) where title == "Show the week": when = "Once a week calendar is set up; checked while the week band shows (the widget only, not the notch)"
            case (2, true, false): when = "Once a week calendar is set up (Settings → Week, with Claude Code sessions on, and its week links to its pages)"
            case (2, false, true): when = "While signed out of claude.ai"
            default: when = shown.map { "\($0.signedIn ? "signed in" : "signed out")\($0.calendar ? ", with a week calendar" : "")" }.joined(separator: "; ")
            }
            let submenu = item.children.isEmpty ? "" : " (a submenu: \(item.children.compactMap(\.title).joined(separator: ", ")); the current one is checked, read each time the menu opens)"
            text += "| \(title) | \(when)\(submenu) |\n"
        }
        return text
    }
}

/// The mockups' plans, as readings for `RenderStage.mock`: the state they show comes from the numbers,
/// not from a label.
struct MockPlan {
    var org: Org
    var week: Double
    /// Hours until the week resets, as a date on the render's calendar.
    var weekReset: Date?
    /// How fast the last 72 hours used the week, in % an hour: the pace the forecast follows.
    var pace: Double
    var session: Double
    var sessionReset: Date?
    /// A model limit's use (the Fable limit), if the plan reports one.
    var fable: Double? = nil

    func withFable(_ use: Double) -> MockPlan { var p = self; p.fable = use; return p }

    func named(_ name: String) -> MockPlan { var p = self; p.org.name = name; return p }

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// 58%, resetting Fri 4 AM at 0.54%/h: about 20% would go unused. 5-hour 34%, back at 4:20 PM.
    static let personal = MockPlan(org: DemoData.personal, week: 58, weekReset: at(23, 4), pace: 0.5436, session: 34, sessionReset: at(21, 16, 20))
    /// The same plan with its 5-hour window at 85%: the switch advice's case.
    static let personalBusy = MockPlan(org: DemoData.personal, week: 60, weekReset: at(23, 4), pace: 0.5, session: 85, sessionReset: at(21, 13, 5))
    /// 81%, resetting Sun 9 AM at 0.26%/h: runs out Sat 2 PM. 5-hour 12%, back at 2:05 PM.
    static let harbor = MockPlan(org: DemoData.harbor, week: 81, weekReset: at(25, 9), pace: 0.2551, session: 12, sessionReset: at(21, 14, 5))
    /// Used up until Mon 9 AM, with its 5-hour window not started.
    static let harborOut = MockPlan(org: DemoData.harbor, week: 100, weekReset: at(26, 9), pace: 0.7, session: 0, sessionReset: nil)
    static let lighthouse = MockPlan(org: DemoData.lighthouse, week: 30, weekReset: at(24, 12), pace: 0.25, session: 82, sessionReset: at(21, 12, 30))
    /// A week that hasn't started: nothing used, no reset yet.
    static let fresh = MockPlan(org: DemoData.harbor, week: 0, weekReset: nil, pace: 0, session: 0, sessionReset: nil)
}

extension RenderStage {
    /// The week calendar's week as the mockups show it (19h 20m, most on tide-tables), changed by `change`.
    func mockWeek(_ change: (inout WeekSummary) -> Void = { _ in }) -> WeekSummary {
        var week = DemoCalendar.store().weekSummary(containing: now, weekStart: .monday, now: now)
        change(&week)
        return week
    }

    /// The poller's path with the mockups' plans: an older round 72 hours back (so the 72-hour pace is
    /// the plan's own), then a round now. `readAge` makes every reading that old; `readAges` single
    /// plans' (by organisation); `failing` plans couldn't be read this round. Plan limits are on;
    /// Claude Code is on the first plan, in `mood` (nil shows none), working when `working`.
    func mock(_ plans: [MockPlan], mood: CodeMood?, week: WeekSummary? = nil, readAge: TimeInterval = 0,
              readAges: [Org: TimeInterval] = [:], failing: [Org: RefreshProblem] = [:], working: Bool = false,
              claudeCode: Org? = nil) -> AppModel {
        let model = model()
        model.settings.planLimits = true
        let orgs = plans.map(\.org)
        func reading(_ p: MockPlan, at time: Date, week: Double, session: Double, sessionReset: Date?) -> Reading {
            Reading(time: time, org: p.org.id, session: session, sessionResetsAt: sessionReset, week: week,
                    weekResetsAt: p.weekReset, scoped: p.fable.map { ["Fable": $0 * week / max(p.week, 1)] } ?? [:])
        }
        let claude = claudeCode ?? orgs.first
        model.setAvailableOrgs(orgs, claudeCodeOrg: claude?.id)
        // Read since the week began (a reading at its start), and 72 hours ago at the plan's own pace.
        let started = plans.filter { $0.weekReset != nil && failing[$0.org] == nil }
        for p in started {
            let first = p.weekReset!.addingTimeInterval(-Pace.window + 1800)
            model.ingest(UsageRound.Outcome(readings: [reading(p, at: first, week: 0, session: 0, sessionReset: nil)]),
                         claudeCodeOrg: claude?.id, at: first)
        }
        for p in started {
            let before = now.addingTimeInterval(-(readAges[p.org] ?? readAge) - 72 * 3600)
            model.ingest(UsageRound.Outcome(readings: [reading(p, at: before, week: max(p.week - p.pace * 72, 0), session: 0, sessionReset: nil)]),
                         claudeCodeOrg: claude?.id, at: before)
        }
        let current = plans.filter { failing[$0.org] == nil }.map { p -> Reading in
            reading(p, at: now.addingTimeInterval(-(readAges[p.org] ?? readAge)), week: p.week, session: p.session,
                    sessionReset: p.sessionReset)
        }
        let failures = failing.map { UsageRound.Failure(org: $0.key, problem: $0.value) }
        let round = UsageRound.Outcome(readings: current, failures: failures)
        model.ingest(round, claudeCodeOrg: claude?.id, at: now)
        // Switch advice must win two readings in a row before it shows.
        if claudeCode != nil || plans.contains(where: { $0.session >= 80 }) { model.ingest(round, claudeCodeOrg: claude?.id, at: now) }
        model.showWeek(week)
        if let mood {
            let time = now.addingTimeInterval(-5)
            model.hooksConnected = true
            model.sessionsChanged([CodeStatus.parse("\(mood.rawValue) \(Int(time.timeIntervalSince1970))", pid: getpid())!])
        }
        if working { model.claudeCodeWorked(at: now.addingTimeInterval(-2)) }
        model.now = now
        model.widgetHeight = 82
        return model
    }
}

/// The widget (or strip) at `width` on the theme's desktop.
struct RenderWidgetScene: View {
    @ObservedObject var model: AppModel
    var width: CGFloat

    var body: some View {
        WidgetView(model: model, actions: .none, width: width).fixedSize()
            .padding(24)
            .background(ShowcaseWallpaper())
    }
}
