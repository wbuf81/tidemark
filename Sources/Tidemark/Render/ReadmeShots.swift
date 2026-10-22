import AppKit
import SwiftUI
import TidemarkCore

/// The pictures the README shows (`readme-*`), composed from the real views: the main window and the
/// first-run window drawn offscreen, the widget view itself, and a few plainly illustrative cards for
/// the macOS steps (drawn in Tidemark's palette, never copies of Apple's screens). `scripts/make-readme-images.sh`
/// copies them to docs/images. `readme-gif-N` are the five status frames of widget-status.gif.
enum ReadmeShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The README's pictures", "The pictures docs/images is made from (`readme-*`), at the demo moment: the hero (the window on Week with the widget beside a Dock), the first-run steps, the widget beside the Dock, three illustrative cards for the macOS steps, and one frame per Claude Code status for the status GIF (`readme-gif-0` to `-4`: Idle, Thinking, Working, Needs you, Done). `scripts/make-readme-images.sh` turns them into the files in docs/images.")
    }

    /// The statuses the GIF cycles through, in order.
    static let gifMoods: [CodeMood] = [.idle, .thinking, .tool, .permission, .done]

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        func shot(_ state: String, _ about: String, _ draw: @escaping @MainActor (Bool) -> NSBitmapImageRep?) -> Shot {
            Shot(screen: "readme", state: state, about: about, byLook: false, draw: draw)
        }
        func firstRun(_ step: Int, _ dark: Bool) -> NSBitmapImageRep? {
            let state = FirstRunState()
            state.step = step
            let window = FirstRunController.frame(model: stage.demo(stage.scenarios[0], week: stage.week()), state: state, actions: FirstRunActions())
            guard let image = Offscreen.image(of: window, dark: dark) else { return nil }
            return Renderer.picture(ReadmeFirstRun(window: image), dark: dark)
        }
        var shots: [Shot] = [
            shot("hero", "The README's hero: a desktop on the sky with the menu bar's batteries, the main window on Usage and the widget beside a Dock (980 points wide)") { dark in
                let model = readmePlans(stage, mood: .thinking)
                let window = MainWindowController.frame(model: model, actions: .none, section: .usage)
                guard let image = Offscreen.image(of: window, dark: dark) else { return nil }
                return Renderer.picture(ReadmeHero(window: image, model: readmePlans(stage, mood: .thinking), items: readmeBatteries(), dark: dark), dark: dark)
            },
            shot("step-reads", "First run, step 2 of 4: What Tidemark reads") { firstRun(2, $0) },
            shot("step-plan-limits", "First run, step 3 of 4: Show your plan's limits? with Anthropic's warning") { firstRun(3, $0) },
            shot("step-widget", "The widget beside the Dock") { dark in
                Renderer.picture(ReadmeDockScene(model: stage.mock([.personal], mood: .thinking, week: stage.mockWeek())), dark: dark)
            },
            shot("step-download", "Illustration: the Tidemark icon with an arrow into the Applications folder") { dark in
                Renderer.picture(ReadmeDownload(), dark: dark)
            },
            shot("step-not-opened", "Illustration: an alert-style card, \u{201C}Tidemark\u{201D} Not Opened, with Done and Move to Bin") { dark in
                Renderer.picture(ReadmeNotOpened(), dark: dark)
            },
            shot("step-open-anyway", "Illustration: a Privacy & Security row, \u{201C}Tidemark\u{201D} was blocked, with Open Anyway highlighted") { dark in
                Renderer.picture(ReadmeOpenAnyway(), dark: dark)
            },
        ]
        for (i, mood) in gifMoods.enumerated() {
            shots.append(shot("gif-\(i)", "Status GIF frame \(i + 1) of \(gifMoods.count): Claude Code \(mood.word) on the plan's chip, plan cards unchanged") { dark in
                let model = stage.mock([.personal, .harbor], mood: mood, week: stage.mockWeek())
                model.hooksConnected = true
                return Renderer.picture(RenderWidgetScene(model: model, width: 560), dark: dark)
            })
        }
        // Click a plan: the widget alone, then its details card open above Harbor Labs.
        for open in [false, true] {
            shots.append(shot("click-\(open ? 1 : 0)", open ? "Click-a-plan GIF frame 2: Harbor Labs's details card open above its slot" : "Click-a-plan GIF frame 1: the widget alone") { dark in
                Renderer.picture(ReadmeClickScene(model: readmePlans(stage, mood: .thinking), open: open), dark: dark)
            })
        }
        // Feature tiles: one size, the subject centred and scaled to fit on the sky.
        func feature(_ name: String, _ about: String, maxScale: CGFloat = 1.6, _ subject: @escaping @MainActor (Bool) -> AnyView) -> Shot {
            shot("feature-\(name)", "Feature tile (880 \u{00D7} 560 points): \(about)") { dark in
                ReadmeTile.draw(subject(dark), dark: dark, maxScale: maxScale)
            }
        }
        func lift<V: View>(_ v: V) -> AnyView { AnyView(v.shadow(color: .black.opacity(0.22), radius: 14, y: 7).padding(24)) }
        shots += [
            feature("tide", "the widget with two plans, tides and the week") { _ in
                lift(WidgetView(model: stage.mock([.personal, .harbor], mood: nil, week: stage.mockWeek()), actions: .none, width: 560).fixedSize())
            },
            feature("status", "Needs you on Personal's chip, Harbor Labs out") { _ in
                let model = stage.mock([.personal, .harborOut], mood: .permission, week: stage.mockWeek())
                model.hooksConnected = true
                return lift(WidgetView(model: model, actions: .none, width: 560).fixedSize())
            },
            feature("battery", "the menu bar's batteries", maxScale: 2.0) { dark in AnyView(ReadmeMenuBar(items: readmeBatteries(), dark: dark).shadow(color: .black.opacity(0.2), radius: 10, y: 5).padding(24)) },
            feature("details", "Harbor Labs's details card") { _ in
                lift(ReadmeDetailsCard(model: readmePlans(stage, mood: .thinking), orgID: DemoData.harbor.id))
            },
            feature("usage", "the Usage page, top of the page") { _ in
                let model = stage.mock([MockPlan.personal.withFable(31), MockPlan.harbor.withFable(6)], mood: nil, claudeCode: DemoData.harbor)
                return lift(RenderUsageScene(model: model, width: 980, selection: nil)
                    .frame(height: 740, alignment: .top).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5)))
            },
            feature("week", "the Week section") { dark in
                let model = stage.mock([.personal, .harbor], mood: nil)
                let window = MainWindowController.frame(model: model, actions: .none, section: .week, calendar: DemoCalendar.store(), now: { stage.now })
                guard let image = Offscreen.image(of: window, dark: dark) else { return AnyView(EmptyView()) }
                return AnyView(ReadmeWindowImage(image, width: image.size.width).padding(24))
            },
            feature("report", "the weekly report, written by Claude Code", maxScale: 1.4) { _ in
                let demo = DemoCalendar.store()
                let week = demo.week(containing: stage.now.addingTimeInterval(-7 * 86400), weekStart: .monday, now: stage.now)
                let model = ReportModel(week: week, settings: stage.model().settings, store: demo, actions: .none, now: { stage.now }, tab: .claude, phase: .idle)
                return lift(ReportCard(model: model).frame(width: 560)
                    .background(Palette.tile)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            },
            feature("trends", "Trends, eight weeks by project") { dark in
                let settings = stage.model().settings
                settings.weekStart = .monday
                let model = TrendsPaneModel(store: DemoCalendar.store(), settings: settings, now: { DemoCalendar.now })
                guard let image = readmePane(TrendsPane(model: model, onOpenWeek: { _ in }), size: NSSize(width: 960, height: 300), dark: dark) else { return AnyView(EmptyView()) }
                return AnyView(ReadmeWindowImage(image, width: image.size.width).padding(24))
            },
            feature("notch", "the open notch, cut to the screen's corner", maxScale: 1.8) { _ in
                let model = stage.mock([.personal, .harbor], mood: .thinking)
                model.settings.notchLook = .hardware
                // The tile is 590 points wide with the open notch at its right end: keep only the part that hangs
                // from the screen's top edge, not the black shoulder to its left.
                return AnyView(NotchTile(model: model, open: true)
                    .offset(x: -170)
                    .frame(width: 420, height: 116, alignment: .topLeading)
                    .background(ReadmeSky())
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6).padding(24))
            },
            feature("private", "first run's What Tidemark reads", maxScale: 1.3) { dark in
                let state = FirstRunState()
                state.step = 2
                let window = FirstRunController.frame(model: stage.demo(stage.scenarios[0], week: stage.week()), state: state, actions: FirstRunActions())
                guard let image = Offscreen.image(of: window, dark: dark) else { return AnyView(EmptyView()) }
                return AnyView(ReadmeWindowImage(image, width: image.size.width).padding(24))
            },
        ]
        return shots
    }
}

