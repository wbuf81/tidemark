import AppKit
import SwiftUI
import TidemarkCore

/// What the notch window shows: open or at rest, and the glass's size and corner. The view
/// pins the glass to that corner of its bounds, so it stays put while the window resizes.
final class NotchState: ObservableObject {
    @Published var open = false
    /// The glass's size, already multiplied by `k`.
    @Published var glassSize = CGSize.zero
    @Published var place = NotchPlace.topRight
    /// The look, set with the place and insets so they never disagree for a frame.
    @Published var look = NotchLook.hardware
    /// The glass's gap from the window's right edge, and from its top (top right) or bottom
    /// (bottom right) edge: 0 for the hardware look, the shadow margin for the island.
    @Published var trailingInset: CGFloat = 0
    @Published var edgeInset: CGFloat = 0
    @Published var k: CGFloat = 1
    /// The width at rest, in points at text size 1.
    @Published var restWidth: Double = 214
}

/// The hardware notch: flush to two screen edges, one rounded corner (16), and a flare (14)
/// where each free side meets an edge.
private struct HardwareNotchShape: Shape {
    var place: NotchPlace
    var glass: CGRect
    var radius: CGFloat
    var flare: CGFloat

    func path(in rect: CGRect) -> Path {
        let g = glass
        var p = Path()
        switch place {
        case .topRight:
            p.move(to: CGPoint(x: g.minX - flare, y: g.minY))
            p.addLine(to: CGPoint(x: g.maxX, y: g.minY))
            p.addLine(to: CGPoint(x: g.maxX, y: g.maxY + flare))
            p.addArc(tangent1End: CGPoint(x: g.maxX, y: g.maxY), tangent2End: CGPoint(x: g.minX, y: g.maxY), radius: flare)
            p.addArc(tangent1End: CGPoint(x: g.minX, y: g.maxY), tangent2End: CGPoint(x: g.minX, y: g.minY), radius: radius)
            p.addArc(tangent1End: CGPoint(x: g.minX, y: g.minY), tangent2End: CGPoint(x: g.minX - flare, y: g.minY), radius: flare)
        case .bottomRight:
            p.move(to: CGPoint(x: g.minX - flare, y: g.maxY))
            p.addLine(to: CGPoint(x: g.maxX, y: g.maxY))
            p.addLine(to: CGPoint(x: g.maxX, y: g.minY - flare))
            p.addArc(tangent1End: CGPoint(x: g.maxX, y: g.minY), tangent2End: CGPoint(x: g.minX, y: g.minY), radius: flare)
            p.addArc(tangent1End: CGPoint(x: g.minX, y: g.minY), tangent2End: CGPoint(x: g.minX, y: g.maxY), radius: radius)
            p.addArc(tangent1End: CGPoint(x: g.minX, y: g.maxY), tangent2End: CGPoint(x: g.minX - flare, y: g.maxY), radius: flare)
        }
        p.closeSubpath()
        return p
    }
}

/// The notch's colours in each look, light and dark.
extension NotchLook {
    private func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }

    /// The notch is always black, like the hardware one: every word on it is lifted to pass on black.
    func background(dark: Bool) -> Color { .black }

    /// The empty part of the hairline bars and the open card's bars.
    func track(dark: Bool) -> Color { Palette.notchTrack }

    /// The island's 1 pt edge; the hardware notch has none.
    func border(dark: Bool) -> Color {
        switch self {
        case .hardware: .clear
        case .island: Color.white.opacity(0.14)
        }
    }

    func shadow(dark: Bool) -> Color {
        switch self {
        case .hardware: dark ? .clear : Color.black.opacity(0.10)
        case .island: Color.black.opacity(dark ? 0.45 : 0.16)
        }
    }
}

