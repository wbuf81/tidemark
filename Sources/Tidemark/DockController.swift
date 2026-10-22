import AppKit
import Combine
import SwiftUI
import TidemarkCore

/// Owns the always-on widget window: one widget at the owner's width (narrowed beside the
/// Dock).
@MainActor
final class DockController {
    private let model: AppModel
    // No window shadow: the Dock has none, and on glass it reads as a dark outline.
    private let widget = FloatingPanel(shadow: false)
    private let container = WidgetContainer()
    private let host: NSHostingView<WidgetView>
    /// Reads the Dock's real frame when the owner turns on measuring it.
    private let dockWatcher = DockWatcher()
    private var changes: AnyCancellable?
    private var settingsChanges: AnyCancellable?
    /// Set while the widget is on screen; layout waits for `show()` otherwise.
    private var shown = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var pinchFactor: Double = 1
    /// The owner scale the widget is drawn at now, after fitting it on screen.
    private var appliedScale: Double = 1
    /// The glass at rest: what moving and snapping go by.
    private var glassFrame = NSRect.zero
    /// The widget's outer edges, which stay put as it resizes: the right one in the right half
    /// of the screen, the left one in the left half.
    private var anchor = GrowthAnchor(.right, .bottom)
    /// A drag on the inner edge: the width it started at (points at text size 1), the glass
    /// then, and the width it's at now.
    private var resizing: (startWidth: Double, startGlass: NSRect, width: Double)?

