import AppKit
import SwiftUI
import TidemarkCore

/// What an in-use effect decorates.
enum EffectTarget: Equatable {
    /// The 5-hour line: how much is filled (0...1).
    case line(fill: Double)
}

/// Particles on an org that's in use, over its 5-hour line, in the owner's style
/// and amount. Core Animation runs them in the window server, so the app does no work per
/// frame. With Reduce Motion, and in image renders (which can't draw Core Animation), a
/// still glow at the end of the fill instead.
struct InUseEffect: View {
    var target: EffectTarget
    var style: EffectStyle
    var amount: EffectAmount
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle
    @Environment(\.colorScheme) private var scheme
    @Environment(\.showsInUse) private var showsInUse

    var body: some View {
        if style != .off, showsInUse {
            if reduceMotion || renderStyle != .live {
                TipGlow(target: target, color: color)
            } else {
                EffectLayers(config: EffectConfig(target: target, style: style, amount: amount,
                                                  color: NSColor(color), dark: scheme == .dark))
            }
        }
    }
}

private struct ShowsInUseKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether in-use effects draw; the notch turns them off.
    var showsInUse: Bool {
        get { self[ShowsInUseKey.self] }
        set { self[ShowsInUseKey.self] = newValue }
    }
}

extension View {
    /// The in-use effect over this line, when `on`; `under` draws it behind the line instead, so the
    /// glow never hides the end of the fill (S1.9).
    @ViewBuilder
    func inUseEffect(_ on: Bool, _ target: EffectTarget, settings: Settings, color: Color, under: Bool = false) -> some View {
        let effect = InUseEffect(target: target, style: settings.effectStyle, amount: settings.effectAmount, color: color)
        if under {
            background { if on { effect } }
        } else {
            overlay { if on { effect } }
        }
    }
}

/// Where the effects go in a view of a given size.
private enum EffectGeometry {
    /// The end of the fill; `flipped` for SwiftUI's y-down coordinates.
    static func tip(_ target: EffectTarget, in size: CGSize) -> CGPoint {
        switch target {
        case .line(let fill):
            return CGPoint(x: max(size.width * CGFloat(fill), 2), y: size.height / 2)
        }
    }

    /// The filled arc or stretch of line, for effects that travel along it (y-up); nil when
    /// there's too little fill to travel along.
    static func fillPath(_ target: EffectTarget, in size: CGSize) -> CGPath? {
        let path = CGMutablePath()
        switch target {
        case .line(let fill):
            guard size.width * CGFloat(fill) >= size.height else { return nil }
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * CGFloat(fill), y: size.height / 2))
        }
        return path
    }
}

/// A soft, still glow where the fill ends.
private struct TipGlow: View {
    var target: EffectTarget
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let radius = max(geo.size.height * 1.2, 5)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.75), color.opacity(0.45), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .position(EffectGeometry.tip(target, in: geo.size))
        }
        .allowsHitTesting(false)
    }
}

private struct EffectConfig: Equatable {
    var target: EffectTarget
    var style: EffectStyle
    var amount: EffectAmount
    var color: NSColor
    var dark: Bool
}

private struct EffectLayers: NSViewRepresentable {
    var config: EffectConfig

    func makeNSView(context: Context) -> EffectView { EffectView() }
    func updateNSView(_ view: EffectView, context: Context) { view.config = config }
}

/// Holds the effect's layers, rebuilt only when what they show or the view's size changes.
private final class EffectView: NSView {
    var config: EffectConfig? { didSet { if config != oldValue { rebuild() } } }
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Clicks, drags and hovers go to the widget underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        builtSize = bounds.size
        guard let config, let layer, bounds.width > 0, bounds.height > 0 else { return }
        for effect in EffectLayersBuilder.layers(config, size: bounds.size) {
            effect.frame = CGRect(origin: .zero, size: bounds.size)
            layer.addSublayer(effect)
        }
    }
}