/// The notch at rest: Claude Code's status glyph, then each plan's small ring, state shape and week %,
/// and what the width has room for.
private struct NotchRestContent: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    let k: CGFloat
    let restWidth: Double

    var body: some View {
        let tier = NotchSizing.rest(width: restWidth, orgs: model.orgs.count, advice: model.advice != nil)
        let word = GlanceCopy.notchWord(signedIn: model.signedIn || model.limitsOff, problem: model.limitsOff ? nil : problemWhenUnread,
                                        loading: !model.limitsOff && model.widgetMessage != nil, message: model.widgetMessage)
        let urgent = NotchSizing.urgentIndex(model.orgs.map { model.state(for: $0) })
        HStack(spacing: 10 * k) {
            if let advice = model.advice {
                Text("⇄").font(Theme.font(13 * k, .bold)).foregroundStyle(model.adviceTone.ink)
                    .fixedSize()
                    .accessibilityLabel("Move Claude Code to \(advice.target.name): \(advice.reason).")
            }
            // Like the widget and the open notch: no status when nothing reports one (L15).
            if let mood = model.codeMood {
                StatusGlyph(mood, size: 15 * k)
                    .accessibilityLabel("Claude Code: \(mood.word)")
            }
            if let word, model.widgetMessage != nil, !model.limitsOff {
                HStack(spacing: 5 * k) {
                    StateShape(nil, size: 10 * k)
                    Text(word).font(Theme.font(12 * k, .semibold)).foregroundStyle(Palette.notchBright)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .help(model.widgetMessage?.sentence ?? word)
            } else if !model.limitsOff {
                ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                    orgView(org, tier: tier, showsUrgent: index == urgent)
                }
            }
        }
        .padding(.horizontal, 14 * k)
    }

    /// The refresh problem while nothing has been read.
    private var problemWhenUnread: RefreshProblem? {
        model.orgs.allSatisfy { model.glance(for: $0) == nil } ? model.refreshProblem : nil
    }

    private func orgView(_ org: Org, tier: NotchRest, showsUrgent: Bool) -> some View {
        let glance = model.glance(for: org)
        let state = model.state(for: org), old = model.isOld(org)
        return HStack(spacing: 4 * k) {
            if let pie = model.weekPie(for: org) {
                ForecastPie(pie: pie, size: 18 * k, isOld: old)
            } else {
                WeekRing(used: glance.map { $0.week.used ?? 0 }, elapsed: (glance?.week.elapsed ?? 0) * 100, state: state,
                         size: 18 * k, showsNumber: false, dimmed: old, firstReadDay: model.firstReadDay(for: org))
            }
            StateShape(state, hollow: old, size: 8 * k).fixedSize()
            if let glance {
                if tier >= .percents {
                    Text(glance.week.percentText).font(Theme.font(11 * k, .semibold))
                        .foregroundStyle(old ? Palette.notchDim : Palette.notchBright).fixedSize()
                }
                if tier >= .bars {
                    hairline(glance.session).frame(width: CGFloat(NotchSizing.hairlineWidth) * k)
                }
                if tier == .numbers {
                    // The 5-hour % of every plan; the urgent plan shows the limit that made it urgent, in its
                    // state's ink (M7).
                    let limit = showsUrgent ? glance.mostUrgent : glance.session
                    Text(limit.percentText).font(Theme.font(11 * k, showsUrgent ? .bold : .regular))
                        .foregroundStyle(showsUrgent ? (state == .fine || state == nil ? Palette.notchBright : UsageText.ink(state)) : Palette.notchDim)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.summary(for: org))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.openWindow(.usage, org.id) }
    }

    /// One bar width for every plan, continuous (no cells) when it would be narrower than 30 pt.
    private func hairline(_ limit: GlanceLimit) -> some View {
        let height = 4 * k
        return GeometryReader { proxy in
            if proxy.size.width < CGFloat(NotchSizing.continuousBelow) * k {
                GlanceCell(shape: RoundedRectangle(cornerRadius: height / 2), track: Palette.notchTrack, color: limit.tone.color,
                           fill: CGFloat((limit.used ?? 0) / 100), hatched: false, k: k)
            } else {
                HStack(spacing: 1.5 * k) {
                    ForEach(0..<limit.cells, id: \.self) { i in
                        GlanceCell(shape: RoundedRectangle(cornerRadius: height / 2), track: Palette.notchTrack,
                                   color: limit.tone.color, fill: CGFloat(limit.cellFill(i)), hatched: false, k: k)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// The notch open: the widget's glance row at the open size.
private struct NotchOpenContent: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    let k: CGFloat
    let restWidth: Double

    var body: some View {
        let orgs = model.orgs.count, advice = model.advice != nil
        let width = NotchSizing.openWidth(orgs: orgs, size: model.settings.notchOpensTo, advice: advice,
                                          restWidth: restWidth, status: model.leftStatusMood)
        GlanceRow(model: model, actions: actions,
                  layout: WidgetSizing.layout(width: width, orgs: orgs, advice: advice, week: false, status: model.leftStatusMood), k: k,
                  anchor: .notch)
    }
}

/// The notch: a look's shape over the window, the rest or open content on its glass, and the
/// optional rim and advice glow.
struct NotchView: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    @ObservedObject var state: NotchState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle

    private var look: NotchLook { state.look }
    private var place: NotchPlace { state.place }
    private var dark: Bool { scheme == .dark }
    private var k: CGFloat { state.k }

    /// The glass in a window of `size` (y down), pinned to its corner.
    private func glassRect(in size: CGSize) -> CGRect {
        let g = state.glassSize
        let y = place == .topRight ? state.edgeInset : size.height - state.edgeInset - g.height
        return CGRect(x: size.width - state.trailingInset - g.width, y: y, width: g.width, height: g.height)
    }

    var body: some View {
        GeometryReader { geo in card(glassRect(in: geo.size)) }
    }

    private func card(_ glass: CGRect) -> some View {
        let shape = self.shape(glass)
        return ZStack {
            shape.fill(look.background(dark: dark))
                .modifier(LookShadow(look: look, color: look.shadow(dark: dark), k: k))
            // A 2 pt stroke clipped to the shape leaves its inner 1 pt, as a strokeBorder would.
            if look == .island { shape.stroke(look.border(dark: dark), lineWidth: 2).clipShape(shape) }
            glow(shape)
            content
                .animation(.easeInOut(duration: 0.15), value: state.open)
                                .frame(width: glass.width, height: glass.height)
                .clipShape(shape.offsetBy(dx: -glass.minX, dy: -glass.minY))
                .position(x: glass.midX, y: glass.midY)
            rim(glass)
        }
        .environment(\.glanceTrack, look.track(dark: dark))
        .environment(\.showsInUse, false)
        .environment(\.colorScheme, .dark)
        .contentShape(shape)
        .onTapGesture { actions.openWindow(.usage, nil) }
        .accessibilityAction(.default) { actions.openWindow(.usage, nil) }
        .simultaneousGesture(MagnificationGesture()
            .onChanged { actions.pinch($0, false) }
            .onEnded { actions.pinch($0, true) })
        .contextMenu { WidgetMenu(model: model, actions: actions) }
    }

    /// The look's shape over the glass.
    private func shape(_ glass: CGRect) -> AnyShape {
        switch look {
        case .hardware:
            return AnyShape(HardwareNotchShape(place: place, glass: glass, radius: 16 * k,
                                        flare: CGFloat(NotchPlacement.flare) * k))
        case .island:
            let island: AnyShape = state.open
                ? AnyShape(RoundedRectangle(cornerRadius: 22 * k, style: .continuous))
                : AnyShape(Capsule())
            return AnyShape(IslandShape(glass: glass, inner: island))
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.open {
            NotchOpenContent(model: model, actions: actions, k: k, restWidth: state.restWidth)
                .transition(.opacity)
        } else {
            NotchRestContent(model: model, actions: actions, k: k, restWidth: state.restWidth)
                .transition(.opacity)
        }
    }

    /// The most urgent tone across the orgs' glances; nil without a reading.
    private var urgentTone: GlanceTone? {
        let tones = model.orgs.compactMap { model.glance(for: $0) }.flatMap { [$0.session.tone, $0.week.tone] }
        guard let top = tones.max(), top != .none else { return nil }
        return top
    }

    @ViewBuilder
    private func rim(_ glass: CGRect) -> some View {
        if model.settings.notchRim, let tone = urgentTone {
            Capsule().fill(tone.color)
                .frame(width: max(glass.width - 36 * k, 0), height: 2 * k)
                .position(x: glass.midX, y: place == .topRight ? glass.maxY - k : glass.minY + k)
        }
    }

    /// Advice at rest: the shape's edge in amber, or red when Claude Code's own 5-hour is full.
    /// Core Animation breathes it (full to 55% over 1.2 s each way) in the window server; still
    /// with Reduce Motion, and drawn in SwiftUI in image renders, which can't show Core Animation.
    @ViewBuilder
    private func glow(_ shape: AnyShape) -> some View {
        if model.advice != nil, !state.open {
            let tone = glowTone
            if renderStyle != .live {
                shape.stroke(tone.opacity(0.7), lineWidth: 1.5)
                    .shadow(color: tone.opacity(0.35), radius: 9)
            } else {
                GlowLayer(path: shape.path(in: .zero).cgPath, color: NSColor(tone), animates: !reduceMotion)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var glowTone: Color {
        model.adviceTone.color
    }
}

/// The island's capsule or card, placed over the glass inside the window.
private struct IslandShape: Shape {
    var glass: CGRect
    var inner: AnyShape

    func path(in rect: CGRect) -> Path { inner.path(in: glass) }
}

private extension Shape {
    /// The shape drawn in a rect at the origin, shifted: clips content placed at a glass rect's origin.
    func offsetBy(dx: CGFloat, dy: CGFloat) -> some Shape { OffsetShape(base: self, dx: dx, dy: dy) }
}

private struct OffsetShape<S: Shape>: Shape {
    var base: S
    var dx: CGFloat
    var dy: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect.offsetBy(dx: -dx, dy: -dy)).offsetBy(dx: dx, dy: dy)
    }
}

/// The look's drop shadow: the hardware notch's only in light, the island's always.
private struct LookShadow: ViewModifier {
    let look: NotchLook
    let color: Color
    let k: CGFloat

    func body(content: Content) -> some View {
        switch look {
        case .hardware: content.shadow(color: color, radius: 4 * k, y: 3 * k)
        case .island: content.shadow(color: color, radius: 12 * k, x: 0, y: 8 * k)
        }
    }
}

/// The advice glow as a stroked, shadowed layer whose opacity breathes in the window server.
private struct GlowLayer: NSViewRepresentable {
    var path: CGPath
    var color: NSColor
    var animates: Bool

    func makeNSView(context: Context) -> GlowLayerView { GlowLayerView() }

    func updateNSView(_ view: GlowLayerView, context: Context) {
        view.color = color
        view.path = path
        view.animates = animates
    }
}

private final class GlowLayerView: NSView {
    private let stroke = CAShapeLayer()
    /// The shape in SwiftUI's y-down coordinates; flipped to the layer's when laid out.
    var path: CGPath? { didSet { if path != oldValue { needsLayout = true } } }
    var color = NSColor.systemOrange { didSet { if color != oldValue { applyColor() } } }
    var animates = true { didSet { if animates != oldValue { restart() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.lineWidth = 1.5
        stroke.shadowRadius = 9
        stroke.shadowOffset = .zero
        stroke.shadowOpacity = 1
        layer?.addSublayer(stroke)
        applyColor()
        restart()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        stroke.path = path?.copy(using: &flip)
        CATransaction.commit()
    }

    private func applyColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.strokeColor = color.withAlphaComponent(0.7).cgColor
        stroke.shadowColor = color.withAlphaComponent(0.35).cgColor
        CATransaction.commit()
    }

    private func restart() {
        stroke.removeAllAnimations()
        guard animates else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1
        breathe.toValue = 0.55
        breathe.duration = 1.2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.isRemovedOnCompletion = false
        stroke.add(breathe, forKey: "breathe")
    }
}
