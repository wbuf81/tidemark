import AppKit
import Combine
import ServiceManagement
import SwiftUI
import TidemarkCore

/// Wires the parts together: the model and its poller, the calendar, the widget and the notch, the
/// windows (main, Settings, first run), the menu bar, notifications and the sheets.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The parts.
    var model: AppModel!
    var dock: DockController!
    var notch: NotchController!
    var poller: Poller!
    let session = ClaudeWebSession()
    var notifier: Notifier!
    var hub: SettingsHub!
    var settingsWindow: SettingsWindowController!
    var mainWindow: MainWindowController!
    var details: PlanDetailsController!
    var firstRun: FirstRunController!
    var statusItem: StatusItemController!
    var mainMenu: MainMenu!
    let dockPresence = DockPresence()

    // Where things are. Everything below is relative to `home`.
    let home = FileManager.default.homeDirectoryForCurrentUser
    let environment = ProcessInfo.processInfo.environment
    lazy var hookFile = ClaudeCodeHookFile(settings: ClaudePaths.settingsFile(environment: environment, home: home),
                                           support: AppIdentity.supportURL(home: home))

    // The calendar: the real store, or the demo's while demo data is on.
    lazy var liveCalendar: CalendarStoring = CalendarStores.live(home: home, environment: environment)
    lazy var calendar = SwitchableCalendar(liveCalendar)
    var importSource: URL { AppIdentity.calendarURL(home: home).appendingPathComponent("import-source") }

    // State.
    private var sinks: [AnyCancellable] = []
    private var hiddenUntil: Date?
    private var hideTimer: Timer?
    private var demo: Task<Void, Never>?
    private var clock: Timer?
    private var calendarTimer: Timer?
    private var activityRefresh: DispatchWorkItem?
    private var pruneTimer: Timer?
    private var claudeCodeActivity: ClaudeCodeActivity?
    private var liveSessions: LiveSessions?
    private var historyStore: HistoryStore!
    /// Delete all or Uninstall is running: the calendar reads nothing meanwhile.
    var calendarPaused = false

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings(defaults: .standard)
        historyStore = HistoryStore(url: HistoryStore.defaultURL)
        model = AppModel(settings: settings, store: historyStore)
        NSApp.appearance = settings.themeChoice.appearance
        sinks.append(settings.$themeChoice.dropFirst().sink { NSApp.appearance = $0.appearance })
        if settings.demoMode { calendar.target = DemoCalendar.store() }
        session.mayRequest = { [weak settings] in
            settings.map { UsageGate.mayRequest(planLimits: $0.planLimits, demoMode: $0.demoMode, firstRunDone: $0.firstRunDone) } ?? false
        }
        poller = Poller(model: model, session: session, account: ClaudeCodeAccount())
        notifier = Notifier(settings: settings)

        let actions = makeActions()
        mainWindow = MainWindowController(model: model, calendar: calendar, actions: actions)
        details = PlanDetailsController(model: model, openUsage: { [weak self] in self?.mainWindow.show(.usage, plan: $0) })
        hub = makeHub()
        settingsWindow = SettingsWindowController(hub: hub)
        firstRun = FirstRunController(model: model, actions: FirstRunActions(
            turnOnAndSignIn: { [weak self] in self?.enablePlanLimits() },
            sourcesChosen: { [weak self] in self?.firstRunChoseSources() }))
        dock = DockController(model: model, actions: actions)
        notch = NotchController(model: model, actions: actions)
        statusItem = StatusItemController(model: model, widgetHidden: { [weak self] in self?.isHidden ?? false },
                                          callbacks: StatusItemController.Callbacks(
                                              open: { [weak self] in self?.mainWindow.show(.usage) },
                                              refresh: { [weak self] in self?.refreshEverything() },
                                              toggleWidget: { [weak self] in self?.toggleWidget() },
                                              settings: { [weak self] in self?.settingsWindow.show() },
                                              quit: { NSApp.terminate(nil) },
                                              openDetails: { [weak self] in self?.makeActions().openDetails($0, $1, $2) }))
        details.onOpenChange = { [weak self] in self?.statusItem.highlight(plan: $0) }
        mainMenu = MainMenu(run: { [weak self] in self?.menuAction($0) })
        NSApp.mainMenu = mainMenu.build()

        wireWindows()
        wireNotifications()
        wireWake()
        startActivityWatchers()
        statusItem.start()
        applyDisplayMode()
        sinks.append(settings.$displayMode.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyDisplayMode() } }
        })
        sinks.append(settings.$sources.dropFirst().removeDuplicates().debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshCalendar()
        })
        sinks.append(settings.$weekStart.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.feedWeek(); self?.mainWindow.reload() } }
        })
        scheduleCalendar()
        schedulePrune()
        updateClock()

        // For checking the main window without a click: TIDEMARK_OPEN_WINDOW=1.
        if environment["\(AppIdentity.envPrefix)OPEN_WINDOW"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.mainWindow.show(.usage) }
        }
        refreshCalendar()
        if settings.demoMode {
            startDemo()
        } else if settings.planLimits, settings.firstRunDone {
            startUsage()
        }
        if !settings.firstRunDone {
            firstRun.onFinished = { [weak self] in
                guard let self else { return }
                // Plan limits read nothing and open no sign-in until here (`UsageGate`); a migrated install has them on.
                if self.model.settings.planLimits, !self.model.settings.demoMode { self.startUsage() }
                self.refreshCalendar()   // reads only if the sources were chosen (closing early leaves it paused)
                self.offerImport()
            }
            firstRun.show()
        } else {
            offerImport()
        }
    }

    /// A click on the Dock icon, or opening the app again: show the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if firstRun.isVisible { return true }
        mainWindow.show(model.settings.firstRunDone ? nil : .usage)
        return true
    }

    // MARK: Wiring

    private func makeActions() -> AppActions {
        AppActions(
            writeReport: { [weak self] week in
                guard let self else { return .failure(.notInstalled) }
                // Demo data never runs the real Claude Code.
                let write = self.model.settings.demoMode ? DemoCalendar.reportWriter()
                    : CalendarStores.reportWriter(home: self.home, environment: self.environment)
                return await write(week, Date())
            },
            openWindow: { [weak self] section, plan in self?.mainWindow.show(section ?? .usage, plan: plan) },
            openDetails: { [weak self] plan, frame, anchor in self?.details.open(plan: plan, from: frame, anchor: anchor) },
            refresh: { [weak self] in self?.refreshEverything() },
            hideForAnHour: { [weak self] in self?.hideForAnHour() },
            openSettings: { [weak self] in self?.settingsWindow.show($0) },
            chooseSources: { [weak self] in self?.firstRun.showSources() },
            signIn: { [weak self] in self?.session.showSignIn() },
            turnOnPlanLimits: { [weak self] in self?.askPlanLimits() },
            signOut: { [weak self] in self?.askSignOut() },
            quit: { NSApp.terminate(nil) },
            dragChanged: { [weak self] in self?.dock.dragChanged() },
            dragEnded: { [weak self] in self?.dock.dragEnded() },
            pinch: { [weak self] in
                guard let self else { return }
                if self.model.settings.displayMode == .notch { self.notch.pinch($0, ended: $1) }
                else { self.dock.pinch($0, ended: $1) }
            })
    }

    private func makeHub() -> SettingsHub {
        let hub = SettingsHub(model: model, home: home)
        let info = Bundle.main.infoDictionary
        hub.version = "\(AppIdentity.name) \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "0"))"
        hub.setDemoMode = { [weak self] in self?.setDemoMode($0) }
        hub.signIn = { [weak self] in self?.session.showSignIn() }
        hub.signOut = { [weak self] in self?.askSignOut() }
        hub.refresh = { [weak self] in self?.refreshEverything() }
        hub.place = { [weak self] in self?.dock.place($0) }
        hub.setLayout = { [weak self] in self?.dock.setLayout($0) }
        hub.setSize = { [weak self] in self?.dock.setSize($0) }
        hub.setWidth = { [weak self] in self?.dock.setWidth($0) }
        hub.setMeasureDock = { [weak self] on in self?.setMeasureDock(on) }
        hub.askDockAccess = { [weak self] in self?.dock.openDockAccessSettings() }
        hub.setPlanLimits = { [weak self] on in on ? self?.askPlanLimits() : self?.disablePlanLimits() }
        hub.setLaunchAtLogin = { [weak self] in self?.setLaunchAtLogin($0) }
        hub.changeHooks = { [weak self] in self?.changeHooks($0) }
        hub.chooseCoworkFolder = { [weak self] in self?.showCoworkSheet() }
        hub.chooseSources = { [weak self] in self?.firstRun.showSources() }
        hub.showImport = { [weak self] in self?.importOrChoose() }
        hub.showInFinder = { [weak self] in self?.showDataInFinder() }
        hub.deleteAll = { [weak self] in self?.askDeleteAll() }
        hub.uninstall = { [weak self] in self?.askUninstall() }
        hub.checkForUpdates = { NSWorkspace.shared.open(AppIdentity.releasesURL) }
        hub.askNotifications = { [weak self] in self?.askNotifications() }
        hub.settingsFile = ShellCopy.displayPath(ClaudePaths.settingsFile(environment: environment, home: home), home: home)
        hub.openNotificationSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        }
        hub.tabAppeared = { [weak self] in self?.refreshHub() }
        return hub
    }

    /// Re-reads what can change behind the app's back, for the tab that just appeared.
    func refreshHub() {
        hub.hookState = hookFile.state()
        hub.launchesAtLogin = SMAppService.mainApp.status == .enabled
        hub.dockAccessAllowed = dock?.dockAccessAllowed ?? false
        hub.legacyFound = calendar.findLegacy(in: importSource)
        if let folder = model.settings.sources.coworkLogFolder {
            hub.coworkStatus = ShellCopy.coworkStatus(lastTask: calendar.lastCoworkLogEntry(in: URL(fileURLWithPath: folder)))
        } else {
            hub.coworkStatus = nil
        }
        Task { hub.notifications = await notifier.permission() }
    }

    private func wireWindows() {
        mainWindow.onVisibilityChange = { [weak self] in self?.dockPresence.set(.main, visible: $0); self?.updateClock() }
        settingsWindow.onVisibilityChange = { [weak self] in self?.dockPresence.set(.settings, visible: $0); self?.updateClock() }
        firstRun.onVisibilityChange = { [weak self] in self?.dockPresence.set(.firstRun, visible: $0) }
        // The sign-in window and sheets that have no window to slide out of are windows too: they keep
        // the Dock icon and ⌘Tab while they're open.
        session.onWindowVisibility = { [weak self] in self?.dockPresence.set(.signIn, visible: $0) }
        SheetPresenter.onStandaloneChange = { [weak self] in self?.dockPresence.set(.sheet, visible: $0) }
        session.onSignedIn = { [weak self] in self?.poller.restartAfterSignIn() }
    }

    private func wireNotifications() {
        notifier.onClick = { [weak self] kind, planName in
            guard let self else { return }
            if kind == .signedOut {
                if self.model.signedIn { self.mainWindow.show(.usage) } else { self.session.showSignIn() }
                return
            }
            let plan = planName.flatMap { name in self.model.orgs.first { $0.name == name }?.id }
            self.mainWindow.show(.usage, plan: plan)
        }
        notifier.askFirst = { [weak self] decide in
            guard let self else { return decide(false) }
            NotificationsSheet.present(over: self.sheetParent, onContinue: { decide(true) }, onNotNow: { decide(false) })
        }
        notifier.start()
        model.onSignedOut = { [weak self] in self?.notifier.post(Copy.signedOutNotice, kind: .signedOut) }
        model.onAdvice = { [weak self] in self?.notifier.post($0, kind: .switchAdvice) }
        model.onOut = { [weak self] in self?.notifier.post($0, kind: .nearlyOut) }
        model.onSessionNearlyFull = { [weak self] in self?.notifier.post($0, kind: .nearlyOut) }
    }

    private func wireWake() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.demoMode else { return }
                self.poller.wake()
                self.refreshCalendar()
                self.applyDisplayMode()   // a hide that ended while asleep
                self.model.tick()
            }
        }
    }

    private func startActivityWatchers() {
        claudeCodeActivity = ClaudeCodeActivity(folder: ClaudePaths.projectsDir(environment: environment, home: home)) { [weak self] time in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.model.claudeCodeWorked(at: time)
                    self?.scheduleActivityRefresh()
                }
            }
        }
        claudeCodeActivity?.start()
        model.hooksConnected = hookFile.state().feedsLiveStatus
        liveSessions = LiveSessions { [weak self] sessions in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.sessionsChanged(sessions) } }
        }
        liveSessions?.start()
    }

    // MARK: Menus

    private func menuAction(_ id: String) {
        switch id {
        case "updates": NSWorkspace.shared.open(AppIdentity.releasesURL)
        case "settings": settingsWindow.show()
        case "quit": NSApp.terminate(nil)
        case "copySummary": mainWindow.copySummary()
        case "usage": mainWindow.show(.usage)
        case "week": mainWindow.show(.week)
        case "month": mainWindow.show(.month)
        case "trends": mainWindow.show(.trends)
        case "names": mainWindow.show(.names)
        case "previousWeek": mainWindow.previousWeek()
        case "nextWeek": mainWindow.nextWeek()
        case "today": mainWindow.today()
        case "refresh": refreshEverything()
        case "hideWidget": hideForAnHour()
        case "sidebar": mainWindow.toggleSidebar()
        case "help": NSWorkspace.shared.open(AppIdentity.releasesURL.deletingLastPathComponent())
        default: break
        }
    }

    // MARK: The widget and the notch

    var isHidden: Bool { ShellCopy.isHidden(until: hiddenUntil, now: Date()) }

    /// Shows the widget or the notch to match Settings, never both. While hidden for an hour both
    /// stay hidden; the mode is applied when it ends (by the wall clock, so a sleep counts).
    func applyDisplayMode() {
        if isHidden {
            dock.hide()
            notch.hide()
            return
        }
        hiddenUntil = nil
        hideTimer?.invalidate()
        hideTimer = nil
        if model.settings.displayMode == .notch {
            dock.hide()
            notch.show()
        } else {
            notch.hide()
            dock.show()
        }
        updateClock()
    }

    private func hideForAnHour() {
        let ends = ShellTime.hideEnds(started: Date(), duration: ShellCopy.hideDuration)
        hiddenUntil = ends
        dock.hide()
        notch.hide()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: max(ends.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDisplayMode() }
        }
        updateClock()
    }

    /// The menu bar's Hide the widget / Show the widget.
    private func toggleWidget() {
        if isHidden { hiddenUntil = nil; applyDisplayMode() } else { hideForAnHour() }
    }

    // MARK: The clock

    /// The 30-second clock runs only while something on screen shows the time: the widget or notch
    /// (not while hidden), the main window or Settings.
    private func updateClock() {
        let needed = !isHidden || mainWindow?.isVisible == true || settingsWindow?.isVisible == true
        if needed, clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tickClock() }
            }
            clock?.tolerance = 3
        } else if !needed {
            clock?.invalidate()
            clock = nil
        }
    }

    private func tickClock() {
        guard !model.settings.demoMode else { return }
        model.tick()
        liveSessions?.reload()
        // settings.json can change behind our back.
        let state = hookFile.state()
        if state.feedsLiveStatus != model.hooksConnected { model.hooksConnected = state.feedsLiveStatus }
        if hub.hookState != state { hub.hookState = state }
    }

    // MARK: The calendar

    /// Reads Claude Code's and Cowork's files into the calendar (off the main thread, by the store)
    /// and shows the week in the widget.
    func refreshCalendar() {
        guard !model.settings.demoMode else { feedWeek(); return }
        // Nothing is read until the user has chosen what Tidemark reads (first run's step 2, or Settings → Week).
        guard CalendarSchedule.mayRefresh(sourcesChosen: model.settings.sourcesChosen, paused: calendarPaused,
                                          importWaiting: importWaiting) else { return }
        let sources = model.settings.sources
        Task {
            _ = await calendar.refresh(sources, now: Date())
            feedWeek()
            mainWindow.reload()
        }
    }

    /// An old calendar waits in `import-source` and the user hasn't answered the offer: its names file hides titles
    /// the first read would show, so nothing is read until Import or Not now.
    var importWaiting: Bool {
        !model.settings.importOffered
            && CalendarSchedule.importWaiting(importOffered: false, legacyWeeks: calendar.findLegacy(in: importSource)?.weeks)
    }

    /// First run left step 2: the switches are the user's choice now, so the first read can run.
    private func firstRunChoseSources() {
        model.settings.sourcesChosen = true
        refreshCalendar()
    }

    /// The widget's week band, from the calendar. Without any source on there is no week to show.
    func feedWeek() {
        let settings = model.settings
        if settings.demoMode {
            model.showWeek(calendar.weekSummary(containing: DemoCalendar.now, weekStart: settings.weekStart, now: DemoCalendar.now))
            return
        }
        let s = settings.sources
        guard s.claudeCode || s.coworkLogFolder != nil || s.desktopCowork else { model.showWeek(nil); return }
        let now = Date()
        model.showWeek(calendar.weekSummary(containing: now, weekStart: settings.weekStart, now: now))
    }

    /// Every 10 minutes, and 60 seconds after Claude Code writes a transcript (once per minute
    /// while it works), the calendar reads again.
    private func scheduleCalendar() {
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCalendar() }
        }
        calendarTimer?.tolerance = 30
    }

    private func scheduleActivityRefresh() {
        guard activityRefresh == nil, !model.settings.demoMode else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.activityRefresh = nil
                self?.refreshCalendar()
            }
        }
        activityRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    /// The reading history is pruned once a day, off the main thread.
    private func schedulePrune() {
        let store = historyStore!
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                try? store.prune(olderThan: Date().addingTimeInterval(-35 * 24 * 3600))
            }
        }
    }

    /// Reads the usage and the calendar now (the Refresh buttons and menus).
    func refreshEverything() {
        Task { await poller.refresh() }
        refreshCalendar()
    }

    // MARK: claude.ai

    /// Turning plan limits on: the warning sheet first, then sign-in.
    func askPlanLimits() {
        PlanLimitsSheet.present(over: sheetParent) { [weak self] in self?.enablePlanLimits() }
    }

    /// Plan limits on: read now when a session already exists, else open sign-in. During first run (step 3) the
    /// switch is only set: nothing reads claude.ai and no window opens until first run is done (`UsageGate`).
    func enablePlanLimits() {
        model.settings.planLimits = true
        if model.settings.demoMode || !model.settings.firstRunDone { return }
        startUsage()
    }

    /// Reads claude.ai now, opens sign-in when there is no session, and polls from then on.
    private func startUsage() {
        Task {
            await poller.refresh()
            if !model.signedIn { session.showSignIn() }
            poller.start(immediately: false)
        }
    }

    /// Plan limits off: no more requests, signed out, the web store emptied, readings cleared.
    func disablePlanLimits() {
        model.settings.planLimits = false
        poller.stop()
        session.shutDown()
        Task {
            await session.signOut()
            clearReadings()
        }
    }

    func clearReadings() {
        model.signedOut()
        // With plan limits off there is nothing to be signed into; with them still on, Settings asks to sign in.
        if !model.settings.demoMode { model.leaveDemo(); model.signedIn = !model.settings.planLimits }
        feedWeek()
    }

    private func askSignOut() {
        SignOutSheet.present(over: sheetParent) { [weak self] in self?.signOut() }
    }

    private func signOut() {
        Task {
            await session.signOut()
            model.signedOut()
        }
    }

    /// Measure the Dock exactly: the sheet says what macOS will ask before it asks.
    private func setMeasureDock(_ on: Bool) {
        guard on, !dock.dockAccessAllowed else {
            model.settings.measureDock = on
            hub.dockAccessAllowed = dock.dockAccessAllowed
            return
        }
        // Cancel leaves it off: the switch snaps back because the setting never changed.
        model.settings.objectWillChange.send()
        DockAccessSheet.present(over: sheetParent) { [weak self] in
            guard let self else { return }
            self.model.settings.measureDock = true
            self.dock.requestDockAccess()
            self.hub.dockAccessAllowed = self.dock.dockAccessAllowed
        }
    }

    // MARK: Hooks

    private func changeHooks(_ change: SettingsHub.HooksChange) {
        switch change {
        case .add, .update:
            HooksSheet.present(over: sheetParent, state: hookFile.state(), file: hub.settingsFile) { [weak self] in
                self?.applyHooks { try $0.update() }
            }
        case .remove:
            applyHooks { try $0.disconnect() }
        }
    }

    private func applyHooks(_ change: (ClaudeCodeHookFile) throws -> Void) {
        do {
            try change(hookFile)
        } catch {
            HooksFailureAlert.run(error, settings: ClaudePaths.settingsFile(environment: environment, home: home), file: hub.settingsFile)
        }
        let state = hookFile.state()
        hub.hookState = state
        model.hooksConnected = state.feedsLiveStatus
        liveSessions?.reload()
    }

    // MARK: Launch at login

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            hub.launchFailed = on && SMAppService.mainApp.status == .requiresApproval
        } catch {
            hub.launchFailed = on
        }
        hub.launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notifications

    private func askNotifications() {
        NotificationsSheet.present(over: sheetParent, onContinue: { [weak self] in
            Task {
                await self?.notifier.requestPermission()
                if let self { self.hub.notifications = await self.notifier.permission() }
            }
        })
    }

    // MARK: Demo data

    func setDemoMode(_ on: Bool) {
        model.settings.demoMode = on
        if on {
            poller.stop()
            calendar.target = DemoCalendar.store()
            mainWindow.reload()
            startDemo()
        } else {
            demo?.cancel()
            calendar.target = liveCalendar
            model.leaveDemo()
            if model.settings.planLimits { poller.start() }
            mainWindow.reload()
            refreshCalendar()
        }
    }

    private func startDemo() {
        demo?.cancel()
        demo = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                let scenarios = DemoData.scenarios()
                self.model.apply(scenarios[index % scenarios.count])
                self.feedWeek()
                index += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    /// The window a sheet should slide out of: Settings while it is open, else nothing (the sheet
    /// gets a window of its own).
    var sheetParent: NSWindow? { settingsWindow.isVisible ? settingsWindow.parentWindow : nil }
}
