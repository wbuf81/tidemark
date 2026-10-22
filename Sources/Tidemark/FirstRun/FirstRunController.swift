import AppKit
import SwiftUI
import TidemarkCore

/// The first-run window: shown once, on the first launch (`firstRunDone`). Closing it by any route
/// counts as finishing: whatever steps are left are "Not now".
@MainActor
final class FirstRunController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let actions: FirstRunActions
    private let state = FirstRunState()
    private var window: NSWindow?
    private var finished = false

    var onVisibilityChange: ((Bool) -> Void)?
    /// Runs once, when the window has closed, after `firstRunDone` is set.
    var onFinished: (() -> Void)?

    init(model: AppModel, actions: FirstRunActions) {
        self.model = model
        self.actions = actions
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        finished = false
        state.sourcesOnly = false
        state.step = 1
        let window = self.window ?? makeWindow()
        window.title = "Welcome to \(AppIdentity.name)"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange?(true)
    }

    /// Step 2, "What Tidemark reads", on its own: for someone who closed first run before choosing (Week's
    /// "Choose sources", Settings → Week). Its Continue chooses and closes; closing it any other way chooses nothing.
    func showSources() {
        if isVisible, !state.sourcesOnly { window?.makeKeyAndOrderFront(nil); return }   // first run itself is still open
        finished = false
        state.sourcesOnly = true
        state.step = 2
        let window = self.window ?? makeWindow()
        window.title = ShellCopy.firstRunReadsTitle
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange?(true)
    }

    private func makeWindow() -> NSWindow {
        var actions = self.actions
        actions.finish = { [weak self] in self?.window?.close() }
        let window = Self.frame(model: model, state: state, actions: actions)
        window.delegate = self
        self.window = window
        return window
    }

    /// The window at a step, not yet shown (`--render` draws one offscreen).
    static func frame(model: AppModel, state: FirstRunState, actions: FirstRunActions) -> NSWindow {
        let host = NSHostingController(rootView: FirstRunView(state: state, settings: model.settings, model: model, actions: actions))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to \(AppIdentity.name)"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(FirstRunView.size)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
        // Step 2 on its own isn't first run: closing it doesn't finish anything.
        if state.sourcesOnly { state.sourcesOnly = false; return }
        guard !finished else { return }
        finished = true
        model.settings.firstRunDone = true
        onFinished?()
    }
}
