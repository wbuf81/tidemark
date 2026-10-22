import AppKit
import SwiftUI
import TidemarkCore

/// One screen in one state, drawn light and dark; `byLook` keeps "-clean" in the file name so
/// pictures line up with earlier renders. `draw` builds its state from the stage.
struct Shot {
    var screen: String
    var state: String
    /// One line on what it shows, for index.md.
    var about: String
    var byLook = true
    var draw: @MainActor (_ dark: Bool) -> NSBitmapImageRep?
}

/// Builds the model a shot draws.
typealias RenderMake = () -> AppModel

/// One area's pictures. `Renderer.catalog` lists the providers; each one is a section of index.md.
@MainActor
protocol ShotProvider {
    /// The section's heading in index.md and what the pictures in it have in common.
    static var section: (title: String, about: String) { get }
    @MainActor static func shots(_ stage: RenderStage) -> [Shot]
    /// Text files written beside the pictures: file name to markdown. Providers that name the same
    /// file add to it, in catalog order.
    @MainActor static func notes(_ stage: RenderStage) -> [String: String]
}

extension ShotProvider {
    @MainActor static func notes(_ stage: RenderStage) -> [String: String] { [:] }
}

/// `Tidemark --render DIR` draws every screen and state from the demo data to
/// `DIR/<screen>-<state>-<look>-<light|dark>.png` (without the look where the look doesn't change
/// the screen), then writes `index.md` (every file and what it shows) and each provider's text
/// files beside them, and exits. SwiftUI screens are drawn with `ImageRenderer`; AppKit windows
/// (Settings, the alerts, sign-in, the main window) are built for real and drawn offscreen
/// (`Offscreen`), never shown. Settings live in a throwaway suite and history in a temporary
/// folder, both removed after; the owner's settings, history, Claude Code files and claude.ai
/// session are never read.
@MainActor
enum Renderer {
    /// Every provider, in the order of index.md.
    static let catalog: [ShotProvider.Type] = [
        WidgetShots.self, NotchShots.self, UsageShots.self, DetailsShots.self, WindowShots.self,
        SettingsShots.self, ShellShots.self, SharedShots.self, ReadmeShots.self,
    ]

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stage = RenderStage()
        defer { stage.cleanUp() }
        var sections: [(title: String, about: String, lines: [String])] = []
        var failed: [String] = []
        var texts: [(name: String, text: String)] = []
        for provider in catalog {
            var lines: [String] = []
            for shot in provider.shots(stage) {
                for look in [shot.byLook ? "clean" : nil] {
                    for dark in [false, true] {
                        let name = [shot.screen, shot.state, look, dark ? "dark" : "light"]
                            .compactMap { $0 }.joined(separator: "-") + ".png"
                        guard let image = shot.draw(dark), write(image, to: dir.appendingPathComponent(name)) else {
                            failed.append(name)
                            continue
                        }
                        if looksBlank(image) { print("warning: \(name) looks blank") }
                        let variant = [dark ? "dark" : "light"].compactMap { $0 }.joined(separator: ", ")
                        lines.append("- `\(name)`: \(shot.about) (\(variant))")
                    }
                }
            }
            let section = provider.section
            sections.append((section.title, section.about, lines))
            for (name, text) in provider.notes(stage).sorted(by: { $0.key < $1.key }) {
                if let i = texts.firstIndex(where: { $0.name == name }) { texts[i].text += text }
                else { texts.append((name, text)) }
            }
        }
        let count = sections.map(\.lines.count).reduce(0, +)
        writeText(index(sections, count: count, notes: texts.map(\.name), failed: failed), to: dir.appendingPathComponent("index.md"))
        for (name, text) in texts { writeText(text, to: dir.appendingPathComponent(name)) }
        for name in failed { print("warning: couldn't draw \(name)") }
        print("Rendered \(count) pictures to \(dir.path)")
    }

    // MARK: Drawing

    /// A SwiftUI view at its own size, drawn with solid cards and still effects, at 2×.
    static func picture<V: View>(_ view: V, dark: Bool) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.renderStyle, .showcase))
        renderer.scale = 2
        return renderer.cgImage.map { NSBitmapImageRep(cgImage: $0) }
    }

    private static func write(_ image: NSBitmapImageRep, to url: URL) -> Bool {
        guard let data = image.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private static func writeText(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every sampled pixel the same colour: something didn't draw.
    private static func looksBlank(_ image: NSBitmapImageRep) -> Bool {
        let first = image.colorAt(x: 0, y: 0)
        for y in stride(from: 0, to: image.pixelsHigh, by: max(image.pixelsHigh / 48, 1)) {
            for x in stride(from: 0, to: image.pixelsWide, by: max(image.pixelsWide / 48, 1)) where image.colorAt(x: x, y: y) != first {
                return false
            }
        }
        return true
    }

    // MARK: index.md

    private static func index(_ sections: [(title: String, about: String, lines: [String])], count: Int,
                              notes: [String], failed: [String]) -> String {
        let links = notes.sorted().map { "[\($0)](\($0))" }.joined(separator: " and ")
        var text = """
            # Tidemark renders

            \(count) pictures from `Tidemark --render`: every screen and state, from the invented demo data, \
            at a fixed moment (Wednesday 21 Oct 2026, 11:32 AM, in this Mac's time zone and clock style). Files are \
            `<screen>-<state>-<look>-<light|dark>.png`; screens the look doesn't change have no look part. \
            See also \(links): notifications and menus are \
            listed as text, since macOS draws them only on screen.

            Not drawn: the live frosted glass and Core Animation (in-use particles, the \
            notch's breathing glow), which image renders can't show; web pages (claude.ai's sign-in, the week \
            calendar), which get placeholders; menus and notifications, listed instead.

            """
        for section in sections where !section.lines.isEmpty {
            text += "\n## \(section.title)\n\n\(section.about)\n\n" + section.lines.joined(separator: "\n") + "\n"
        }
        if !failed.isEmpty {
            text += "\n## Not drawn this time\n\n" + failed.map { "- `\($0)`" }.joined(separator: "\n") + "\n"
        }
        return text
    }
}

/// Where `--render` builds its states: a throwaway settings suite, a temporary folder for history
/// and files, a fixed clock (the design's moment, Wednesday 21 Oct 2026, 11:32 AM) and the look being
/// drawn. States are built through the model's own entry points: demo mode's `apply`, or the
/// poller's `setAvailableOrgs` and `ingest`.
@MainActor
final class RenderStage {
    let now = DemoCalendar.now   // Wed 21 Oct 2026, 11:32 local
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidemarkRender-\(UUID().uuidString)")
    /// The settings live in a file inside `folder` (a suite named by an absolute path), so a render never writes
    /// to the real home's Preferences and everything goes when `folder` does.
    private lazy var suite = folder.appendingPathComponent("settings").path
    private lazy var defaults = UserDefaults(suiteName: suite)!
    private var history: URL { folder.appendingPathComponent("history.jsonl") }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var scenarios: [DemoScenario] { DemoData.scenarios(now: now) }

    /// A fresh model on fresh settings at `now`, with no history: nothing carries over
    /// from the state before.
    func model() -> AppModel {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: history)
        let settings = Settings(defaults: defaults)
        settings.sourcesChosen = true   // the pictures show a user who has chosen; `week-sources-not-chosen` shows the other
        let model = AppModel(settings: settings, store: HistoryStore(url: history))
        model.now = now
        model.widgetHeight = 82
        return model
    }

    /// Demo mode's path: `scenario` applied, without the week calendar unless `week` is given.
    func demo(_ scenario: DemoScenario, week: WeekSummary? = nil) -> AppModel {
        let model = model()
        model.apply(scenario)
        model.showWeek(week)
        return model
    }

    /// A demo scenario of its own: `orgs` (the first shared with the desktop app, and Claude
    /// Code's unless `claudeCode` says otherwise) and their readings.
    func scenario(_ orgs: [Org], _ readings: [Reading], claudeCode: Org? = nil, working: Bool = false,
                  codeMood: CodeMood? = .tool) -> DemoScenario {
        DemoScenario(name: "render", orgs: orgs, primary: orgs[0].id, readings: readings,
                     claudeCodeOrg: (claudeCode ?? orgs[0]).id, claudeCodeWorking: working, now: now, codeMood: codeMood)
    }

    /// The poller's path: signed in, the org list read (`hidden` turned off in Settings), then one
    /// refresh round's `outcome`.
    func refreshed(_ orgs: [Org], _ outcome: UsageRound.Outcome, claudeCode: Org? = nil, hidden: [Org] = []) -> AppModel {
        let model = model()
        for org in hidden { model.settings.orgChoices[org.id] = false }
        let claudeCodeOrg = (claudeCode ?? orgs.first)?.id
        model.setAvailableOrgs(orgs, claudeCodeOrg: claudeCodeOrg)
        model.ingest(outcome, claudeCodeOrg: claudeCodeOrg, at: now)
        return model
    }

    /// A reading taken `age` seconds before `now`; resets in hours from now, the week's on the hour.
    func reading(_ org: Org, week: Double, weekReset: Double?, session: Double = 0, sessionReset: Double? = nil,
                 fable: Double = 20, age: TimeInterval = 0) -> Reading {
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        let weekResetsAt = weekReset.map { Date(timeIntervalSince1970: (at($0).timeIntervalSince1970 / 3600).rounded() * 3600) }
        return Reading(time: now.addingTimeInterval(-age), org: org.id, session: session, sessionResetsAt: sessionReset.map(at),
                       week: week, weekResetsAt: weekResetsAt, scoped: ["Fable": fable])
    }

    // MARK: States several screens share

    /// Signed out of claude.ai.
    func signedOut() -> AppModel {
        let model = model()
        model.signedOut()
        return model
    }

    /// Nothing could be read: the refresh failed with `problem` before any org was read.
    func cantRead(_ problem: RefreshProblem) -> AppModel {
        let model = model()
        model.refreshFailed(problem)
        return model
    }

    /// Demo scenario 0 forty minutes on: every reading over 10 minutes old.
    func stale() -> AppModel {
        let model = demo(scenarios[0])
        model.now = now.addingTimeInterval(40 * 60)
        return model
    }

    /// Personal alone, from demo scenario 0.
    var oneOrg: DemoScenario { scenario([DemoData.personal], [scenarios[0].readings[0]]) }

    /// The demo week calendar's week, changed by `change`.
    func week(_ change: (inout WeekSummary) -> Void = { _ in }) -> WeekSummary {
        var week = DemoData.week(now: now)
        change(&week)
        return week
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The desktop behind every scene: the theme's own gradient, never a real wallpaper.
struct ShowcaseWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Palette.page, Palette.page], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
