import SwiftUI
import TidemarkCore

/// A plan slot's background (the mockups' `tide_water`): the plan's seven days left to right, the water
/// rising as the week fills, and any locked time hatched red.
///
/// - `level`: the water sits at how full the plan is, with two drifting waves and a dashed tidemark where
///   an even pace would have it by now.
/// - `week`: the surface traces how the week filled up to now, a paler forecast runs on to
///   `chart.forecastEnd` along a dashed line, and a faint line marks now.
///
/// The hatch shows from `chart.lockedFrom` when `locked`. The water rises (or falls) to a new level over
/// 1.8 s when the reading changes. Reduce Motion, image renders and `isOld` keep it still; `isOld` also
/// dims the water to 55%.
///
/// Energy: the days, hatch, tidemark and forecast are drawn in a SwiftUI `Canvas` that only redraws when the
/// data changes. The drifting waves are Core Animation layers (`TideWaves`) that the window server moves at
/// about 12 frames a second, and whose animations are taken away whenever `WaveGate` says to stand still
/// (window hidden or covered, screens asleep, session resigned, Reduce Motion, an old reading). When they
/// can't drift (renders, Reduce Motion, an old reading) the whole picture is one still `Canvas` instead.
struct TideWater: View, Equatable {
    let chart: LeftChart
    let style: TideStyle
    let locked: Bool
    let isOld: Bool
    /// The plan, so a slot that is built again (the notch opening) doesn't make the water rise from empty again.
    let planID: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle

    /// What fraction of the plan is used now, 0...1; what the rise animates. (An object, not `@State`:
    /// the macro behind `@State` isn't available to a Command Line Tools build.)
    private final class Rise: ObservableObject { @Published var shown: Double? }
    @StateObject private var rise = Rise()

    private var target: Double { Self.used(chart) }
    private var moves: Bool { !reduceMotion && renderStyle == .live }

    init(chart: LeftChart, style: TideStyle, locked: Bool, isOld: Bool, planID: String = "") {
        self.chart = chart
        self.style = style
        self.locked = locked
        self.isOld = isOld
        self.planID = planID
    }

    static func == (a: TideWater, b: TideWater) -> Bool {
        a.chart == b.chart && a.style == b.style && a.locked == b.locked && a.isOld == b.isOld && a.planID == b.planID
    }

    /// The last level each plan's water showed, so it only rises when the reading really changed.
    @MainActor private enum Memory { static var level: [String: Double] = [:] }

    /// Used now, 0...1: the chart's now point, or its last point for last week.
    static func used(_ chart: LeftChart) -> Double {
        min(1, max(0, 1 - (chart.now?.y ?? chart.left.last?.y ?? 1)))
    }

    var body: some View {
        let animate = moves && !isOld
        let start = animate ? (planID.isEmpty ? 0 : Memory.level[planID] ?? 0) : target
        let water = Surface(chart: chart, style: style, locked: locked, palette: TidePalette.for(scheme), dark: scheme == .dark,
                            level: rise.shown ?? start, target: target, drifting: animate, dimmed: isOld)
        water
            .onAppear {
                // An old reading holds still; so does a plan whose level hasn't changed since it was last shown.
                guard animate else { rise.shown = target; remember(target); return }
                rise.shown = start
                remember(target)
                withAnimation(Self.riseCurve) { rise.shown = target }
            }
            .onChange(of: target) { _, new in
                remember(new)
                if animate { withAnimation(Self.riseCurve) { rise.shown = new } } else { rise.shown = new }
            }
            .accessibilityHidden(true)
    }

    private func remember(_ level: Double) { if !planID.isEmpty { Memory.level[planID] = level } }

