import AppKit
import SwiftUI
import TidemarkCore

/// What the app puts around its windows: consent sheets, alerts, first run, the sign-in window, the
/// menu bar icon and the menus.
enum ShellShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("Sheets, first run and the menu bar", "The real consent sheets (`sheet-*`), built by the same views the app presents and drawn offscreen at their own size on the window background, in rounded corners; the hooks failure alert (`alert-*`) built by the function the app calls and never run; first run's four steps in their one window (`firstrun-*`); the sign-in window's native parts with a placeholder where claude.ai's page loads (`signin-window`: the render makes no web view and never opens the website data); and the menu bar icon at 18 points on a menu bar strip (`menubar-icon`). Menus are listed as text in menus.md. Folders and files shown come from a temporary home, never a real one.")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        sheetShots(stage) + alertShots(stage) + firstRunShots(stage) + signInShots(stage) + menuBarShots(stage)
    }

    // MARK: Sheets

    /// A sheet's view drawn at its own size on the window background, in the sheet's rounded corners.
    private static func sheet<V: View>(_ state: String, _ about: String, _ make: @escaping () -> V) -> Shot {
        Shot(screen: "sheet", state: state, about: about, byLook: false) { dark in
            let window = SheetPresenter.offscreenWindow(make())
            return Offscreen.image(of: window, dark: dark, chrome: false)
                .flatMap { Offscreen.onBackground($0, dark: dark, radius: 12) }
        }
    }

    /// The uninstall list as the inventory gives it for the stage's temporary home; stand-in lines
    /// when it gives none yet.
    private static func inventory(_ stage: RenderStage) -> [DataItem] {
        let items = DataInventory.items(home: stage.folder, environment: [:])
        if !items.isEmpty { return items }
        let support = AppIdentity.supportURL(home: stage.folder)
        return [
            DataItem(path: AppIdentity.calendarURL(home: stage.folder), what: "Your calendar, names and reports", removedBy: [.deleteAll, .uninstall]),
            DataItem(path: support.appendingPathComponent("history.jsonl"), what: "Your usage history", removedBy: [.deleteAll, .uninstall]),
            DataItem(path: stage.folder.appendingPathComponent("Library/Preferences/\(AppIdentity.bundleID).plist"), what: "Tidemark’s settings", removedBy: [.deleteAll, .uninstall]),
            DataItem(path: stage.folder.appendingPathComponent(".claude/settings.json"), what: "Tidemark’s hooks in Claude Code’s settings", removedBy: [.uninstall]),
        ]
    }

    private static func sheetShots(_ stage: RenderStage) -> [Shot] {
        let folder = URL(fileURLWithPath: "/Users/you/Documents/Cowork")
        func cowork(_ last: Date?, folder: URL?) -> CoworkLogSheet {
            let state = CoworkLogModel(folder: folder, lastEntry: { _ in last }, formatting: Formatting(), now: stage.now)
            return CoworkLogSheet(state: state, instruction: CoworkInstruction.text(folderName: AppIdentity.coworkLogFolderName),
                                  cancel: {}, copy: {}, choose: {})
        }
        let found = LegacyFound(weeks: 39, first: "2026-01-26", last: "2026-10-19", hasNames: true, hasReports: true)
        return [
            sheet("plan-limits", "Turn on plan limits?: what turning claude.ai reading on means, Anthropic's warning in plain words, neither button the default") {
                PlanLimitsSheet(cancel: {}, confirm: {})
            },
            sheet("cowork-log", "Log Cowork tasks for Tidemark: no folder chosen yet; Choose folder… is the default") { cowork(nil, folder: nil) },
            sheet("cowork-log-waiting", "A folder chosen: Waiting for Cowork’s first log line…") { cowork(nil, folder: folder) },
            sheet("cowork-log-works", "Cowork has logged a task: Logging works · last task 10:42 AM") {
                cowork(stage.now.addingTimeInterval(-50 * 60), folder: folder)
            },
            sheet("hooks", "Show what Claude Code is doing?: exactly what Add hooks writes, and that a copy is kept first") {
                HooksSheet(state: .notConnected, notNow: {}, proceed: {})
            },
            sheet("hooks-update", "The same sheet when the hooks are outdated: the button says Update hooks") {
                HooksSheet(state: .outdated, notNow: {}, proceed: {})
            },
            sheet("delete-all", "Delete all of Tidemark’s data?: what goes and what doesn't; Delete everything is red and never the default") {
                DeleteAllSheet(cancel: {}, export: {}, delete: {})
            },
            sheet("uninstall", "Uninstall Tidemark?: every item from the data inventory, and that the app itself goes to the Bin by hand") {
                UninstallSheet(items: inventory(stage), home: stage.folder, cancel: {}, export: {}, uninstall: {})
            },
            sheet("import", "Import your week calendar?: the found counts and range") {
                ImportSheet(found: found, notNow: {}, importAll: {})
            },
            sheet("notifications", "Get notified?: what Tidemark would tell you, before macOS asks") {
                NotificationsSheet(notNow: {}, proceed: {})
            },
            sheet("sign-out", "Sign out of claude.ai?: what signing out forgets and what stays; Sign out is red and never the default") {
                SignOutSheet(cancel: {}, signOut: {})
            },
            sheet("dock-access", "Measure the Dock exactly?: what the Accessibility permission is for; Open System Settings is the default") {
                DockAccessSheet(cancel: {}, proceed: {})
            },
        ]
    }

    // MARK: Alerts

    /// An alert's content laid out and drawn on the window background (the glass behind it draws as
    /// plain white in a bitmap), in the alert's rounded corners.
    private static func alert(_ state: String, _ about: String, _ make: @escaping () -> NSAlert?) -> Shot {
        Shot(screen: "alert", state: state, about: about, byLook: false) { dark in
            guard let alert = make() else { return nil }
            // The app's icon. A `.build` run has none, so its alerts would show the build folder's;
            // they get macOS's generic app icon, which is what the bundled app has.
            if Bundle.main.bundleIdentifier == nil { alert.icon = NSWorkspace.shared.icon(for: .applicationBundle) }
            alert.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            alert.layout()
            return Offscreen.image(of: alert.window, dark: dark, chrome: false)
                .flatMap { Offscreen.onBackground($0, dark: dark, radius: 12) }
        }
    }

    private static func alertShots(_ stage: RenderStage) -> [Shot] {
        /// The error a real hook file gives for a Claude Code settings file that isn't plain JSON, made
        /// in the stage's folder: nothing is written then.
        func hookError() -> Error? {
            let folder = stage.folder.appendingPathComponent("claude-code")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let settings = folder.appendingPathComponent("settings.json")
            try? Data("{ \"hooks\": { }, // a comment\n}".utf8).write(to: settings)
            let file = ClaudeCodeHookFile(settings: settings, support: folder.appendingPathComponent("support"))
            do { try file.update() } catch { return error }
            return nil
        }
        return [
            alert("hooks-failed", "Couldn’t change ~/.claude/settings.json: the file isn't plain JSON, so it was left alone; Show in Finder") {
                hookError().map { HooksFailureAlert.make(reason: HooksFailureAlert.reason($0)) }
            },
            alert("hooks-failed-other", "Any other failure gets macOS's own words: here, no permission to write the settings file") {
                HooksFailureAlert.make(reason: HooksFailureAlert.reason(CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "settings.json"])),
                                       unreadable: false)
            },
        ]
    }

    // MARK: First run

    private static func firstRunShots(_ stage: RenderStage) -> [Shot] {
        let abouts = [
            "Step 1 of 4, Welcome: what Tidemark shows, in three lines",
            "Step 2 of 4, What Tidemark reads: a checkbox per source (first messages off, Cowork waits for a log folder)",
            "Step 3 of 4, Show your plan’s limits?: Anthropic's warning; Not now and Turn on and sign in… equal, neither the default",
            "Step 4 of 4, You’re set: the live widget preview",
        ]
        let alone = Shot(screen: "firstrun", state: "sources-alone", about: "What Tidemark reads on its own, from Week’s “Choose sources” or Settings → Week: the same step with no step count, no Back, and Continue chooses and closes", byLook: false) { dark in
            let model = stage.demo(stage.scenarios[0], week: stage.week())
            let state = FirstRunState()
            state.step = 2
            state.sourcesOnly = true
            let window = FirstRunController.frame(model: model, state: state, actions: FirstRunActions())
            window.title = ShellCopy.firstRunReadsTitle
            return Offscreen.image(of: window, dark: dark)
        }
        let steps = (1...4).map { step in
            Shot(screen: "firstrun", state: "\(step)", about: abouts[step - 1], byLook: false) { dark in
                let model = stage.demo(stage.scenarios[0], week: stage.week())
                let state = FirstRunState()
                state.step = step
                let window = FirstRunController.frame(model: model, state: state, actions: FirstRunActions())
                return Offscreen.image(of: window, dark: dark)
            }
        }
        return steps + [alone]
    }

    // MARK: Sign-in window, menu bar icon

    private static func signInShots(_ stage: RenderStage) -> [Shot] {
        [
            Shot(screen: "signin", state: "window", about: "The sign-in window at its first size, with a placeholder where claude.ai's sign-in page loads",
                 byLook: false) { dark in
                let page = NSHostingView(rootView: RenderWebPlaceholder(text: "claude.ai's sign-in page loads here.\nRenders never open it."))
                return Offscreen.image(of: SignInWindow.make(page: page, target: nil, openLink: nil), dark: dark)
            },
            Shot(screen: "signin", state: "window-narrow", about: "The sign-in window at its smallest (480 × 560): the hint wraps to more lines instead of clipping",
                 byLook: false) { dark in
                let page = NSHostingView(rootView: RenderWebPlaceholder(text: "claude.ai's sign-in page loads here.\nRenders never open it."))
                let window = SignInWindow.make(page: page, target: nil, openLink: nil)
                window.setContentSize(SignInWindow.minSize)
                return Offscreen.image(of: window, dark: dark)
            },
        ]
    }

    private static func menuBarShots(_ stage: RenderStage) -> [Shot] {
        [
            Shot(screen: "menubar", state: "icon", about: "The menu bar icon (a ring with a water line) at 18 points on a menu bar strip, and 4× larger beside it",
                 byLook: false) { dark in
                Renderer.picture(MenuBarStrip(), dark: dark)
            },
            batteryShot("batteries-names", "A battery per plan with names: Personal fine (ink fill, 42% left), Harbor Labs running out early (amber fill and %)",
                        names: .names, [("personal", "Personal", 58, .fine, false), ("harbor", "Harbor Labs", 81, .runsOutEarly, false)]),
            batteryShot("batteries-letters", "First letters, for a notched MacBook: P fine; H out (empty battery with a red dash, red \"Out\")",
                        names: .letters, [("personal", "Personal", 58, .fine, false), ("harbor", "Harbor Labs", 100, .out, false)]),
            batteryShot("batteries-out", "With names, one plan out: red \"Out\" and an empty red battery",
                        names: .names, [("personal", "Personal", 58, .fine, false), ("harbor", "Harbor Labs", 100, .out, false)]),
            batteryShot("batteries-old", "Old readings: the batteries dim to half",
                        names: .names, [("personal", "Personal", 58, .fine, true), ("harbor", "Harbor Labs", 81, .runsOutEarly, true)]),
        ]
    }

    private typealias BatteryPlan = (id: String, name: String, used: Double, state: PlanState, old: Bool)

    private static func batteryShot(_ state: String, _ about: String, names: PlanNameStyle, _ plans: [BatteryPlan]) -> Shot {
        let items = MenuBarBatteries.make(plans.map { MenuBarBatteries.Plan(id: $0.id, name: $0.name, weekUsed: $0.used, state: $0.state, isOld: $0.old) },
                                          limitsOn: true, names: names)
        return Shot(screen: "menubar", state: state, about: about) { dark in
            Renderer.picture(BatteryBar(items: items, dark: dark), dark: dark)
        }
    }

    // MARK: Menus as text

    @MainActor static func notes(_ stage: RenderStage) -> [String: String] {
        ["menus.md": menus(stage)]
    }

    private static func block(_ title: String, _ entries: [ShellCopy.MenuEntry]) -> String {
        "### \(title)\n\n" + ShellCopy.lines(entries).map { $0 == "-" ? "- ---" : "- \($0)" }.joined(separator: "\n") + "\n\n"
    }

    private static func menus(_ stage: RenderStage) -> String {
        var text = "\n## The menu bar\n\nA line `---` is a separator. Active while Tidemark's window or Settings is open (Tidemark has a Dock icon then).\n\n"
        for (title, entries) in ShellCopy.mainMenus { text += block(title, entries) }
        text += "## The menu bar icon's menu\n\nShown when Settings → General → Menu bar is Tidemark icon, with plan limits off, or while no plan has been read (a right click on a battery opens the same menu). The first lines are disabled: one per plan (a state mark, then the plan's line), Claude Code's status when it has one.\n\n"
        let actions = ShellCopy.lines(ShellCopy.statusMenu(widgetHidden: false)).map { $0 == "-" ? "- ---" : "- \($0)" }.joined(separator: "\n")
        let limitsOn = stage.demo(stage.scenarios[0])
        limitsOn.settings.planLimits = true
        // Not demo data (which would list its plans): the model a user with plan limits off has, and a week.
        let limitsOff = stage.mock([], mood: .tool, week: stage.mockWeek())
        limitsOff.settings.planLimits = false
        text += "### With plan limits on (demo plans)\n\n"
            + StatusItemController.infoLines(limitsOn).map { "- \($0.text)" }.joined(separator: "\n") + "\n- ---\n\(actions)\n\n"
        text += "### With plan limits off\n\nNo plans to list, so the week stands in.\n\n"
            + StatusItemController.infoLines(limitsOff).map { "- \($0.text)" }.joined(separator: "\n") + "\n- ---\n\(actions)\n\n"
        text += "### While the widget is hidden\n\nThe third action reads \"Show the widget\".\n\n"
        text += "## Settings' pop-up menus\n\nEach picker in the Settings window, its items in order, and when it shows.\n\n| Tab → Picker | Items | Shows |\n| --- | --- | --- |\n"
        let pickers: [(String, String, String)] = [
            ("General → Show as", "Always", DisplayMode.allCases.map(\.title).joined(separator: ", ")),
            ("General → Theme", "Always", ThemeChoice.allCases.map(\.title).joined(separator: ", ")),
            ("Widget → Position", "Show as Widget. \(WidgetTab.draggedSpot) comes first only while the widget sits where it was dragged",
             ([WidgetTab.draggedSpot] + SnapPoint.allCases.map { WidgetView.title($0) }).joined(separator: ", ")),
            ("Widget → Layout", "Show as Widget", WidgetTab.layouts.map(\.1).joined(separator: ", ")),
            ("Widget → Shape", "Show as Notch", WidgetTab.notchShapes.map(\.1).joined(separator: ", ")),
            ("Widget → Place", "Show as Notch", WidgetTab.notchPlaces.map(\.1).joined(separator: ", ")),
            ("Widget → Opens to", "Show as Notch", WidgetTab.notchSizes.map(\.1).joined(separator: ", ")),
            ("Widget → Text size", "Always (widget and notch)", WidgetView.sizes.map(\.0).joined(separator: ", ")),
            ("Widget → In-use effect", "Show as Widget", EffectStyle.allCases.map { WidgetView.title($0) }.joined(separator: ", ")),
            ("Widget → Amount", "Show as Widget", EffectAmount.allCases.map { WidgetView.title($0) }.joined(separator: ", ")),
            ("Plans → Shared with the desktop app", "With two or more plans shown; it lists the shown plans", [DemoData.personal, DemoData.harbor].map(\.name).joined(separator: ", ")),
            ("Week → Week starts on", "Always", WeekTab.weekStarts.map(\.1).joined(separator: ", ")),
            ("Week → Weekly report", "Always", WeekTab.reportModes.map(\.1).joined(separator: ", ")),
            ("Advanced → Status picture", "Always (one choice until GIFs come)", "Built-in"),
        ]
        for (picker, when, items) in pickers { text += "| \(picker) | \(items) | \(when) |\n" }
        return text
    }
}

