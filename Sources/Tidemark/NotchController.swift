import AppKit
import Combine
import SwiftUI
import TidemarkCore

/// The notch window's content: the hosted notch, the resize handle on the glass's left edge
/// (at rest only) and a tracking area over the glass that reports the pointer coming and going.
private final class NotchContainer: NSView {
    var onResize: ((ResizePhase) -> Void)? {
        get { handle.onResize }
        set { handle.onResize = newValue }
    }
    var onHover: ((Bool) -> Void)?
    private let handle = EdgeHandle()
    private var area: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(handle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The handle stays above the host, which is added after it.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== handle, handle.superview === self {
            addSubview(handle, positioned: .above, relativeTo: nil)
        }
    }

    /// Puts the handle at `frame` (hidden when nil) and the hover area over `hover`, both in
    /// window coordinates.
    func place(handle frame: NSRect?, hover: NSRect) {
        handle.isHidden = frame == nil
        if let frame, handle.frame != frame { handle.frame = frame }
        if area?.rect != hover {
            if let area { removeTrackingArea(area) }
            let new = NSTrackingArea(rect: hover, options: [.mouseEnteredAndExited, .activeAlways],
                                     owner: self, userInfo: nil)
            addTrackingArea(new)
            area = new
        }
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The notch's panel. It places itself exactly: its transparent margins may reach under the
/// menu bar or past the screen's edge, which AppKit would otherwise push the window back from.
private final class NotchPanel: FloatingPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Owns the notch window: a small tab at the screen's right edge that opens into the glance
/// when the pointer rests on it and opens Insights on a click.
@MainActor
final class NotchController {
    private let model: AppModel
    private let window = NotchPanel(shadow: false)
    private let container = NotchContainer()
    private let host: NSHostingView<NotchView>
    private let state = NotchState()
    private var changes: AnyCancellable?
    private var settingsChanges: AnyCancellable?
    /// Set while the notch is on screen; layout waits for `show()` otherwise.
    private var shown = false
    private var pinchFactor: Double = 1
    private var openWork: DispatchWorkItem?
    /// The close that's waiting to fire, nil when none is.
    private var closeWork: DispatchWorkItem?
    /// The window frame the last layout aimed for, which an animation may not have reached yet.
    private var lastTarget: NSRect?
    /// True while the window shrinks on close: the glass keeps its open size until it's done.
    private var closing = false
    /// A drag on the inner edge: the width it started at (points at text size 1) and the
    /// width it's at now.
    private var resizing: (startWidth: Double, width: Double)?

    init(model: AppModel, actions: AppActions) {
        self.model = model
        host = NSHostingView(rootView: NotchView(model: model, actions: actions, state: state))
        container.addSubview(host)
        host.autoresizingMask = [.width, .height]
        window.contentView = container
        window.level = DockController.aboveDock
        container.onResize = { [weak self] phase in self?.resize(phase) }
        container.onHover = { [weak self] inside in self?.hover(inside) }
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        settingsChanges = model.settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show() {
        shown = true
        layout()
        window.orderFrontRegardless()
        NotificationCenter.default.post(name: .tideWavesRecheck, object: nil)
    }

    func hide() {
        shown = false
        resizing = nil
        openWork?.cancel()
        closeWork?.cancel()
        closeWork = nil
        closing = false
        lastTarget = nil
        if state.open { state.open = false }
        window.orderOut(nil)
        NotificationCenter.default.post(name: .tideWavesRecheck, object: nil)   // the waves stop drifting
    }

    /// Resizes live while pinching, and keeps the size when the pinch ends.
    func pinch(_ magnification: Double, ended: Bool) {
        if ended {
            pinchFactor = 1
            model.settings.sizeScale = WidgetLayout.clampSize(
                model.settings.sizeScale * magnification)
        } else {
            pinchFactor = WidgetLayout.clampSize(model.settings.sizeScale * magnification)
                / model.settings.sizeScale
        }
        layout()
    }

    // MARK: Hover

    /// The pointer rests on the glass: open after a beat; leaves: close after a longer one.
    /// The resize handle isn't part of the hover area at rest, so reaching it opens nothing.
    private func hover(_ inside: Bool) {
        if inside {
            closeWork?.cancel()
            closeWork = nil
            guard !state.open, resizing == nil else { return }
            schedule(&openWork, after: 0.08) { [weak self] in
                guard let self, self.resizing == nil else { return }
                self.setOpen(true)
            }
        } else {
            openWork?.cancel()
            guard state.open else { return }
            schedule(&closeWork, after: 0.3) { [weak self] in
                self?.closeWork = nil
                self?.setOpen(false)
            }
        }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval,
                          _ body: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { body() } }
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setOpen(_ open: Bool) {
        guard state.open != open else { return }
        if open { closing = false }
        state.open = open
        layout(animated: true)
    }

    // MARK: Resizing

    /// A drag on the inner (left) edge: pulling it left widens the notch. The width is saved
    /// on release.
    private func resize(_ phase: ResizePhase) {
        switch phase {
        case .began:
            openWork?.cancel()
            let width = NotchSizing.clampRest(settings.notchWidth, orgs: model.orgs.count)
            resizing = (width, width)
        case .moved(let dx):
            guard var r = resizing else { return }
            r.width = NotchSizing.clampRest(r.startWidth - Double(dx / state.k),
                                            orgs: model.orgs.count)
            resizing = r
            layout()
        case .ended:
            guard let r = resizing else { return }
            resizing = nil
            if abs(r.width - r.startWidth) >= 0.5 { settings.notchWidth = r.width }
            layout()
        }
    }

    private var settings: Settings { model.settings }

    // MARK: Layout

    /// Sizes and places the window for the state (open or at rest) on the primary display,
    /// and tells the view where the glass is inside it.
    private func layout(animated: Bool = false) {
        guard shown else { return }
        // A resize whose mouse-up got lost would otherwise block layout for good.
        if resizing != nil, NSEvent.pressedMouseButtons & 1 == 0 { resize(.ended); return }
        guard let screen = NSScreen.screens.first else { return }
        let tile = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        let k = CGFloat(DockFit.contentScale(screen: screen.frame, visible: screen.visibleFrame, tileSize: tile)
                        * settings.sizeScale * pinchFactor)
        let orgs = model.orgs.count, advice = model.advice != nil
        let restWidth = NotchSizing.clampRest(resizing?.width ?? settings.notchWidth, orgs: orgs)
        let size = state.open
            ? CGSize(width: NotchSizing.openWidth(orgs: orgs, size: settings.notchOpensTo, advice: advice,
                                                  restWidth: restWidth, status: model.leftStatusMood) * k,
                     height: NotchSizing.openHeight * k)
            : CGSize(width: restWidth * k, height: NotchSizing.restHeight * k)
        let frames = NotchPlacement.frames(size: size, place: settings.notchPlace, look: settings.notchLook,
                                           screen: screen.frame, visible: screen.visibleFrame, scale: Double(k))
        let island = settings.notchLook == .island
        let inset = island ? CGFloat(NotchPlacement.shadowMargin) * k : 0
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let moves = frames.window != lastTarget
        // Closing animates the window down over the open glass, a reverse reveal into the corner;
        // the glass takes the rest size when that's done.
        if moves, !state.open, state.glassSize != size, animated, !still, window.isVisible {
            closing = true
        }
        if state.open || !closing, state.glassSize != size { state.glassSize = size }
        if state.look != settings.notchLook { state.look = settings.notchLook }
        if state.place != settings.notchPlace { state.place = settings.notchPlace }
        if state.trailingInset != inset { state.trailingInset = inset }
        if state.edgeInset != inset { state.edgeInset = inset }
        if state.k != k { state.k = k }
        if state.restWidth != restWidth { state.restWidth = restWidth }

        if moves {
            lastTarget = frames.window
            if animated, !still, window.isVisible {
                // The host follows the container by autoresizing; setting its frame to the final
                // bounds here would add the change twice.
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(frames.window, display: true)
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.closing else { return }
                        self.closing = false
                        if !self.state.open { self.layout() }
                    }
                })
            } else {
                closing = false
                if state.glassSize != size { state.glassSize = size }
                window.setFrame(frames.window, display: true)
                host.frame = container.bounds
            }
        }
        // In the window's own (y up) coordinates, as the window will be once placed.
        let local = frames.glass.offsetBy(dx: -frames.window.minX, dy: -frames.window.minY)
        let handle = state.open ? nil
            : NSRect(x: local.minX, y: local.minY, width: 6, height: local.height)
        // At rest the hover area stops short of the handle, so the pointer can reach it.
        var area = local
        if !state.open { area.origin.x += 6; area.size.width -= 6 }
        container.place(handle: handle, hover: area)
        // Replacing the tracking area sends no exit: an open notch that no longer holds the
        // pointer (a narrower card, a smaller one after a model change) must still close.
        // A close already waiting isn't pushed back by each layout.
        if state.open, closeWork == nil, !frames.glass.contains(NSEvent.mouseLocation) { hover(false) }
    }
}