// MARK: Pieces

/// The soft desktop behind the README's pictures: one gradient per look, never a real wallpaper.
struct ReadmeDesktop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.07, green: 0.10, blue: 0.15), Color(red: 0.09, green: 0.19, blue: 0.23), Color(red: 0.15, green: 0.13, blue: 0.20)]
                       : [Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.84, green: 0.90, blue: 0.95), Color(red: 0.96, green: 0.92, blue: 0.91)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The README's sample plans (Personal 58%, Harbor Labs 81%) and week, as every widget picture draws them.
@MainActor func readmePlans(_ stage: RenderStage, mood: CodeMood?) -> AppModel {
    stage.mock([.personal, .harbor], mood: mood, week: stage.mockWeek())
}

/// The menu bar's batteries for the same plans: Personal 42% left, Harbor Labs 19% left and running out early.
func readmeBatteries() -> [MenuBarBatteries.Item] {
    MenuBarBatteries.make([MenuBarBatteries.Plan(id: "personal", name: "Personal", weekUsed: 58, state: .fine, isOld: false),
                           MenuBarBatteries.Plan(id: "harbor", name: "Harbor Labs", weekUsed: 81, state: .runsOutEarly, isOld: false)],
                          limitsOn: true, names: .names)
}

/// A pane built for real in an offscreen borderless window, so its controls draw.
@MainActor func readmePane<V: View>(_ view: V, size: NSSize, dark: Bool) -> NSBitmapImageRep? {
    let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height).background(Palette.tile))
    host.sizingOptions = []
    let window = NSWindow(contentViewController: host)
    window.styleMask = [.borderless]
    window.setContentSize(size)
    return Offscreen.image(of: window, dark: dark, chrome: false)
}