    init(model: AppModel, actions: AppActions) {
        self.model = model
        host = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        // Reports its size (for `fittingSize`); `layout` sets its frame.
        host.sizingOptions = [.intrinsicContentSize]
        container.addSubview(host)
        widget.contentView = container
        widget.level = .floating
        // The resize handle sets its cursor on every move, which a background app only gets this way.
        widget.acceptsMouseMovedEvents = true
        container.onResize = { [weak self] phase in self?.resize(phase) }
        host.autoresizingMask = [.width, .height]
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        settingsChanges = model.settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.followMeasureDock(); self?.layout() } }
        }
        dockWatcher.onChange = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        followMeasureDock()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // Apps that open or quit change the Dock's width.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            }
        }
    }

    /// Runs the Dock watcher only while the widget is on screen and Settings asks for it
    /// (starting a running one does nothing).
    private func followMeasureDock() {
        if shown && model.settings.measureDock { dockWatcher.start() } else { dockWatcher.stop() }
    }

    func requestDockAccess() { dockWatcher.requestAccess() }

    func openDockAccessSettings() { dockWatcher.openAccessSettings() }

    var dockAccessAllowed: Bool { dockWatcher.isAllowed }

    func show() {
        shown = true
        followMeasureDock()
        layout()
        widget.orderFrontRegardless()
        NotificationCenter.default.post(name: .tideWavesRecheck, object: nil)
    }

    /// Orders the widget out; the caller brings it back with `show()`.
    func hide() {
        shown = false
        followMeasureDock()
        resizing = nil
        widget.orderOut(nil)
        NotificationCenter.default.post(name: .tideWavesRecheck, object: nil)   // the waves stop drifting
    }

    /// Moves the widget with the mouse. Screen coordinates, so the window moving under the
    /// pointer doesn't disturb the drag.
    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, widget.frame.origin)
        }
        guard let start = dragStart else { return }
        widget.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    /// Near one of the six snap points the widget snaps there; anywhere else it stays put.
    func dragEnded() {
        guard let start = dragStart else { return }
        dragStart = nil
        guard let screen = NSScreen.screens.first else { return }
        // The glass, moved as far as the window was.
        let glass = glassFrame.offsetBy(dx: widget.frame.minX - start.origin.x, dy: widget.frame.minY - start.origin.y)
        let dockWidth = dockWidth(on: screen)
        if let point = WidgetPlacement.snap(frame: glass, screen: screen.frame, visible: screen.visibleFrame,
                                            dockWidth: dockWidth,
                                            width: model.vertical ? nil : { self.drawnWidth(at: $0, screen: screen, dockWidth: dockWidth) }) {
            model.settings.widgetSpot = .snapped(point)
        } else {
            model.settings.widgetSpot = .free(WidgetPlacement.offset(origin: glass.origin, size: glass.size, screen: screen.frame))
        }
        layout()
    }

    /// The width the widget would be drawn at snapped to `point`, on screen: the owner's,
    /// narrowed to the gap beside the Dock there.
    private func drawnWidth(at point: SnapPoint, screen: NSScreen, dockWidth: Double?) -> Double {
        let orgs = model.orgs.count, advice = model.advice != nil
        let wanted = WidgetSizing.clampWidth(model.settings.widgetWidth, orgs: orgs, advice: advice)
        let minimum = WidgetSizing.widthRange(orgs: orgs, advice: advice).lowerBound
        let scale = Double(model.widgetScale)
        return WidgetSizing.fittedWidth(wanted: wanted * scale, minimum: minimum * scale, spot: .snapped(point),
                                        fitBesideDock: model.settings.fitBesideDock, screen: screen.frame,
                                        visible: screen.visibleFrame, dockWidth: dockWidth)
    }

    func place(_ point: SnapPoint) {
        model.settings.widgetSpot = .snapped(point)
        layout()
    }

    func setLayout(_ choice: LayoutChoice) {
        model.settings.layoutChoice = choice
        layout()
    }

    func setSize(_ scale: Double) {
        model.settings.sizeScale = WidgetLayout.clampSize(scale)
        layout()
    }

    /// Resizes live while pinching, and keeps the size when the pinch ends.
    func pinch(_ magnification: Double, ended: Bool) {
        if ended {
            pinchFactor = 1
            model.settings.sizeScale = WidgetLayout.clampSize(model.settings.sizeScale * magnification)
        } else {
            pinchFactor = WidgetLayout.clampSize(model.settings.sizeScale * magnification) / model.settings.sizeScale
        }
        layout()
    }

    /// The width from Settings: the strip's when the widget stands on a side.
    func setWidth(_ width: Double) {
        if model.vertical { model.settings.stripWidth = WidgetSizing.clampStrip(width) }
        else { model.settings.widgetWidth = clampedWidth(width) }
        layout()
    }

    private func clampedWidth(_ width: Double) -> Double {
        model.vertical ? WidgetSizing.clampStrip(width)
            : WidgetSizing.clampWidth(width, orgs: model.orgs.count, advice: model.advice != nil)
    }

    // MARK: Resizing

    /// A drag on the inner edge: pulling it toward the middle of the screen widens the
    /// widget, and the layout changes as the width crosses each size. The width is saved on
    /// release; a widget dropped anywhere keeps its outer edge where it was.
    private func resize(_ phase: ResizePhase) {
        switch phase {
        case .began:
            let width = Double(model.vertical ? model.stripLayoutWidth : model.widgetLayoutWidth)
            resizing = (width, glassFrame, width)
        case .moved(let dx):
            guard var r = resizing else { return }
            let pull = anchor.horizontal == .right ? -Double(dx) : Double(dx)
            r.width = clampedWidth(r.startWidth + pull / Double(model.widgetScale))
            resizing = r
            layout()
        case .ended:
            guard let r = resizing else { return }
            resizing = nil
            if model.vertical {
                if let width = WidgetSizing.widthToSave(start: r.startWidth, end: r.width, saved: r.startWidth, narrowed: false) {
                    model.settings.stripWidth = width
                }
            } else {
                let saved = WidgetSizing.clampWidth(model.settings.widgetWidth, orgs: model.orgs.count,
                                                    advice: model.advice != nil)
                if let width = WidgetSizing.widthToSave(start: r.startWidth, end: r.width, saved: saved,
                                                        narrowed: r.startWidth < saved - 0.5) {
                    model.settings.widgetWidth = width
                }
            }
            if case .free? = model.settings.widgetSpot, let screen = NSScreen.screens.first {
                model.settings.widgetSpot = .free(WidgetPlacement.offset(origin: glassFrame.origin, size: glassFrame.size,
                                                                         screen: screen.frame))
            }
            layout()
        }
    }

    // MARK: Layout

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock, at the owner's width narrowed to
    /// the gap beside the Dock. Frames here are the glass.
    private func layout() {
        guard shown else { return }
        // A resize whose mouse-up got lost would otherwise block layout for good.
        if resizing != nil, NSEvent.pressedMouseButtons & 1 == 0 { resize(.ended); return }
        guard let screen = NSScreen.screens.first else { return }
        let settings = model.settings
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        // The owner's text size, shrunk only if the widget wouldn't fit on screen (size measured
        // from what's drawn now, divided back to scale 1).
        let current = host.fittingSize
        let vertical = WidgetLayout.isVertical(spot: settings.widgetSpot, choice: settings.layoutChoice)
        let contentScale = DockFit.contentScale(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize)
        var natural = CGSize(width: current.width / appliedScale, height: current.height / appliedScale)
        if !vertical {
            // From the width wanted, not the one drawn: that is narrowed by the scale chosen here.
            let wanted = WidgetSizing.clampWidth(resizing?.width ?? settings.widgetWidth, orgs: model.orgs.count,
                                                 advice: model.advice != nil)
            natural.width = wanted * contentScale
        }
        let ownerScale = WidgetLayout.fittedScale(settings.sizeScale * pinchFactor, natural: natural,
                                                  visible: screen.visibleFrame)
        let height = DockFit.height(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize) * ownerScale
        let scale = contentScale * ownerScale
        if abs(model.widgetHeight - height) > 0.5 || abs(model.widgetScale - scale) > 0.001 || model.vertical != vertical {
            model.widgetHeight = height  // these changes trigger another layout with the new size
            model.widgetScale = scale
            model.vertical = vertical
            appliedScale = ownerScale
            return
        }
        let dockWidth = dockWidth(on: screen)
        if vertical {
            let width = CGFloat(WidgetSizing.clampStrip(resizing?.width ?? settings.stripWidth))
            if abs(model.stripLayoutWidth - width) > 0.01 { model.stripLayoutWidth = width; return }
        } else {
            let orgs = model.orgs.count, advice = model.advice != nil
            let wanted = WidgetSizing.clampWidth(resizing?.width ?? settings.widgetWidth, orgs: orgs, advice: advice)
            let minimum = WidgetSizing.widthRange(orgs: orgs, advice: advice).lowerBound
            let drawn = WidgetSizing.fittedWidth(wanted: wanted * scale, minimum: minimum * scale, spot: settings.widgetSpot,
                                                 fitBesideDock: settings.fitBesideDock, screen: screen.frame,
                                                 visible: screen.visibleFrame, dockWidth: dockWidth) / scale
            if abs(Double(model.widgetLayoutWidth) - drawn) > 0.01 { model.widgetLayoutWidth = CGFloat(drawn); return }
        }
        guard dragStart == nil else { return }
        let size = glassSize()
        var origin = WidgetPlacement.origin(size: size, screen: screen.frame, visible: screen.visibleFrame,
                                            spot: settings.widgetSpot, dockWidth: dockWidth)
        // While resizing a widget dropped anywhere, its outer edge stays put.
        if let r = resizing, case .free? = settings.widgetSpot {
            let held = anchor.horizontal == .right ? r.startGlass.maxX - size.width : r.startGlass.minX
            origin.x = min(max(held, screen.frame.minX), screen.frame.maxX - size.width)
        }
        let glass = NSRect(origin: origin, size: size)
        if resizing == nil {
            anchor = WidgetPlacement.anchor(glass: glass, visible: screen.visibleFrame, spot: settings.widgetSpot)
        }
        glassFrame = glass
        let frame = glass
        widget.level = besideDock(origin: origin, screen: screen) ? Self.aboveDock : .floating
        if frame != widget.frame { widget.setFrame(frame, display: true) }
        host.frame = NSRect(origin: .zero, size: frame.size)
        placeHandle(glass: glass, in: frame)
    }

    /// The level one above the Dock's window.
    static let aboveDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    /// The widget sits beside a bottom Dock at the Dock's height (snapped to a bottom corner or
    /// never moved, where `WidgetPlacement.origin` chose that spot). There it floats one level
    /// above the Dock: the Dock's window covers the whole screen and swallows clicks, so a
    /// widget reaching under a Dock wider than estimated (minimized windows can't be counted)
    /// would lose its inner edge. Above it, the overlap is visible and the owner can drag the
    /// widget back.
    private func besideDock(origin: CGPoint, screen: NSScreen) -> Bool {
        switch model.settings.widgetSpot {
        case nil, .snapped(.bottomRight)?, .snapped(.bottomLeft)?: break
        default: return false
        }
        return screen.visibleFrame.minY > screen.frame.minY + 1 && abs(origin.y - (screen.frame.minY + 6)) < 0.5
    }

    /// The glass: the host's fitting size.
    private func glassSize() -> CGSize { host.fittingSize }

    /// Puts the resize handle along the glass's inner edge (the side facing the middle of the
    /// screen) and the glass's full height.
    private func placeHandle(glass: NSRect, in window: NSRect) {
        let width = EdgeHandle.width
        let x = anchor.horizontal == .right ? glass.minX : glass.maxX - width
        container.handleFrame = NSRect(x: x - window.minX, y: glass.minY - window.minY, width: width, height: glass.height)
    }

    /// The Dock's width: measured when the owner turned that on and the Dock's frame is known,
    /// otherwise estimated from its settings and the apps running now.
    private func dockWidth(on screen: NSScreen) -> Double? {
        // Only a Dock that reserves a bottom band (the gate the estimate uses too).
        if model.settings.measureDock, screen.visibleFrame.minY - screen.frame.minY > 20,
           let frame = dockWatcher.frame,
           let measured = DockFit.measuredWidth(frame, screen: screen.frame) {
            return measured
        }
        let dock = UserDefaults(suiteName: "com.apple.dock")
        // Spacers and web apps have no bundle id but still take a slot.
        func apps(_ key: String) -> [String] {
            (dock?.array(forKey: key) as? [[String: Any]] ?? []).enumerated().map { index, tile in
                (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String ?? "\(key)-\(index)"
            }
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)
        let contents = DockFit.contents(pinned: apps("persistent-apps"), recent: apps("recent-apps"), running: running,
                                        folders: dock?.array(forKey: "persistent-others")?.count ?? 0,
                                        showRecents: dock?.object(forKey: "show-recents") as? Bool ?? true)
        return DockFit.estimatedWidth(items: contents.items, dividers: contents.dividers,
                                      screen: screen.frame, visible: screen.visibleFrame)
    }
}
