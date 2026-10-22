import SwiftUI

/// The sky's colours (the mockups' `.td` tokens): dawn in light, dusk in dark. Pieces that sit on the
/// sky (the widget, the details card, the Usage page) take their ink from here instead of `Palette`,
/// so they read on the gradient. Choose with `TidePalette.for(colorScheme)`.
///
/// Text tokens (`fg`, `dim`, `faint`, `red`) pass 4.5:1 over the whole sky (sky1 to sky3) and over the water
/// the slots draw (middle and bottom of the water, and the card's sea at its foot), in both looks. The light
/// numbers (the 25 pt used %) only need 3:1. Several differ from the mockups to get there: dawn `dim` is .9
/// and `faint` .85 (was .68 and .5) and dawn `red` is #6B140C (was #C23A2B), the deepest red that still
/// reads as red; dusk `dim` is .85 and `faint` .8 (was .7 and .52) and dusk `red` is #FFAB9F (was #FF8E7E).
/// The measured ratios are in the round 6 fix notes.
struct TidePalette {
    let sky1, sky2, sky3: Color
    let sea1, sea2, sea3: Color
    let moon: Color
    /// Stars: clear by day.
    let star: Color
    let fg, dim, faint: Color
    let line, track: Color
    /// Red text. Deep in light so it reads on the water too; for hatches, dots and bars use `redMark`.
    let red: Color
    /// Red for marks that aren't text (hatching, dots, bars): the mockups' reds.
    let redMark: Color
    let sel: Color
    /// A glass card over the sky.
    let glass: Color

    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }

    static let dawn = TidePalette(
        sky1: hex(0xC9DBF3), sky2: hex(0xE3E1F3), sky3: hex(0xF5E6DD),
        sea1: hex(0xA9C2E8), sea2: hex(0x8FAEE0), sea3: hex(0x7A9BD6),
        moon: hex(0xFFFDF6), star: .clear,
        fg: hex(0x1B1D3A), dim: hex(0x1B1D3A, 0.9), faint: hex(0x1B1D3A, 0.85),
        line: hex(0x1B1D3A, 0.12), track: hex(0x1B1D3A, 0.13), red: hex(0x6B140C), redMark: hex(0xB02E1F),
        sel: hex(0x1B1D3A, 0.08), glass: hex(0xFFFFFF, 0.58))

    static let dusk = TidePalette(
        sky1: hex(0x15173F), sky2: hex(0x24287A), sky3: hex(0x3B40A6),
        sea1: hex(0x3A3F9E), sea2: hex(0x2C3088), sea3: hex(0x222672),
        moon: hex(0xEEF0FF), star: hex(0xFFFFFF, 0.7),
        fg: hex(0xEEF0FF), dim: hex(0xE6E8FF, 0.85), faint: hex(0xE6E8FF, 0.8),
        line: hex(0xFFFFFF, 0.15), track: hex(0xFFFFFF, 0.18), red: hex(0xFFAB9F), redMark: hex(0xFF8E7E),
        sel: hex(0xFFFFFF, 0.12), glass: hex(0xFFFFFF, 0.09))

    static func `for`(_ scheme: ColorScheme) -> TidePalette { scheme == .dark ? .dusk : .dawn }

    /// The fill behind white text on a "Needs you" chip: blue enough for 4.5:1 in both looks.
    static let needsBlue = hex(0x2563EB)
}

/// The same hatch the mockups' patterns draw: 45-degree stripes, `/` on screen, over a tinted base.
enum TideHatch {
    /// Fills `region` (clipped) with `base` and stripes `spacing` apart, `stripe` wide.
    static func fill(_ ctx: inout GraphicsContext, region: Path, spacing: CGFloat, stripe: CGFloat,
                     stripeColor: Color, base: Color) {
        let box = region.boundingRect
        // An empty region (a zero-length arc) has a null box: nothing to fill, and no Int to trap on.
        guard !box.isNull, !box.isInfinite, !box.isEmpty,
              box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite else { return }
        var layer = ctx
        layer.clip(to: region)
        layer.fill(Path(box), with: .color(base))
        // Stripes are the lines x + y = k * spacing * sqrt 2 (the pattern's x axis, turned 45 degrees).
        let step = spacing * 2.0.squareRoot()
        let lo = Int(((box.minX + box.minY) / step).rounded(.down)) - 1
        let hi = Int(((box.maxX + box.maxY) / step).rounded(.up)) + 1
        var lines = Path()
        for k in lo...hi {
            let s = (CGFloat(k) + stripe / spacing / 2) * step
            lines.move(to: CGPoint(x: s - box.minY + 1, y: box.minY - 1))
            lines.addLine(to: CGPoint(x: s - box.maxY - 1, y: box.maxY + 1))
        }
        layer.stroke(lines, with: .color(stripeColor), lineWidth: stripe)
    }
}
