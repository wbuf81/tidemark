import SwiftUI

/// The sky behind the widget, the details card and the Usage page (the mockups' `tide_mini` and
/// `tide_scene`): dawn in light, dusk in dark, with a tide along the bottom. Static; fills its frame.
struct TideSky: View {
    enum Kind: Equatable {
        /// A small piece of sky: a few stars at dusk, a corner moon when `moon`, a low tide line.
        case widget(moon: Bool)
        /// Gradient to the sea at the foot, stars, a deeper tide at the foot.
        case card
        /// The Usage page: stars, a big moon with glow and glint, three waves.
        case page
    }

    let kind: Kind
    @Environment(\.colorScheme) private var scheme

    init(_ kind: Kind) { self.kind = kind }

    var body: some View {
        let p = TidePalette.for(scheme)
        ZStack {
            LinearGradient(stops: stops(p), startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                switch kind {
                case .widget(let moon):
                    Self.mini(&ctx, size, p, moon: moon, sea: 10, stars: 7)
                case .card:
                    Self.mini(&ctx, size, p, moon: false, sea: 34, stars: 14)
                case .page:
                    Self.scene(&ctx, size, p)
                }
            }
            // The page's scene is 330 pt tall: its sea fades out at the foot instead of ending in an edge.
            .mask { if kind == .page { Self.sceneFade } else { Color.black } }
        }
        .accessibilityHidden(true)
    }

    private static var sceneFade: some View {
        GeometryReader { geo in
            let bottom = 330 * max(geo.size.width / 1000, 1)
            VStack(spacing: 0) {
                Color.black.frame(height: max(bottom - 110, 0))
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 110)
                Color.clear
            }
        }
    }

    private func stops(_ p: TidePalette) -> [Gradient.Stop] {
        switch kind {
        case .widget: [.init(color: p.sky1, location: 0), .init(color: p.sky2, location: 0.6), .init(color: p.sky3, location: 1)]
        case .card: [.init(color: p.sky1, location: 0), .init(color: p.sky2, location: 0.42),
                     .init(color: p.sky3, location: 0.78), .init(color: p.sea2, location: 1)]
        case .page: [.init(color: p.sky1, location: 0), .init(color: p.sky2, location: 0.34),
                     .init(color: p.sky3, location: 0.52), .init(color: p.sea3, location: 1)]
        }
    }

    // MARK: Drawing

    /// A repeatable wave: quadratic bumps `half` wide that swing up then down, filled to the bottom.
    private static func wave(width: CGFloat, height: CGFloat, y: CGFloat, amp: CGFloat, half: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        var x: CGFloat = 0
        var index = 0
        while x < width + half {
            let swing = index % 2 == 0 ? -amp : amp
            path.addQuadCurve(to: CGPoint(x: x + half, y: y), control: CGPoint(x: x + half / 2, y: y + swing))
            x += half
            index += 1
        }
        path.addLine(to: CGPoint(x: x, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    private static func glow(_ ctx: inout GraphicsContext, at c: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(0)]), center: c, startRadius: 0, endRadius: radius))
    }

    private static func mini(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: TidePalette, moon: Bool, sea: CGFloat, stars: Int) {
        var seed = UInt64(size.width * 31 + size.height) &* 2862933555777941757 &+ 3037000493
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        for _ in 0..<stars {
            let r: CGFloat = [0.6, 0.8, 1][Int(next() * 3) % 3]
            let x = 4 + next() * max(size.width - 8, 1), y = 3 + next() * max(size.height * 0.55 - 3, 1)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(p.star))
        }
        if moon {
            let c = CGPoint(x: size.width - 12, y: 12), r: CGFloat = 5
            glow(&ctx, at: c, radius: r * 3, color: p.moon, opacity: 0.4)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(p.moon))
        }
        let low = wave(width: size.width, height: size.height, y: size.height - sea, amp: 2.2, half: 40)
        ctx.fill(low, with: .color(p.sea1.opacity(0.45)))
        let high = wave(width: size.width, height: size.height, y: size.height - sea * 0.55, amp: 2.6, half: 40)
        ctx.fill(high, with: .color(p.sea2.opacity(0.6)))
    }

    /// The Usage page's scene: a 1000 x 330 box scaled to cover the width (never below 1x), centred.
    private static func scene(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: TidePalette) {
        let k = max(size.width / 1000, 1)
        ctx.translateBy(x: (size.width - 1000 * k) / 2, y: 0)
        ctx.scaleBy(x: k, y: k)
        for (x, y, r) in [(80, 40, 1.0), (210, 22, 0.8), (330, 70, 1.1), (520, 30, 0.9), (610, 88, 0.8),
                          (700, 18, 1.0), (790, 60, 0.9), (860, 30, 1.2), (450, 110, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(p.star))
        }
        let moon = CGPoint(x: 640, y: 118)
        glow(&ctx, at: moon, radius: 90, color: p.moon, opacity: 0.45)
        ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 30, y: moon.y - 30, width: 60, height: 60)), with: .color(p.moon))
        for (y, amp, color, op) in [(205.0, 7.0, p.sea1, 0.55), (228, 9, p.sea2, 0.7), (254, 8, p.sea3, 0.85)] as [(CGFloat, CGFloat, Color, Double)] {
            ctx.fill(wave(width: 1200, height: 330, y: y, amp: amp, half: 120), with: .color(color.opacity(op)))
        }
        for (y, w, op) in [(214.0, 60.0, 0.5), (226, 40, 0.4), (240, 70, 0.3), (262, 30, 0.25)] as [(CGFloat, CGFloat, Double)] {
            ctx.fill(Path(roundedRect: CGRect(x: 640 - w / 2, y: y, width: w, height: 1.6), cornerRadius: 0.8), with: .color(p.moon.opacity(op)))
        }
    }
}
