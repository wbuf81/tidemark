import AppKit
import SwiftUI
import TidemarkCore

/// The notch, at rest and open.
enum NotchShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The notch", "One fake screen corner with a menu bar, the notch (always black) in the window `NotchPlacement` gives it, at rest or open (as when the pointer rests on it). The advice glow, live a Core Animation layer, is drawn still.")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        let two: RenderMake = { stage.mock([.personal, .harbor], mood: .thinking) }
        let fullSession: RenderMake = {
            var busy = MockPlan.personalBusy
            busy.session = 100
            return stage.mock([busy, .harbor], mood: .tool)
        }
        let states: [(String, String, Bool, RenderMake)] = [
            ("rest", "At rest, two plans: the status glyph, then each plan's ring, shape and week % (214 points)", false, two),
            ("open", "Open (the pointer resting on it): the status and the widget's cards", true, two),
            ("rest-advice", "At rest with switch advice: the arrow and the amber glow", false, { stage.mock([.personalBusy, .harbor], mood: .tool) }),
            ("open-advice", "Open with switch advice: the band beside the plans", true,
             { stage.mock([.personalBusy, .harbor], mood: .tool) }),
            ("rest-advice-red", "At rest with advice while Claude Code's 5-hour window is full: the glow and arrow turn red", false, fullSession),
            ("rest-narrow", "At rest, narrowed to 150 points: rings and shapes only", false,
             { let m = two(); m.settings.notchWidth = 150; return m }),
            ("rest-bars", "At rest, widened to 260 points: the 5-hour hairline too, one width for every plan", false,
             { let m = two(); m.settings.notchWidth = 260; return m }),
            ("rest-widest", "At rest, widest (373 points): each plan's 5-hour %, the urgent plan's in its ink", false,
             { let m = two(); m.settings.notchWidth = 373; return m }),
            ("open-m", "Open, with Opens to set to M", true, { let m = two(); m.settings.notchOpensTo = .m; return m }),
            ("rest-rim", "At rest with the status rim on, in the most urgent colour", false,
             { let m = two(); m.settings.notchRim = true; return m }),
            ("rest-three-plans", "At rest, three plans", false, { stage.mock([.personal, .harbor, .lighthouse], mood: .tool) }),
            ("open-three-plans", "Open, three plans", true, { stage.mock([.personal, .harbor, .lighthouse], mood: .tool) }),
            ("rest-out", "At rest, one plan out, Claude Code needs you", false, { stage.mock([.personal, .harborOut], mood: .permission) }),
            ("rest-unread-plan", "At rest, Harbor Labs couldn't be read: its hollow grey shape, no number", false, {
                stage.mock([.personal, .harbor], mood: .idle, failing: [DemoData.harbor: .refused])
            }),
            ("rest-stale", "At rest, every reading old: hollow shapes, dimmed numbers", false,
             { stage.mock([.personal, .harbor], mood: .idle, readAge: 50 * 60) }),
            ("rest-signed-out", "At rest, signed out: \"Sign in\" in white with a shape", false, { let m = stage.signedOut(); m.settings.planLimits = true; return m }),
            ("open-signed-out", "Open, signed out", true, { let m = stage.signedOut(); m.settings.planLimits = true; return m }),
            ("rest-loading", "At rest, before the first reading: \"Loading…\"", false, { let m = stage.model(); m.settings.planLimits = true; return m }),
            ("rest-offline", "At rest, nothing could be read: \"Offline\"", false, { let m = stage.cantRead(.offline); m.settings.planLimits = true; return m }),
            ("open-offline", "Open, offline: the same word, the message's own words", true, { let m = stage.cantRead(.offline); m.settings.planLimits = true; return m }),
            ("rest-blocked", "At rest, blocked by a bot check: \"Blocked\"", false, { let m = stage.cantRead(.blocked); m.settings.planLimits = true; return m }),
            ("bottom-right-rest", "At rest in the bottom-right corner (Place: Bottom right)", false,
             { let m = two(); m.settings.notchPlace = .bottomRight; return m }),
            ("bottom-right-open", "Open in the bottom-right corner", true,
             { let m = two(); m.settings.notchPlace = .bottomRight; return m }),
        ]
        return WidgetTab.notchShapes.flatMap { look, title in
            states.map { state, about, open, make in
                Shot(screen: "notch", state: "\(look.rawValue)-\(state)", about: "\(title): \(about)") { dark in
                    let model = make()
                    model.settings.notchLook = look
                    return Renderer.picture(NotchTile(model: model, open: open).background(ShowcaseWallpaper()), dark: dark)
                }
            }
        }
    }
}

/// One fake screen corner: a menu bar, and the notch in the window `NotchPlacement` gives it,
/// sized the way `NotchController` sizes it from the settings (at text size 1). At least 590
/// points wide; wider when an open notch needs it.
struct NotchTile: View {
    @ObservedObject var model: AppModel
    let open: Bool
    private let menuBar = 28.0
    private let state = NotchState()
    private let width: Double
    private let height: Double

    init(model: AppModel, open: Bool) {
        self.model = model
        self.open = open
        let settings = model.settings
        let orgs = model.orgs.count, advice = model.advice != nil
        let restWidth = NotchSizing.clampRest(settings.notchWidth, orgs: orgs)
        width = open ? NotchSizing.openWidth(orgs: orgs, size: settings.notchOpensTo, advice: advice, restWidth: restWidth,
                                             status: model.leftStatusMood)
                     : restWidth
        height = open ? NotchSizing.openHeight : NotchSizing.restHeight
        state.open = open
        state.look = settings.notchLook
        state.place = settings.notchPlace
        state.glassSize = CGSize(width: width, height: height)
        state.trailingInset = settings.notchLook == .island ? NotchPlacement.shadowMargin : 0
        state.edgeInset = state.trailingInset
        state.restWidth = restWidth
    }

    var body: some View {
        let tileWidth = max(590, width + 80)
        let screen = CGRect(x: 0, y: 0, width: tileWidth, height: 210)
        let visible = CGRect(x: 0, y: 0, width: tileWidth, height: 210 - menuBar)
        let window = NotchPlacement.frames(size: CGSize(width: width, height: height), place: model.settings.notchPlace,
                                           look: model.settings.notchLook, screen: screen, visible: visible).window
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: menuBar)
            NotchView(model: model, actions: .none, state: state)
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: screen.height - window.maxY)
        }
        // Pinned to the corner: the menu bar along the top, the notch where its frames put it.
        .frame(width: tileWidth, height: 210, alignment: .topLeading)
        .clipped()
    }
}
