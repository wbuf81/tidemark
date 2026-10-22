import AppKit
import QuartzCore
import TidemarkCore

/// What moves on a menu bar battery: bubbles rising inside the battery of the plan Claude Code is working on,
/// or a blue dot when it needs you. They are Core Animation layers on the status item's button, so the window
/// server steps them (about 10 frames a second) and Tidemark does no per-frame work. `MenuBarBatteries.effect`
/// decides what shows; the animations exist only while it says so and are removed (not hidden) otherwise:
/// battery not on screen, screens asleep, session resigned, Reduce Motion, or Claude Code not at work.
@MainActor
final class BatteryEffects {
    /// The look of a bubble (the mockup's `.bub`), in points from the battery's bottom-left corner.
    struct Bubble {
        var x: CGFloat, dx: CGFloat, delay: Double
        static let all = [Bubble(x: 4, dx: 1, delay: 0), Bubble(x: 8, dx: -1, delay: 0.55), Bubble(x: 6, dx: 1, delay: 1.1)]
        static let size: CGFloat = 3, bottom: CGFloat = 2, rise: CGFloat = 9, cycle: Double = 1.6
        /// Where in its rise a bubble is `t` seconds into the cycle: 0...1.
        func progress(at t: Double) -> CGFloat {
            var p = (t - delay).truncatingRemainder(dividingBy: Bubble.cycle) / Bubble.cycle
            if p < 0 { p += 1 }
            return CGFloat(p)
        }
        /// Opacity at a progress: in over the first 15%, then out by the top.
        static func opacity(_ p: CGFloat) -> CGFloat { p < 0.15 ? 0.95 * p / 0.15 : 0.95 * (1 - p) / 0.85 }
    }
    static let dotColor = NSColor(srgbRed: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255, alpha: 1)
    static let dotSize: CGFloat = 7, dotRing: CGFloat = 1.5
    /// The dot's centre, beyond the battery's top-right corner (the mockup's `right: -4px; top: -4px`).
    static func dotCentre(batteryWidth w: CGFloat) -> CGPoint { CGPoint(x: w + 0.5, y: -0.5) }   // y from the battery's top, up is negative
    static let frameRate = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)

    private final class Entry {
        weak var button: NSStatusBarButton?
        var item: MenuBarBatteries.Item
        var prefix: CGFloat
        var titleWidth: CGFloat
        var container: CALayer?
        var shown: MenuBarBatteries.Effect?
        var dark = false
        var frameWatch: NSObjectProtocol?
        init(button: NSStatusBarButton, item: MenuBarBatteries.Item, prefix: CGFloat, titleWidth: CGFloat) {
            self.button = button; self.item = item; self.prefix = prefix; self.titleWidth = titleWidth
        }
    }

    private var entries: [String: Entry] = [:]
    private var gate = WaveGate()
    private var tokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var listening = false

    /// Tells the effects what a battery's button now shows. Pass `.none` activity to take its effects away.
    func update(id: String, button: NSStatusBarButton, item: MenuBarBatteries.Item) {
        let title = MenuBarIcon.batteryTitle(item)
        let entry = entries[id] ?? Entry(button: button, item: item, prefix: 0, titleWidth: 0)
        entry.button = button
        entry.item = item
        entry.prefix = MenuBarIcon.batteryOffset(in: title)
        entry.titleWidth = title.size().width
        if entries[id] == nil {
            entries[id] = entry
            button.postsFrameChangedNotifications = true
            entry.frameWatch = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layOut(id) }
            }
        }
        refresh()
        // The button resizes to the new title on the next layout pass; place the layers then too.
        DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.layOut(id) } }
    }

    /// Takes away the effects of batteries that left the menu bar.
    func keep(_ ids: [String]) {
        for id in entries.keys where !ids.contains(id) { drop(id) }
        refresh()
    }

    func removeAll() { keep([]) }

    // MARK: The gate

    private func listen() {
        guard !listening else { return }
        listening = true
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        let shared = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ change: @escaping (inout WaveGate) -> Void) {
            workspaceTokens.append(shared.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(&self.gate)
                    self.refresh()
                }
            })
        }
        watch(NSWorkspace.screensDidSleepNotification) { $0.screensAwake = false }
        watch(NSWorkspace.screensDidWakeNotification) { $0.screensAwake = true }
        watch(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        watch(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { _ in }
    }

    private func stopListening() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens = []; workspaceTokens = []
        listening = false
    }

    /// Re-decides every battery: adds the layers and animations that should run, removes the rest. Listens to the
    /// system only while some battery has something to show.
    private func refresh() {
        gate.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if entries.values.contains(where: { $0.item.activity != .none }) { listen() } else { stopListening() }
        for entry in entries.values {
            var g = gate
            g.windowVisible = entry.button?.window?.occlusionState.contains(.visible) == true
            let effect = MenuBarBatteries.effect(entry.item.activity, gate: g)
            let dark = entry.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if effect != entry.shown || dark != entry.dark || (effect.bubbles || effect.dot) != (entry.container != nil) {
                entry.shown = effect
                entry.dark = dark
                build(entry, effect)
            }
        }
    }

    private func drop(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.container?.removeAllAnimations()
        entry.container?.sublayers?.forEach { $0.removeAllAnimations() }
        entry.container?.removeFromSuperlayer()
        entry.container = nil
        if let token = entry.frameWatch { NotificationCenter.default.removeObserver(token) }
    }

    // MARK: Layers

    private func layOut(_ id: String) {
        guard let entry = entries[id], let button = entry.button, let container = entry.container else { return }
        let size = MenuBarIcon.batterySize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = CGRect(x: ((button.bounds.width - entry.titleWidth) / 2 + entry.prefix).rounded(),
                                 y: ((button.bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        CATransaction.commit()
    }

    /// Replaces the entry's layers with the ones `effect` calls for: none at all when it has nothing to show,
    /// so nothing is left animating.
    private func build(_ entry: Entry, _ effect: MenuBarBatteries.Effect) {
        if let old = entry.container {
            old.sublayers?.forEach { $0.removeAllAnimations() }
            old.removeAllAnimations()
            old.removeFromSuperlayer()
            entry.container = nil
        }
        guard (effect.bubbles || effect.dot), let button = entry.button else { return }
        button.wantsLayer = true
        guard let host = button.layer else { return }
        let size = MenuBarIcon.batterySize
        let flipped = host.isGeometryFlipped
        // y measured up from the battery's bottom, in the layer's own direction.
        func y(_ up: CGFloat) -> CGFloat { flipped ? size.height - up : up }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let container = CALayer()
        container.frame = CGRect(x: ((button.bounds.width - entry.titleWidth) / 2 + entry.prefix).rounded(),
                                 y: ((button.bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        host.addSublayer(container)
        entry.container = container
        if effect.bubbles {
            let inkIsFill = entry.item.fill == .ink
            let colour = MenuBarIcon.ink(dark: dark, inverse: inkIsFill).cgColor
            for bubble in Bubble.all {
                let layer = CALayer()
                layer.bounds = CGRect(x: 0, y: 0, width: Bubble.size, height: Bubble.size)
                layer.cornerRadius = Bubble.size / 2
                layer.backgroundColor = colour
                layer.opacity = 0
                let start = CGPoint(x: bubble.x + Bubble.size / 2, y: y(Bubble.bottom + Bubble.size / 2))
                let end = CGPoint(x: start.x + bubble.dx, y: y(Bubble.bottom + Bubble.size / 2 + Bubble.rise))
                layer.position = start
                container.addSublayer(layer)
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = start; move.toValue = end
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.6; grow.toValue = 1
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 0.95, 0]; fade.keyTimes = [0, 0.15, 1]
                let group = CAAnimationGroup()
                group.animations = [move, grow, fade]
                group.duration = Bubble.cycle
                group.repeatCount = .infinity
                group.timingFunction = CAMediaTimingFunction(name: .linear)
                group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + bubble.delay
                group.fillMode = .backwards
                group.preferredFrameRateRange = Self.frameRate
                layer.add(group, forKey: "bubble")
            }
        }
        if effect.dot {
            let ring = Self.dotSize + 2 * Self.dotRing
            let centre = Self.dotCentre(batteryWidth: size.width)
            let group = CALayer()
            group.bounds = CGRect(x: 0, y: 0, width: ring, height: ring)
            group.position = CGPoint(x: centre.x, y: y(size.height - centre.y))
            let halo = CALayer()
            halo.frame = group.bounds
            halo.cornerRadius = ring / 2
            halo.backgroundColor = MenuBarIcon.barColor(dark: dark).cgColor
            let dot = CALayer()
            dot.frame = CGRect(x: Self.dotRing, y: Self.dotRing, width: Self.dotSize, height: Self.dotSize)
            dot.cornerRadius = Self.dotSize / 2
            dot.backgroundColor = Self.dotColor.cgColor
            group.addSublayer(halo); group.addSublayer(dot)
            container.addSublayer(group)
            if effect.pulse {
                let pulse = CABasicAnimation(keyPath: "transform.scale")
                pulse.fromValue = 1; pulse.toValue = 1.35
                pulse.autoreverses = true
                pulse.duration = 0.7
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pulse.preferredFrameRateRange = Self.frameRate
                group.add(pulse, forKey: "pulse")
            }
        }
    }
}