/// A menu bar strip with the icon in it, and the icon enlarged beside it.
private struct MenuBarStrip: View {
    var body: some View {
        HStack(spacing: 22) {
            HStack(spacing: 14) {
                Text("Tidemark").font(.system(size: 13, weight: .bold))
                Text("File Edit View Window Help").font(.system(size: 13))
                Spacer()
                Image(nsImage: MenuBarIcon.image(size: 18)).renderingMode(.template)
                Text("Wed 21 Oct 11:32").font(.system(size: 13))
            }
            .foregroundStyle(Palette.fg)
            .padding(.horizontal, 12)
            .frame(width: 500, height: 28)
            .background(Palette.page)
            Image(nsImage: MenuBarIcon.image(size: 72)).renderingMode(.template).foregroundStyle(Palette.fg)
        }
        .padding(18)
        .background(Palette.tile)
    }
}

/// Stands in for a web page in renders, saying what loads there, so no web view is ever made.
struct RenderWebPlaceholder: View {
    var text: String

    var body: some View {
        ZStack {
            Color.gray.opacity(0.14)
            VStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 30)).foregroundStyle(.secondary)
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }
}

/// The right end of a menu bar over a wallpaper, with each plan's battery in it (the mockup's `menubar_section`).
private struct BatteryBar: View {
    var items: [MenuBarBatteries.Item]
    var dark: Bool

    var body: some View {
        let ink = dark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.07, green: 0.07, blue: 0.07)
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View"], id: \.self) { Text($0).font(.system(size: 13)) }
                Spacer(minLength: 20)
                ForEach(items, id: \.id) { item in
                    Image(nsImage: MenuBarIcon.batteryTitleImage(item, dark: dark))
                        .accessibilityLabel(item.accessibility)
                }
                Text("Wed 21 Oct  11:32").font(.system(size: 13))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(dark ? Color(red: 0.04, green: 0.05, blue: 0.12).opacity(0.55) : Color.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .frame(width: 660, height: 44)
        .background(LinearGradient(colors: dark ? [Color(red: 0.08, green: 0.09, blue: 0.25), Color(red: 0.23, green: 0.25, blue: 0.65)]
                                                 : [Color(red: 0.75, green: 0.83, blue: 0.93), Color(red: 0.95, green: 0.89, blue: 0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