/// The sky behind the feature tiles and the hero: the widget's dawn or dusk gradient.
struct ReadmeSky: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = TidePalette.for(scheme)
        LinearGradient(stops: [.init(color: p.sky1, location: 0), .init(color: p.sky2, location: 0.55), .init(color: p.sky3, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Every feature tile is 880 \u{00D7} 560 points: the subject is measured, then scaled to fit with room round it, never past `maxScale`.
enum ReadmeTile {
    static let size = CGSize(width: 880, height: 560)

    @MainActor static func draw(_ subject: AnyView, dark: Bool, maxScale: CGFloat) -> NSBitmapImageRep? {
        guard let probe = Renderer.picture(subject.fixedSize(), dark: dark), probe.pixelsWide > 0 else { return nil }
        let w = CGFloat(probe.pixelsWide) / 2, h = CGFloat(probe.pixelsHigh) / 2
        let scale = min((size.width - 56) / w, (size.height - 56) / h, maxScale)
        let tile = ZStack {
            ReadmeSky()
            subject.fixedSize().scaleEffect(scale)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        return Renderer.picture(tile, dark: dark)
    }
}

/// The right end of a menu bar with the plans' batteries.
struct ReadmeMenuBar: View {
    var items: [MenuBarBatteries.Item]
    var dark: Bool
    var body: some View {
        let ink = dark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.07, green: 0.07, blue: 0.07)
        HStack(spacing: 15) {
            ForEach(items, id: \.id) { item in
                Image(nsImage: MenuBarIcon.batteryTitleImage(item, dark: dark)).accessibilityLabel(item.accessibility)
            }
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            Text("11:32").font(.system(size: 13))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14).frame(height: 28)
        .background(dark ? Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.6) : Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A plan's details card from the model, as the panel draws it.
struct ReadmeDetailsCard: View {
    @ObservedObject var model: AppModel
    let orgID: String
    var body: some View {
        if let org = model.orgs.first(where: { $0.id == orgID }), let reading = model.latest[orgID] {
            PlanDetailsView(name: org.name,
                            details: PlanDetails.make(reading: reading.adjusted(to: model.now), history: model.history, now: model.now,
                                                      formatting: model.formatting, thresholds: model.settings.thresholds, isOld: model.isOld(org)),
                            formatting: model.formatting, isOld: model.isOld(org))
        }
    }
}

/// The click-a-plan frames: the widget at the bottom, Harbor Labs's card above its slot when `open`; both the same size.
struct ReadmeClickScene: View {
    @ObservedObject var model: AppModel
    var open: Bool
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Color.clear.frame(width: 560, height: 600)
                if open {
                    ReadmeDetailsCard(model: model, orgID: DemoData.harbor.id)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                        .padding(.leading, 232 + 116 - 150)
                }
            }
            WidgetView(model: model, actions: .none, width: 560).fixedSize()
        }
        .padding(24)
        .background(ShowcaseWallpaper())
    }
}

/// A drawn window picture, rounded and lifted off the desktop.
struct ReadmeWindowImage: View {
    let rep: NSBitmapImageRep
    let width: CGFloat
    init(_ rep: NSBitmapImageRep, width: CGFloat) { self.rep = rep; self.width = width }
    var body: some View {
        let ratio = CGFloat(rep.pixelsHigh) / CGFloat(rep.pixelsWide)
        Group {
            if let cg = rep.cgImage {
                Image(decorative: cg, scale: 1).resizable().interpolation(.high)
            } else { Color.clear }
        }
        .frame(width: width, height: width * ratio)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

/// A first-run step: the window itself, drawn as it is, on the desktop gradient.
struct ReadmeFirstRun: View {
    let window: NSBitmapImageRep
    var body: some View {
        ReadmeWindowImage(window, width: window.size.width)
            .padding(32)
            .background(ReadmeDesktop())
    }
}

/// Tidemark's icon (Resources/icon/tidemark.svg), drawn.
struct ReadmeIcon: View {
    var size: CGFloat
    var body: some View {
        let k = size / 824   // the svg's tile is 824 of 1024 units
        ZStack {
            RoundedRectangle(cornerRadius: 185 * k, style: .continuous)
                .fill(Color(red: 0.949, green: 0.965, blue: 0.976))
                .shadow(color: .black.opacity(0.22), radius: 6 * size / 100, y: 3 * size / 100)
            IconInner(size: size)
        }
        .frame(width: size, height: size)
    }
}

private struct IconInner: View {
    var size: CGFloat
    var body: some View {
        let u = size / 128   // the tile is 128 units across
        ZStack {
            Circle().stroke(Color(red: 0.835, green: 0.882, blue: 0.918), lineWidth: 14 * u).frame(width: 76 * u, height: 76 * u)
            Circle().trim(from: 0, to: 167.0 / 238.76)
                .rotation(.degrees(-90))
                .stroke(Color(red: 0.122, green: 0.498, blue: 0.651), style: StrokeStyle(lineWidth: 14 * u, lineCap: .round))
                .frame(width: 76 * u, height: 76 * u)
            Circle().fill(Color(red: 0.902, green: 0.937, blue: 0.961)).frame(width: 52 * u, height: 52 * u)
            ScaledShape(box: 128) { p in
                p.move(to: CGPoint(x: 38, y: 70))
                p.addCurve(to: CGPoint(x: 64, y: 70), control1: CGPoint(x: 46, y: 65), control2: CGPoint(x: 54, y: 75))
                p.addCurve(to: CGPoint(x: 90, y: 70), control1: CGPoint(x: 74, y: 65), control2: CGPoint(x: 82, y: 65))
                p.svgArc(to: CGPoint(x: 38, y: 70), r: 26)
                p.closeSubpath()
            }
            .fill(Color(red: 0.247, green: 0.655, blue: 0.788))
            .frame(width: size, height: size)
            .mask(Circle().frame(width: 52 * u, height: 52 * u))
        }
        .frame(width: size, height: size)
    }
}

/// A Dock: a rounded bar of plain app tiles and Tidemark's icon, drawn for the picture.
struct ReadmeDock: View {
    @Environment(\.colorScheme) private var scheme
    var count = 5
    var body: some View {
        let all: [[Color]] = [
            [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.20, green: 0.40, blue: 0.85)],
            [Color(red: 0.95, green: 0.70, blue: 0.35), Color(red: 0.90, green: 0.45, blue: 0.25)],
            [Color(red: 0.45, green: 0.80, blue: 0.55), Color(red: 0.20, green: 0.60, blue: 0.40)],
            [Color(red: 0.70, green: 0.55, blue: 0.90), Color(red: 0.45, green: 0.35, blue: 0.80)],
            [Color(red: 0.62, green: 0.66, blue: 0.72), Color(red: 0.40, green: 0.44, blue: 0.50)],
        ]
        let tiles = Array(all.prefix(count))
        HStack(spacing: 9) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: c, startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
            }
            ReadmeIcon(size: 44)
            Capsule().fill(Palette.dim.opacity(0.4)).frame(width: 1, height: 36)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.80, green: 0.83, blue: 0.87), Color(red: 0.62, green: 0.67, blue: 0.73)], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85), lineWidth: 1))
    }
}

