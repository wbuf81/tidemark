import AppKit
import SwiftUI
import TidemarkCore

/// One tab's page: its SwiftUI form, sized to its content so the window fits each tab.
@MainActor
final class SettingsPage: NSHostingController<AnyView> {
    static let width: CGFloat = 520
    /// The tallest a tab makes the window; nil is what the screen has room for. The render sets a large one.
    static var maxHeight: CGFloat?
    let tab: SettingsTab
    private let hub: SettingsHub

    init(tab: SettingsTab, hub: SettingsHub) {
        self.tab = tab
        self.hub = hub
        super.init(rootView: AnyView(tab.content(hub).frame(width: Self.width)))
        title = tab.title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// How tall a tab may be on `screen`: its visible height less the title bar, the toolbar and a margin.
    static func heightLimit(on screen: NSScreen?) -> CGFloat {
        if let maxHeight { return maxHeight }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame.height else { return 640 }
        return max(visible - 140, 400)
    }

    private func height(for content: CGFloat) -> CGFloat {
        min(max(content, 160), Self.heightLimit(on: view.window?.screen))
    }

    /// Sets the size the window takes for this tab: the form's full height, up to what the screen has room for.
    func fit() {
        view.frame = NSRect(x: 0, y: 0, width: Self.width, height: 2400)
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: Self.width, height: height(for: Offscreen.scrolledHeight(in: view) ?? 480))
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        hub.tabAppeared()
        fit()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in self?.settle() }
    }

    /// Measured again in the window, where the form has laid out every row (before, it may not have): the
    /// window grows or shrinks to it from its top edge, and a tab that still doesn't fit flashes its scroll bar.
    private func settle() {
        guard let window = view.window, let scroll = Offscreen.scrollView(in: view),
              let document = scroll.documentView else { return }
        let content = ceil(document.frame.height)
        let height = height(for: content)
        preferredContentSize = NSSize(width: Self.width, height: height)
        let change = height - view.frame.height
        if abs(change) > 1 {
            var frame = window.frame
            frame.size.height += change
            frame.origin.y -= change
            if let visible = window.screen?.visibleFrame, frame.minY < visible.minY { frame.origin.y = visible.minY }
            window.setFrame(frame, display: true, animate: true)
        }
        if content > height + 1 { scroll.flashScrollers() }
    }
}

/// The Settings window: six tabs on a toolbar (an `NSTabViewController`), built on first use and kept.
/// `show(_:)` opens it on a tab.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let hub: SettingsHub
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    var onVisibilityChange: ((Bool) -> Void)?

    init(hub: SettingsHub) {
        self.hub = hub
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }
    /// The window, for sheets to slide out of.
    var parentWindow: NSWindow? { window }

    func show(_ tab: SettingsTab = .general) {
        let window = self.window ?? makeWindow()
        let wasVisible = window.isVisible
        tabs?.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        if !wasVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { onVisibilityChange?(true) }
    }

    private func makeWindow() -> NSWindow {
        let (window, controller) = Self.make(hub: hub)
        window.delegate = self
        window.setFrameAutosaveName("Settings")
        self.window = window
        tabs = controller
        return window
    }

    /// The window and its tab controller, not yet shown (`--render` draws one offscreen).
    static func make(hub: SettingsHub) -> (NSWindow, NSTabViewController) {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let page = SettingsPage(tab: tab, hub: hub)
            let item = NSTabViewItem(viewController: page)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            controller.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        return (window, controller)
    }

    func windowWillClose(_ notification: Notification) { onVisibilityChange?(false) }
    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChange?(false) }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChange?(true) }
}
