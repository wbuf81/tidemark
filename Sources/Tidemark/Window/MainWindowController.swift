import AppKit
import Combine
import SwiftUI
import TidemarkCore

/// The one main window: an ordinary window that remembers its size and place. Created on first
/// use and kept, so closing and reopening keeps its size and the section it was on. A sidebar of
/// Usage, Week, Month, Trends and Names & tags, then the plans; one pane at a time.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let calendar: CalendarStoring
    private let actions: AppActions
    private let state = MainState()
    private let viewModel: CalendarViewModel
    private let copy = CopyState()
    private let defaults: UserDefaults
    private var window: NSWindow?
    private var sectionSink: AnyCancellable?

    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AppModel, calendar: CalendarStoring, actions: AppActions, defaults: UserDefaults = .standard) {
        self.model = model
        self.calendar = calendar
        self.actions = actions
        self.defaults = defaults
        viewModel = CalendarViewModel(store: calendar, settings: model.settings, now: { Date() })
        super.init()
        if let saved = defaults.string(forKey: "mainSection").flatMap(MainSection.init(rawValue:)) { state.section = saved }
        sectionSink = state.$section.dropFirst().sink { defaults.set($0.rawValue, forKey: "mainSection") }
    }

    var isVisible: Bool { window?.isVisible == true }

    /// Shows the window on `section` (the one it was on, when nil), on `plan` where the section has
    /// one, and reads claude.ai first when the reading is old.
    func show(_ section: MainSection? = nil, plan: String? = nil) {
        let window = self.window ?? makeWindow()
        let wasVisible = window.isVisible
        // A window that was closed opens on the headline's row again.
        if !wasVisible { state.plan = nil }
        if let section { state.section = section }
        if let plan { state.plan = plan }
        if state.section != .usage { viewModel.reloadAll() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { onVisibilityChange?(true) }
        refreshIfStale()
    }

    // MARK: The week (the main menu calls these)

    func previousWeek() { onWeek { $0.previousWeek() } }
    func nextWeek() { onWeek { $0.nextWeek() } }
    func today() { onWeek { $0.today() } }

    /// Puts the shown week on the pasteboard as a picture, without the sidebar.
    func copySummary() {
        onWeek { vm in
            let dark = self.window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self.copy.copy(week: vm.week, now: vm.now(), calendar: .current, dark: dark)
        }
    }

    /// Reloads every pane's data from the store: after a calendar refresh, a demo switch or Delete
    /// all data. (A change of week start reloads by itself.)
    func reload() { viewModel.reloadAll() }

    func toggleSidebar() { state.sidebarShown.toggle() }

    private func onWeek(_ act: (CalendarViewModel) -> Void) {
        if state.section != .week || !isVisible { show(.week) }
        act(viewModel)
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let window = Self.frame(model: model, actions: actions, section: state.section, state: state,
                                viewModel: viewModel, copy: copy, onCopy: { [weak self] in self?.copySummary() })
        window.setFrameAutosaveName("Main")
        if !window.setFrameUsingName("Main") { window.center() }
        window.delegate = self
        // Edit → Undo reaches the window's own undo manager; name edits register there.
        viewModel.undoManager = window.undoManager
        self.window = window
        return window
    }

    /// A main window at its first size, not yet placed or shown (`--render` draws one offscreen).
    /// Where it goes is remembered by the controller, not here.
    static func frame(model: AppModel, actions: AppActions, section: MainSection,
                      calendar: CalendarStoring = EmptyCalendarStore(), now: @escaping () -> Date = { Date() },
                      shownDay: Date? = nil) -> NSWindow {
        let state = MainState()
        state.section = section
        let viewModel = CalendarViewModel(store: calendar, settings: model.settings, now: now)
        if let shownDay { viewModel.shownDay = shownDay }
        return frame(model: model, actions: actions, section: section, state: state, viewModel: viewModel,
                     copy: CopyState(), onCopy: {})
    }

    private static func frame(model: AppModel, actions: AppActions, section: MainSection, state: MainState,
                              viewModel: CalendarViewModel, copy: CopyState, onCopy: @escaping () -> Void) -> NSWindow {
        let root = MainView(state: state, model: model, calendar: viewModel, copy: copy, actions: actions, onCopy: onCopy)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []   // the window sets the size, not the content
        let window = NSWindow(contentViewController: host)
        window.title = "Tidemark"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.setContentSize(NSSize(width: 1180, height: 760))
        return window
    }

    private func refreshIfStale() {
        guard !model.settings.demoMode else { return }
        if model.lastUpdated.map({ Date().timeIntervalSince($0) > 30 }) ?? true { actions.refresh() }
    }

    // A minimized window is still open: the Dock icon, ⌘Tab and the main menu stay until it is closed.
    func windowWillClose(_ notification: Notification) { onVisibilityChange?(false) }
}