/// The Dock with the widget beside it, as the app lays them out.
struct ReadmeDockRow: View {
    @ObservedObject var model: AppModel
    var widgetWidth: CGFloat = 330
    var dockTiles = 5
    var body: some View {
        HStack(spacing: 14) {
            ReadmeDock(count: dockTiles)
            WidgetView(model: model, actions: .none, width: widgetWidth).fixedSize()
        }
    }
}

struct ReadmeDockScene: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ReadmeDockRow(model: model)
            .padding(.horizontal, 28).padding(.top, 52).padding(.bottom, 24)
            .background(ReadmeDesktop())
    }
}

struct ReadmeHero: View {
    let window: NSBitmapImageRep
    @ObservedObject var model: AppModel
    var items: [MenuBarBatteries.Item]
    var dark: Bool
    var body: some View {
        let ink = dark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.07, green: 0.07, blue: 0.07)
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View"], id: \.self) { Text($0).font(.system(size: 13)) }
                Spacer(minLength: 20)
                ForEach(items, id: \.id) { Image(nsImage: MenuBarIcon.batteryTitleImage($0, dark: dark)) }
                Text("Wed 21 Oct  11:32").font(.system(size: 13))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14).frame(height: 28)
            .background(dark ? Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.55) : Color.white.opacity(0.55))
            Spacer().frame(height: 30)
            ReadmeWindowImage(window, width: 800)
            Spacer().frame(height: 30)
            ReadmeDockRow(model: model, widgetWidth: 560, dockTiles: 3)
            Spacer().frame(height: 24)
        }
        .frame(width: 980)
        .background(ReadmeSky())
    }
}

