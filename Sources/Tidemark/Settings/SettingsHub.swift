import AppKit
import Combine
import ServiceManagement
import SwiftUI
import TidemarkCore

/// Everything the six Settings tabs read and ask for: the model and its settings, the state that
/// doesn't live in them (hooks, launch at login, the old calendar, notification permission) and
/// the actions, each a do-nothing until the app fills it in, so `--render` can build a tab with
/// nothing behind it.
@MainActor
final class SettingsHub: ObservableObject {
    enum HooksChange { case add, update, remove }
    enum NotificationPermission { case unavailable, notAsked, allowed, denied }

    let model: AppModel
    var settings: Settings { model.settings }
    /// A home folder to show paths relative to; renders pass a temporary one.
    let home: URL

    // State the tabs draw.
    @Published var hookState: HookState = .notConnected
    @Published var launchesAtLogin = false
    /// macOS refused to register the login item (or wants it allowed in System Settings).
    @Published var launchFailed = false
    @Published var legacyFound: LegacyFound?
    @Published var coworkStatus: String?
    @Published var dockAccessAllowed = false
    @Published var thresholdsOpen = false
    @Published var notifications: NotificationPermission = .unavailable
    @Published var version = "Tidemark"
    /// Claude Code's settings file as the user sees it (it moves with CLAUDE_CONFIG_DIR).
    var settingsFile = ShellCopy.defaultSettingsFile

    // Actions.
    var setDemoMode: (Bool) -> Void = { _ in }
    var signIn: () -> Void = {}
    var signOut: () -> Void = {}
    var refresh: () -> Void = {}
    var place: (SnapPoint) -> Void = { _ in }
    var setLayout: (LayoutChoice) -> Void = { _ in }
    var setSize: (Double) -> Void = { _ in }
    var setWidth: (Double) -> Void = { _ in }
    var setMeasureDock: (Bool) -> Void = { _ in }
    var askDockAccess: () -> Void = {}
    var setPlanLimits: (Bool) -> Void = { _ in }
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var changeHooks: (HooksChange) -> Void = { _ in }
    var chooseCoworkFolder: () -> Void = {}
    var chooseSources: () -> Void = {}
    var showImport: () -> Void = {}
    var showInFinder: () -> Void = {}
    var deleteAll: () -> Void = {}
    var uninstall: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var askNotifications: () -> Void = {}
    var openNotificationSettings: () -> Void = {}
    /// Called when a tab appears, so the app can re-read what can change behind its back.
    var tabAppeared: () -> Void = {}

    init(model: AppModel, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.model = model
        self.home = home
    }
}