    static let riseCurve = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.8)

    /// The drawing, with `level` as its animatable value.
    private struct Surface: View, Animatable {
        let chart: LeftChart
        let style: TideStyle
        let locked: Bool
        let palette: TidePalette
        let dark: Bool
        var level: Double
        let target: Double
        /// The waves are Core Animation layers between two canvases; else one canvas draws everything still.
        let drifting: Bool
        let dimmed: Bool

        var animatableData: Double {
            get { level }
            set { level = newValue }
        }

        private enum Pass { case below, above, all }

        var body: some View {
            if drifting {
                ZStack {
                    Canvas { ctx, size in draw(&ctx, size, .below, waves: false) }
                    TideWaves(style: style, level: level, dark: dark)
                    Canvas { ctx, size in draw(&ctx, size, .above, waves: false) }
                }
            } else {
                Canvas { ctx, size in draw(&ctx, size, .all, waves: true) }
            }
        }

        /// `below`: the days, hatch and the week's filled areas; `above`: the tidemark and the lines on top of
        /// the water. `waves` draws the level waves and the shimmer here too (one still picture).
        private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ pass: Pass, waves: Bool) {
            let p = palette, w = size.width, h = size.height
            let nowX = chart.now?.x ?? 1
            func y(_ used: Double) -> CGFloat { h - CGFloat(used) * (h - 6) }
            let ink = p.fg
            let dim = dimmed ? 0.55 : 1.0
            let below = pass != .above, above = pass != .below

            let fill = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [.init(color: p.sea1.opacity(0.85), location: 0), .init(color: p.sea3.opacity(0.95), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h))
            var water = ctx
            water.opacity = dim

            if below {
                // The days gone, a shade lighter, and six day lines.
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w * nowX, height: h)), with: .color(ink.opacity(0.035)))
                var lines = Path()
                for i in 1...6 {
                    lines.move(to: CGPoint(x: w * CGFloat(i) / 7, y: 0))
                    lines.addLine(to: CGPoint(x: w * CGFloat(i) / 7, y: h))
                }
                ctx.stroke(lines, with: .color(ink.opacity(0.07)), lineWidth: 1)

                if locked, let from = chart.lockedFrom {
                    let region = Path(CGRect(x: w * from, y: 0, width: w * (1 - from), height: h))
                    TideHatch.fill(&ctx, region: region, spacing: 5, stripe: 1.2,
                                   stripeColor: p.redMark.opacity(0.4), base: p.redMark.opacity(0.09))
                }
            }

            switch style {
            case .level:
                if below, waves {
                    let top = y(level)
                    let shade = TideWaves.shade(palette: p, top: top, height: h)
                    var back = water; back.opacity = dim * 0.55
                    back.fill(TideWaves.wave(w: w, h: h, top: top + 2.5, amp: 2.4, shift: -48), with: shade)
                    var front = water; front.opacity = dim * 0.9
                    front.fill(TideWaves.wave(w: w, h: h, top: top, amp: 2.8, shift: 0), with: shade)
                }
                if above {
                    // Where an even pace would have the water by now.
                    let mark = y(nowX)
                    var tide = Path()
                    tide.move(to: CGPoint(x: 0, y: mark)); tide.addLine(to: CGPoint(x: w, y: mark))
                    ctx.stroke(tide, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            case .week:
                // The surface follows what's used, scaled so a new reading rises to its place.
                let scale = target == 0 ? 1 : level / target
                if below {
                    var area = Path()
                    area.move(to: CGPoint(x: 0, y: h))
                    var last = CGPoint(x: 0, y: h)
                    for pt in chart.left {
                        last = CGPoint(x: w * pt.x, y: y((1 - pt.y) * scale))
                        area.addLine(to: last)
                    }
                    area.addLine(to: CGPoint(x: last.x, y: h))
                    area.closeSubpath()
                    var body = water; body.opacity = dim * 0.92
                    body.fill(area, with: fill)
                    if waves {
                        var shimmer = water; shimmer.opacity = dim * 0.35
                        shimmer.stroke(TideWaves.ridge(w: w, y: h - 3, shift: 0), with: .color(p.moon), lineWidth: 1)
                    }
                    if let end = chart.forecastEnd, let now = chart.now {
                        let from = CGPoint(x: w * now.x, y: y((1 - now.y) * scale))
                        let to = CGPoint(x: w * end.x, y: y(1 - end.y))
                        var ahead = Path()
                        ahead.move(to: CGPoint(x: from.x, y: h)); ahead.addLine(to: from)
                        ahead.addLine(to: to); ahead.addLine(to: CGPoint(x: to.x, y: h)); ahead.closeSubpath()
                        var paler = water; paler.opacity = dim * 0.28
                        paler.fill(ahead, with: fill)
                    }
                }
                if above {
                    if let end = chart.forecastEnd, let now = chart.now {
                        var dash = Path()
                        dash.move(to: CGPoint(x: w * now.x, y: y((1 - now.y) * scale)))
                        dash.addLine(to: CGPoint(x: w * end.x, y: y(1 - end.y)))
                        ctx.stroke(dash, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    }
                    if chart.now != nil {
                        var line = Path()
                        line.move(to: CGPoint(x: w * nowX, y: 0)); line.addLine(to: CGPoint(x: w * nowX, y: h))
                        ctx.stroke(line, with: .color(ink.opacity(0.3)), lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: Core Animation waves

/// The drifting waves as layers: two filled waves for `.level` (7 s and 11 s, opposite ways), one shimmer line
/// for `.week`. Each is a 48 pt pattern wider than the slot, slid 48 pt along by a linear animation that the
/// window server steps at about 12 frames a second. The animations exist only while `WaveGate.runs`.
private struct TideWaves: NSViewRepresentable {
    let style: TideStyle
    let level: Double
    let dark: Bool

    func makeNSView(context: Context) -> WavesView { WavesView() }

    func updateNSView(_ view: WavesView, context: Context) { view.apply(style: style, level: level, dark: dark) }

    static func dismantleNSView(_ view: WavesView, coordinator: ()) { view.shutDown() }

    /// The gradient the water is filled with, from just above the surface to the bottom.
    static func shade(palette p: TidePalette, top: CGFloat, height h: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: [.init(color: p.sea1.opacity(0.85), location: 0), .init(color: p.sea3.opacity(0.95), location: 1)]),
                        startPoint: CGPoint(x: 0, y: top - 4), endPoint: CGPoint(x: 0, y: h))
    }

    /// `q 12 -amp 24 0 t 24 0` repeated, from x = -48, filled down to the bottom.
    static func wave(w: CGFloat, h: CGFloat, top: CGFloat, amp: CGFloat, shift: CGFloat) -> Path {
        var path = ridge(w: w, y: top, amp: amp, shift: shift)
        path.addLine(to: CGPoint(x: w + 96, y: h)); path.addLine(to: CGPoint(x: -48, y: h)); path.closeSubpath()
        return path
    }

    static func ridge(w: CGFloat, y: CGFloat, amp: CGFloat = 2, shift: CGFloat) -> Path {
        var path = Path()
        var x: CGFloat = -48 + shift
        path.move(to: CGPoint(x: x, y: y))
        while x < w + 48 {
            path.addQuadCurve(to: CGPoint(x: x + 24, y: y), control: CGPoint(x: x + 12, y: y - amp))
            path.addQuadCurve(to: CGPoint(x: x + 48, y: y), control: CGPoint(x: x + 36, y: y + amp))
            x += 48
        }
        return path
    }
}

extension Notification.Name {
    /// A window was ordered in or out: the waves in it check again whether they may drift.
    static let tideWavesRecheck = Notification.Name("TidemarkTideWavesRecheck")
}

private final class WavesView: NSView {
    private var style: TideStyle = .level
    private var level = 0.0
    private var dark = false
    private var builtSize = CGSize.zero
    private var builtKey = ""
    private var gate = WaveGate()
    private var centre: [NSObjectProtocol] = []
    private var workspace: [NSObjectProtocol] = []
    /// The layers that slide, with their direction and period.
    private var drifters: [(layer: CALayer, period: CFTimeInterval, reversed: Bool)] = []
    private var waves: [(grad: CAGradientLayer, mask: CAShapeLayer, offset: CGFloat, amp: CGFloat)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Never takes a click: the slot under it does.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(style: TideStyle, level: Double, dark: Bool) {
        let key = "\(style)-\(dark)"
        let rebuild = key != builtKey
        self.style = style; self.level = level; self.dark = dark
        if rebuild { build() } else { place() }
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { build() }
    }

    // MARK: Layers

    private var palette: TidePalette { dark ? .dusk : .dawn }

    private func build() {
        guard bounds.width > 0, bounds.height > 0, let host = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stopDrifting()
        host.sublayers = nil
        drifters = []
        waves = []
        builtSize = bounds.size
        builtKey = "\(style)-\(dark)"
        let p = palette
        switch style {
        case .level:
            // Back wave first: fainter, slower, the other way.
            for (opacity, offset, amp, period, reversed) in [(0.55, CGFloat(2.5), CGFloat(2.4), 11.0, true), (0.9, 0, 2.8, 7.0, false)] {
                let grad = CAGradientLayer()
                grad.frame = bounds
                grad.opacity = Float(opacity)
                grad.colors = [NSColor(p.sea1).withAlphaComponent(0.85).cgColor, NSColor(p.sea3).withAlphaComponent(0.95).cgColor]
                let mask = CAShapeLayer()
                mask.frame = bounds
                mask.fillColor = NSColor.black.cgColor
                grad.mask = mask
                host.addSublayer(grad)
                waves.append((grad, mask, offset, amp))
                drifters.append((mask, period, reversed))
            }
        case .week:
            let shimmer = CAShapeLayer()
            shimmer.frame = bounds
            shimmer.fillColor = nil
            shimmer.strokeColor = NSColor(p.moon).cgColor
            shimmer.lineWidth = 1
            shimmer.opacity = 0.35
            let ridge = TideWaves.ridge(w: bounds.width, y: bounds.height - 3, shift: 0)
            shimmer.path = Self.flipped(ridge, height: bounds.height)
            host.addSublayer(shimmer)
            drifters.append((shimmer, 7, false))
        }
        place()
        refreshGate()
    }

    /// Moves the water to the current level (the rise calls this every frame while it lasts).
    private func place() {
        guard style == .level, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let w = bounds.width, h = bounds.height
        let top = h - CGFloat(level) * (h - 6)
        for wave in waves {
            wave.mask.path = Self.flipped(TideWaves.wave(w: w, h: h, top: top + wave.offset, amp: wave.amp, shift: 0), height: h)
            // The gradient starts 4 pt above the surface and ends at the bottom (the layer's y runs up).
            wave.grad.startPoint = CGPoint(x: 0, y: 1 - (top - 4) / h)
            wave.grad.endPoint = CGPoint(x: 0, y: 0)
        }
    }

    /// A SwiftUI path (y down) as a layer path (y up).
    private static func flipped(_ path: Path, height: CGFloat) -> CGPath {
        path.cgPath.copy(using: [CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)]) ?? path.cgPath
    }

    // MARK: Going and stopping

    private func startDrifting() {
        for d in drifters where d.layer.animation(forKey: "drift") == nil {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = d.reversed ? -48 : 0
            slide.toValue = d.reversed ? 0 : -48
            slide.duration = d.period
            slide.repeatCount = .infinity
            slide.timingFunction = CAMediaTimingFunction(name: .linear)
            // A slow drift needs no more than about 12 steps a second.
            slide.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
            d.layer.add(slide, forKey: "drift")
        }
    }

    private func stopDrifting() {
        for d in drifters { d.layer.removeAnimation(forKey: "drift") }
    }

    /// Whether the waves may drift now, from the window's state and the Mac's; starts or stops them to match.
    private func refreshGate() {
        gate.windowVisible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        gate.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if gate.runs { startDrifting() } else { stopDrifting() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shutDown()
        guard let window else { return }
        let center = NotificationCenter.default
        let recheck: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.refreshGate() } }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            centre.append(center.addObserver(forName: name, object: window, queue: .main, using: recheck))
        }
        centre.append(center.addObserver(forName: .tideWavesRecheck, object: nil, queue: .main, using: recheck))
        let shared = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ change: @escaping (inout WaveGate) -> Void) {
            workspace.append(shared.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(&self.gate)
                    self.refreshGate()
                }
            })
        }
        watch(NSWorkspace.screensDidSleepNotification) { $0.screensAwake = false }
        watch(NSWorkspace.screensDidWakeNotification) { $0.screensAwake = true }
        watch(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true }
        watch(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { _ in }
        refreshGate()
    }

    /// Takes the animations away and stops listening: the view left its window.
    func shutDown() {
        stopDrifting()
        gate.windowVisible = false
        for token in centre { NotificationCenter.default.removeObserver(token) }
        for token in workspace { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        centre = []
        workspace = []
    }
}
