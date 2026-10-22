import AppKit
import SwiftUI
import TidemarkCore

/// The Settings window, tab by tab.
enum SettingsShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("Settings", "The real Settings window, one picture per tab and state, drawn offscreen at the tab's full height (on screen a tab taller than the screen has room for scrolls, and flashes its scroll bar). It's never made key or brought in front, so it looks as it does while another app is active: grey switches. Launch at login, hooks and notification permission are drawn from stand-ins; the render never asks macOS or reads any real file.")
    }

    /// One tab of the window the hub builds, in its own window, at the tab's full height.
    private static func tabShot(_ tab: SettingsTab, _ state: String, _ about: String,
                                _ make: @escaping (RenderStage) -> SettingsHub) -> (RenderStage) -> Shot {
        { stage in
            Shot(screen: "settings", state: "\(tab.rawValue)-\(state)", about: about, byLook: false) { dark in
                let hub = make(stage)
                SettingsPage.maxHeight = 4000
                defer { SettingsPage.maxHeight = nil }
                let (window, controller) = SettingsWindowController.make(hub: hub)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                controller.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
                guard let page = controller.tabViewItems[controller.selectedTabViewItemIndex].viewController as? SettingsPage else { return nil }
                window.setContentSize(NSSize(width: SettingsPage.width, height: 400))
                page.fit()
                window.setContentSize(page.preferredContentSize)
                controller.view.frame = NSRect(origin: .zero, size: page.preferredContentSize)
                controller.view.layoutSubtreeIfNeeded()
                controller.tabView.frame = controller.view.bounds
                page.view.frame = controller.tabView.bounds
                page.view.layoutSubtreeIfNeeded()
                return Offscreen.image(of: window, dark: dark)
            }
        }
    }

    /// A hub on a model, with the stage's folder as home so no real path is read or shown.
    @MainActor static func hub(_ stage: RenderStage, model: AppModel, _ change: (SettingsHub) -> Void = { _ in }) -> SettingsHub {
        let hub = SettingsHub(model: model, home: stage.folder)
        hub.version = "Tidemark 1.0 (1)"
        hub.legacyFound = LegacyFound(weeks: 39, first: "2026-01-26", last: "2026-10-19", hasNames: true, hasReports: true)
        hub.notifications = .allowed
        change(hub)
        return hub
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        let s = stage.scenarios
        /// Plan limits on, signed in, the two demo plans known, as after the first refresh.
        func on(_ scenario: DemoScenario? = nil, _ change: @escaping (AppModel) -> Void = { _ in }) -> AppModel {
            let scenario = scenario ?? s[0]
            let model = stage.demo(scenario)
            model.settings.planLimits = true
            model.setAvailableOrgs(scenario.orgs, claudeCodeOrg: scenario.claudeCodeOrg)
            change(model)
            return model
        }
        typealias Make = (RenderStage) -> SettingsHub
        func shot(_ tab: SettingsTab, _ state: String, _ about: String, _ make: @escaping Make) -> Shot {
            tabShot(tab, state, about, make)(stage)
        }
        return [
            shot(.general, "default", "Signed in with plan limits on, launch at login off") { hub($0, model: on()) },
            shot(.general, "signed-out", "Signed out with plan limits on: a top row with Sign in to claude.ai…") {
                hub($0, model: on { $0.signedOut() })
            },
            shot(.general, "limits-off", "Plan limits off, the first-run default: no requests go to claude.ai") {
                hub($0, model: stage.demo(s[0]))
            },
            shot(.general, "menu-bar-icon", "Menu bar set to Tidemark icon: the Plan names row goes away (it shows only for batteries)") {
                hub($0, model: on { $0.settings.menuBarMode = .icon })
            },
            shot(.general, "first-letters", "Menu bar a battery per plan with Plan names set to First letters") {
                hub($0, model: on { $0.settings.planNameStyle = .letters })
            },
            shot(.general, "launch-failed", "macOS wouldn't register the login item: the caption and Open") {
                hub($0, model: on()) { $0.launchFailed = true }
            },
            shot(.widget, "widget", "Show as Widget: position, layout, width (no tick marks), text size, Dock fitting, in-use effect") {
                hub($0, model: on())
            },
            shot(.widget, "notch", "Show as Notch: Shape, Place, Width, Opens to Medium or Large, Status rim; no in-use effect") {
                hub($0, model: on { $0.settings.displayMode = .notch })
            },
            shot(.widget, "vertical", "The widget on a side edge: no Fit beside the Dock or Measure the Dock") {
                hub($0, model: on { $0.vertical = true })
            },
            shot(.widget, "dragged", "The widget dragged off the snap points: Position reads Where you dragged it") {
                hub($0, model: on { $0.settings.widgetSpot = .free(WidgetOffset(right: 240, bottom: 0)) })
            },
            shot(.widget, "fitted", "The widget narrowed beside the Dock: Fitted to … pt under the width") {
                hub($0, model: on { $0.settings.widgetWidth = 520; $0.widgetLayoutWidth = 376 })
            },
            shot(.widget, "measure-needs-permission", "Measure the Dock on without Accessibility access: the Allow button") {
                hub($0, model: on { $0.settings.measureDock = true })
            },
            shot(.widget, "measure-allowed", "Measure the Dock on with Accessibility access") {
                hub($0, model: on { $0.settings.measureDock = true }) { $0.dockAccessAllowed = true }
            },
            shot(.plans, "two-plans", "Two plans shown: the shared-with-the-desktop-app picker and every threshold") {
                hub($0, model: on())
            },
            shot(.plans, "one-plan", "One plan: no Shared picker, and the switch thresholds say Switch advice needs two plans") {
                hub($0, model: on(stage.oneOrg)) { $0.thresholdsOpen = true }
            },
            shot(.plans, "thresholds-open", "Show thresholds open, with the clearer labels") {
                hub($0, model: on()) { $0.thresholdsOpen = true }
            },
            shot(.plans, "limits-off", "Plan limits off: no plan list, a line pointing to General") {
                hub($0, model: stage.demo(s[0]))
            },
            shot(.week, "default", "The sources as switches, Cowork log folder not set, 39 weeks found to import") {
                hub($0, model: on())
            },
            shot(.week, "not-chosen", "Before anything has been chosen: one row, “Tidemark isn’t reading anything yet”, with Choose what it reads…") {
                hub($0, model: on { $0.settings.sourcesChosen = false })
            },
            shot(.week, "cowork-waiting", "A Cowork log folder chosen: waiting for Cowork’s first log line") {
                hub($0, model: on { $0.settings.sources.coworkLogFolder = $0.settings.sources.coworkLogFolder ?? "/Users/you/Documents/Cowork" }) {
                    $0.coworkStatus = ShellCopy.coworkStatus(lastTask: nil)
                }
            },
            shot(.week, "cowork-works", "Cowork has logged a task: Logging works · last task 10:42 AM") {
                hub($0, model: on { $0.settings.sources.coworkLogFolder = "/Users/you/Documents/Cowork" }) {
                    $0.coworkStatus = ShellCopy.coworkStatus(lastTask: stage.now.addingTimeInterval(-50 * 60), now: stage.now)
                }
            },
            shot(.week, "nothing-to-import", "No old week calendar found") {
                hub($0, model: on()) { $0.legacyFound = nil }
            },
            shot(.notifications, "default", "The three switches, notifications allowed") { hub($0, model: on()) },
            shot(.notifications, "one-plan", "One plan: the switch-advice notification is off and says why") {
                hub($0, model: on(stage.oneOrg))
            },
            shot(.notifications, "not-asked", "macOS hasn't been asked yet: Allow notifications… opens the Get notified? sheet") {
                hub($0, model: on()) { $0.notifications = .notAsked }
            },
            shot(.notifications, "denied", "macOS notifications are off for Tidemark: a way to System Settings") {
                hub($0, model: on()) { $0.notifications = .denied }
            },
            shot(.advanced, "not-connected", "Claude Code status not connected: Add hooks…") { hub($0, model: on()) },
            shot(.advanced, "connected", "Connected: the status line and Remove hooks") {
                hub($0, model: on()) { $0.hookState = .connected }
            },
            shot(.advanced, "outdated", "Outdated: Update hooks and Remove hooks") {
                hub($0, model: on()) { $0.hookState = .outdated }
            },
            shot(.advanced, "demo-data", "Demo data on") {
                hub($0, model: on { $0.settings.demoMode = true })
            },
        ]
    }
}