/// The Core Animation layers for each style. Every layer is full-size; rates and counts
/// scale with the amount. Coordinates are y-up.
private enum EffectLayersBuilder {
    static func layers(_ c: EffectConfig, size: CGSize) -> [CALayer] {
        let m = c.amount.multiplier
        let tip = EffectGeometry.tip(c.target, in: size)
        let path = EffectGeometry.fillPath(c.target, in: size)
        switch (c.style, c.target) {
        case (.off, _):
            return []
        case (.sparks, .line):
            let big: CGFloat = size.height >= 6 ? 1.25 : 1.1
            let warm = NSColor(srgbRed: 1, green: 0.84, blue: 0.55, alpha: 1)
            return [sparks(at: tip, direction: .pi / 2 - 0.4, spread: .pi / 3, rate: 70 * m * Double(big), speed: 50 * big,
                           gravity: 190, life: 0.5, scale: 0.2 * big, colors: c.dark ? [warm, c.color] : [c.color], dark: c.dark),
                    glow(at: tip, radius: 6 * big, color: warm)]
        case (.flow, .line):
            guard let path else { return [] }
            let count = max(3, Int((6 * m).rounded()))
            return [travellers(along: path, count: count, spacing: 1.7 / Double(count), period: 1.7, timing: .linear,
                               size: max(3.5, size.height * 0.9), color: .white, opacity: [0, 1, 0], fade: 0),
                    glow(at: tip, radius: max(6, size.height * 1.5), color: c.color)]
        case (.shimmer, .line(let fill)):
            let width = size.width * CGFloat(fill)
            guard width >= size.height else { return [] }
            return [sweep(width: width, height: size.height)]
        }
    }

    /// A small round particle, white so emitter cells can tint it.
    static let particle: CGImage = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                                   endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
        return context.makeImage()!
    }()

    /// Sparks from one point, mostly at `direction` (radians, y-up), falling with `gravity`.
    static func sparks(at point: CGPoint, direction: CGFloat, spread: CGFloat, rate: Double, speed: CGFloat,
                       gravity: CGFloat, life: Float, scale: CGFloat, colors: [NSColor], dark: Bool) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = dark ? .additive : .oldestLast
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = particle
            cell.birthRate = Float(rate) / Float(colors.count)
            cell.lifetime = life
            cell.lifetimeRange = life * 0.3
            cell.velocity = speed
            cell.velocityRange = speed * 0.5
            cell.emissionLongitude = direction
            cell.emissionRange = spread
            cell.yAcceleration = -gravity
            cell.scale = scale
            cell.scaleRange = scale * 0.4
            cell.scaleSpeed = -scale / CGFloat(life)
            cell.alphaSpeed = -1 / life
            cell.color = color.cgColor
            return cell
        }
        return emitter
    }

    /// `count` dots travelling along `path` one after another every `period` seconds,
    /// `spacing` seconds apart, fading through `opacity`. `fade` dims each one after the
    /// first, for a trail.
    static func travellers(along path: CGPath, count: Int, spacing: CFTimeInterval, period: CFTimeInterval,
                           timing: CAMediaTimingFunctionName, size: CGFloat, color: NSColor,
                           opacity: [Float], fade: Float) -> CALayer {
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        dot.cornerRadius = size / 2
        dot.backgroundColor = color.cgColor
        dot.opacity = 0
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .paced
        let fadeInOut = CAKeyframeAnimation(keyPath: "opacity")
        fadeInOut.values = opacity
        let travel = CAAnimationGroup()
        travel.animations = [move, fadeInOut]
        travel.duration = period
        travel.timingFunction = CAMediaTimingFunction(name: timing)
        travel.repeatCount = .infinity
        travel.fillMode = .backwards
        travel.isRemovedOnCompletion = false
        dot.add(travel, forKey: "travel")
        let replicator = CAReplicatorLayer()
        replicator.instanceCount = count
        replicator.instanceDelay = spacing
        replicator.instanceAlphaOffset = fade
        replicator.addSublayer(dot)
        return replicator
    }

    /// A soft round glow.
    static func glow(at point: CGPoint, radius: CGFloat, color: NSColor) -> CALayer {
        let holder = CALayer()
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [NSColor.white.withAlphaComponent(0.8).cgColor, color.withAlphaComponent(0.4).cgColor,
                       color.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        holder.addSublayer(glow)
        return holder
    }

    /// A band of light sweeping along the filled part of the line.
    static func sweep(width: CGFloat, height: CGFloat) -> CALayer {
        let holder = CALayer()
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: width, height: height)
        fill.cornerRadius = height / 2
        fill.masksToBounds = true
        let band = CAGradientLayer()
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.95).cgColor,
                       NSColor.white.withAlphaComponent(0).cgColor]
        band.frame = CGRect(x: -24, y: 0, width: 24, height: height)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -12
        move.toValue = width + 12
        move.duration = 1.6
        move.repeatCount = .infinity
        band.add(move, forKey: "sweep")
        fill.addSublayer(band)
        holder.addSublayer(fill)
        return holder
    }
}