/// "Illustration" in a corner, so no picture here is taken for a screenshot of macOS.
private struct IllustrationTag: View {
    var body: some View {
        Text("Illustration")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Palette.dim)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Palette.tile.opacity(0.8)))
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

private struct Pill: View {
    let text: String
    var primary = false
    var halo = false
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Palette.fg)
            .padding(.horizontal, 16).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(primary ? Palette.blue : Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(primary ? Color.clear : Palette.track, lineWidth: 1))
            .padding(halo ? 5 : 0)
            .overlay(halo ? RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.blue.opacity(0.55), lineWidth: 2.5) : nil)
    }
}

struct ReadmeDownload: View {
    var body: some View {
        HStack(spacing: 34) {
            VStack(spacing: 10) {
                ReadmeIcon(size: 104)
                Text("Tidemark").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.bright)
            }
            VStack(spacing: 6) {
                Text("Drag").font(.system(size: 12)).foregroundStyle(Palette.dim)
                ZStack {
                    Capsule().fill(Palette.blue).frame(width: 110, height: 4)
                    Path { p in
                        p.move(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 22, y: 12)); p.addLine(to: CGPoint(x: 8, y: 24))
                    }
                    .stroke(Palette.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24).offset(x: 46)
                }
                .frame(width: 130, height: 24)
            }
            VStack(spacing: 10) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.36, green: 0.62, blue: 0.95).opacity(0.75))
                        .frame(width: 52, height: 22).offset(x: -26, y: -8)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.72, blue: 0.98), Color(red: 0.25, green: 0.52, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 112, height: 88)
                }
                .frame(width: 112, height: 96, alignment: .bottom)
                Text("Applications").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.bright)
            }
        }
        .padding(.horizontal, 54).padding(.vertical, 48)
        .frame(width: 640)
        .background(ReadmeDesktop())
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}

struct ReadmeNotOpened: View {
    var body: some View {
        ZStack {
            ReadmeDesktop()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    ReadmeIcon(size: 64)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\u{201C}Tidemark\u{201D} Not Opened")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bright)
                        Text("Apple could not verify \u{201C}Tidemark\u{201D} is free of malware that may harm your Mac or compromise your privacy.")
                            .font(.system(size: 13)).foregroundStyle(Palette.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Pill(text: "Move to Bin")
                    Pill(text: "Done", primary: true)
                }
                .padding(.top, 20)
            }
            .padding(22)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        }
        .frame(width: 640, height: 250)
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}

struct ReadmeOpenAnyway: View {
    var body: some View {
        ZStack {
            ReadmeDesktop()
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy & Security")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.bright)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                Rectangle().fill(Palette.line).frame(height: 0.5)
                Text("Security").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.dim)
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
                HStack(spacing: 12) {
                    Text("\u{201C}Tidemark\u{201D} was blocked to protect your Mac.")
                        .font(.system(size: 13)).foregroundStyle(Palette.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Pill(text: "Open Anyway", primary: true, halo: true)
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        }
        .frame(width: 640, height: 220)
        .overlay(IllustrationTag().padding(12), alignment: .bottomTrailing)
    }
}
