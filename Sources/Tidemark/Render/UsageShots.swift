import AppKit
import SwiftUI
import TidemarkCore

/// Usage: the page's content at the width the main window gives it.
enum UsageShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("Usage", "The Usage page on the sky (dawn in light, dusk in dark) at 980 points (the main window's width less its sidebar), its whole height: the headline and its detail, a glass card per plan (what's left, the forecast pie, what the week comes to, the lock, the pace, the 5-hour line) and Claude Code's, then the chosen plan's Week panel (what's left falling, the dashed forecast, the locked hours, the hours used), its pace and its busiest hours. The most urgent plan is chosen unless the state says otherwise. Plan limits are on unless the state says off. The real window, drawn offscreen, is in the window pictures.")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        let s = stage.scenarios
        let (personal, harbor) = (DemoData.personal, DemoData.harbor)
        func usage(_ state: String, _ about: String, selection: LimitID? = nil, lastWeek: Bool = false, width: CGFloat = 980,
                   limits: Bool = true, _ make: @escaping RenderMake) -> Shot {
            Shot(screen: "usage", state: state, about: about) { dark in
                let model = make()
                model.settings.planLimits = limits
                return Renderer.picture(RenderUsageScene(model: model, width: width, selection: selection, lastWeek: lastWeek), dark: dark)
            }
        }
        /// The widget's moment and numbers, so every picture of a plan reads the same: Personal 58% with room to
        /// spare, Harbor Labs 81% on course to run out Saturday, Claude Code on Harbor Labs.
        let plans: [MockPlan] = [MockPlan.personal.withFable(31), MockPlan.harbor.withFable(6)]
        let mockup: RenderMake = { stage.mock(plans, mood: nil, claudeCode: harbor) }
        /// The same, with a full week before this one read back from history.
        func withLastWeek(_ make: @escaping RenderMake) -> RenderMake {
            {
                let model = make()
                let current = model.orgs.compactMap { model.latest[$0.id] }
                let days: [(Double, Double)] = [(0.4, 3), (1.2, 14), (2.5, 31), (3.7, 48), (4.9, 66), (6.2, 84)]
                for (day, used) in days {
                    let readings = current.compactMap { r -> Reading? in
                        guard let reset = r.weekResetsAt else { return nil }
                        let before = reset.addingTimeInterval(-Pace.window)
                        return Reading(time: before.addingTimeInterval(-Pace.window + day * 86_400), org: r.org, session: 0,
                                       sessionResetsAt: nil, week: used, weekResetsAt: before)
                    }
                    model.ingest(UsageRound.Outcome(readings: readings), claudeCodeOrg: model.claudeCodeOrg, at: readings.first?.time ?? stage.now)
                }
                // Advice must win two readings in a row before it shows.
                for _ in 0..<2 { model.ingest(UsageRound.Outcome(readings: current), claudeCodeOrg: model.claudeCodeOrg, at: stage.now) }
                model.now = stage.now
                return model
            }
        }
        return [
            usage("two-plans", "Two plans: Personal has room to spare, Harbor Labs runs out early and is chosen, and Claude Code is on it, so its card says how to move it", mockup),
            usage("personal-chosen", "The same, with Personal's card chosen: its week lasts, so the chart has a dashed line to the reset and no lock",
                  selection: LimitID(org: personal.id, kind: .week), mockup),
            usage("one", "One plan: no switch to suggest") { stage.mock([.personal], mood: nil) },
            usage("three", "Three plans and Claude Code's card wrap to two rows", { stage.mock([.personal, .harbor, .lighthouse], mood: nil) }),
            usage("out", "Harbor Labs is out until Monday: the headline says so, its card is red-marked and the chart is hatched from when it ran out") {
                stage.mock([.personal, .harborOut], mood: nil, claudeCode: harbor)
            },
            usage("last-week", "Harbor Labs's Week panel on Last week: the week before this one, read back from history, with no now and no forecast",
                  lastWeek: true, withLastWeek(mockup)),
            usage("stale", "Every reading 40 minutes old: hollow marks, dimmed numbers, \"as of\"") {
                stage.mock(plans, mood: nil, readAge: 40 * 60, claudeCode: harbor)
            },
            usage("refused", "Harbor Labs refused this round: its card says why instead of numbers, and a banner names the problem") {
                stage.mock(plans, mood: nil, failing: [harbor: .refused], claudeCode: harbor)
            },
            usage("no-history", "A first reading and nothing before it: the chart has only today", {
                stage.refreshed([personal, harbor], UsageRound.Outcome(readings: [s[0].readings[0], s[0].readings[1]]))
            }),
            usage("model-detail", "Personal's Fable limit chosen: its tab in the Week panel, within limit, no use-it-all line",
                  selection: LimitID(org: personal.id, kind: .model("Fable")), mockup),
            usage("session-detail", "Personal's 5-hour window chosen: peak per window and the open one",
                  selection: LimitID(org: personal.id, kind: .session), mockup),
            usage("signed-out", "Signed out of claude.ai", stage.signedOut),
            usage("limits-off", "Plan limits are off in Settings: a message and Turn on…", limits: false, mockup),
            usage("changed-shape", "claude.ai answered in a way Tidemark can't read: the banner offers Copy details", {
                stage.cantRead(.changedShape(details: "usage: unexpected shape at five_hour"))
            }),
            usage("offline", "Nothing could be read: offline", { stage.cantRead(.offline) }),
            usage("narrow", "At 640 points, the window's smallest: the cards wrap to two a row and the panels stack tighter", width: 640, mockup),
        ]
    }
}

/// The Usage page's content at `width`, its whole height, on the sky.
struct RenderUsageScene: View {
    @ObservedObject var model: AppModel
    var width: CGFloat
    @StateObject private var chosen = UsageSelection()
    var selection: LimitID?

    init(model: AppModel, width: CGFloat, selection: LimitID?, lastWeek: Bool = false) {
        self.model = model
        self.width = width
        self.selection = selection
        let chosen = UsageSelection()
        chosen.org = selection?.org
        if let kind = selection?.kind { chosen.kind = kind }
        chosen.lastWeek = lastWeek
        _chosen = StateObject(wrappedValue: chosen)
    }

    var body: some View {
        UsageContent(model: model, actions: .none, chosen: chosen)
            .padding(24)
            .frame(width: width, alignment: .topLeading)
            .background { TideSky(.page) }
    }
}
