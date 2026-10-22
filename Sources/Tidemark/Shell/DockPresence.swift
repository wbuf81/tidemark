import AppKit

/// The Dock icon and ⌘Tab: Tidemark is an accessory app (neither) until a window is open, regular
/// while the main window, Settings, first run, the sign-in window or a stand-alone sheet is visible,
/// and an accessory again half a second after the last one closes. Becoming a regular app also
/// activates it, so the menu bar shows Tidemark's menus rather than the previous app's.
@MainActor
final class DockPresence {
    enum Window: Hashable { case main, settings, firstRun, signIn, sheet }

    private var visible: Set<Window> = []
    private var pending: DispatchWorkItem?
    private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void
    static let delay: TimeInterval = 0.5

    init(apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = DockPresence.applyToApp) {
        self.apply = apply
    }

    private static func applyToApp(_ policy: NSApplication.ActivationPolicy) {
        let becomingRegular = policy == .regular && NSApp.activationPolicy() != .regular
        _ = NSApp.setActivationPolicy(policy)
        if becomingRegular { NSApp.activate(ignoringOtherApps: true) }
    }

    func set(_ window: Window, visible isVisible: Bool) {
        if isVisible { visible.insert(window) } else { visible.remove(window) }
        pending?.cancel()
        pending = nil
        if !visible.isEmpty {
            apply(.regular)
        } else {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.visible.isEmpty else { return }
                    self.apply(.accessory)
                }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        }
    }
}
