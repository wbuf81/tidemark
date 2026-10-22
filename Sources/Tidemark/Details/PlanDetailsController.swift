import AppKit
import Combine
import SwiftUI
import TidemarkCore

/// The details card's panel: borderless, floating, never takes the app's focus. One at a time. Placed
/// from the frame `AppActions.openDetails` gets (see `DetailsPlacement`). Esc, a click anywhere else,
/// or opening another plan's card closes it; opening the same plan again closes it too.
@MainActor
final class PlanDetailsController {
    private let model: AppModel
    private let openUsage: (String) -> Void
    private var panel: DetailsPanel?
    private var host: NSHostingView<PlanDetailsHost>?
    private var planID: String?
    /// What the card was opened from, so it can be placed again when its contents change size.
    private var anchor: (frame: CGRect, kind: DetailsAnchor)?
    private var monitors: [Any] = []
    private var modelSink: AnyCancellable?
    /// A click outside just closed this plan's card: the same click landing on its slot must not reopen it.
    private var justClosed: (id: String, until: Date)?
    /// Told which plan's card is open (nil when none): the menu bar highlights that plan's battery.
    var onOpenChange: (String?) -> Void = { _ in }

    init(model: AppModel, openUsage: @escaping (String) -> Void) {
        self.model = model
        self.openUsage = openUsage
    }

    var isOpen: Bool { panel != nil }

    /// `anchor` is in screen points (origin bottom left); `kind` says what was clicked.
    func open(plan id: String, from anchor: CGRect, anchor kind: DetailsAnchor) {
        if let justClosed, justClosed.id == id, Date() < justClosed.until { self.justClosed = nil; return }
        justClosed = nil
        if planID == id, panel != nil { close(); return }
        close()
        guard canShow(id) else { return }

        let host = NSHostingView(rootView: PlanDetailsHost(model: model, orgID: id, openUsage: { [weak self] in
            self?.close()
            self?.openUsage(id)
        }))
        // The controller owns the frame: the host reports its size but never resizes the window itself.
        host.sizingOptions = [.intrinsicContentSize]
        let panel = DetailsPanel()
        panel.onEscape = { [weak self] in self?.close() }
        panel.contentView = host
        self.panel = panel
        self.host = host
        self.anchor = (anchor, kind)
        planID = id
        place()
        panel.orderFrontRegardless()
        panel.makeKey()
        // VoiceOver is told about the new panel.
        NSAccessibility.post(element: panel, notification: .focusedWindowChanged)
        monitor()
        // Follows the model: closes when its plan goes or limits turn off, and re-fits as contents appear.
        modelSink = model.objectWillChange.debounce(for: .milliseconds(150), scheduler: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.modelChanged() }
        }
        onOpenChange(id)
    }

    func close() {
        modelSink = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        host = nil
        anchor = nil
        let was = planID
        planID = nil
        if was != nil { onOpenChange(nil) }
    }

    /// Limits off never opens it; nor does a plan that is gone or was never read.
    private func canShow(_ id: String) -> Bool {
        guard !model.limitsOff, let org = model.orgs.first(where: { $0.id == id }) else { return false }
        return model.readTime(for: org) != nil
    }

    private func modelChanged() {
        guard let id = planID else { return }
        guard canShow(id) else { close(); return }
        place()
    }

    /// Sizes the panel to its contents and puts it where `DetailsPlacement` says; moves it again only if that changed.
    private func place() {
        guard let panel, let host, let anchor else { return }
        let size = host.fittingSize
        let screen = Self.screen(holding: anchor.frame)
        let frame = DetailsPlacement.frame(anchor: anchor.frame, from: anchor.kind, size: size,
                                           screen: screen?.visibleFrame ?? anchor.frame.insetBy(dx: -400, dy: -400))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// The screen with the most of `rect` on it, else the one holding its centre, else the main one.
    static func screen(holding rect: CGRect) -> NSScreen? {
        let best = NSScreen.screens.max { a, b in
            let x = a.frame.intersection(rect), y = b.frame.intersection(rect)
            return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
        }
        if let best, best.frame.intersects(rect) { return best }
        return NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
    }

    private func monitor() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeFromOutside() }
        }) { monitors.append(global) }
        // Clicks in this app's other windows; the event goes on to what was clicked.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated { if let self, event.window !== self.panel { self.closeFromOutside() } }
            return event
        }) { monitors.append(local) }
    }

    private func closeFromOutside() {
        if let id = planID { justClosed = (id, Date().addingTimeInterval(0.8)) }
        close()
    }
}

/// Takes key status without activating the app, so Esc reaches it.
private final class DetailsPanel: NSPanel {
    var onEscape: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        setAccessibilityLabel("Plan details")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// The card as the panel shows it: kept current as the model changes.
private struct PlanDetailsHost: View {
    @ObservedObject var model: AppModel
    let orgID: String
    let openUsage: () -> Void

    var body: some View {
        if let org = model.orgs.first(where: { $0.id == orgID }), let reading = model.latest[orgID] {
            let adjusted = reading.adjusted(to: model.now)
            PlanDetailsView(
                name: org.name,
                details: PlanDetails.make(reading: adjusted, history: model.history, now: model.now, formatting: model.formatting,
                                          thresholds: model.settings.thresholds, isOld: model.isOld(org)),
                formatting: model.formatting, isOld: model.isOld(org), openUsage: openUsage)
        }
    }
}
