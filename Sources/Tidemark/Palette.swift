import AppKit
import SwiftUI
import TidemarkCore

/// Every colour in Tidemark: (light, dark) pairs that follow the appearance. Text is 4.5:1 on
/// its ground and marks 3:1. With Increase Contrast on, `faint` steps up to `dim` and `dim` to `fg`.
enum Palette {
    static let page = dynamic(0xF1F2F4, 0x111111)
    static let tile = dynamic(0xFFFFFF, 0x1A1A1A)
    static let fg = dynamic(0x2A2D31, 0xD4D4D4)
    static let bright = dynamic(0x111316, 0xF5F5F5)
    static let dim = dynamic(0x5F656C, 0xA3A3A3, boosted: (0x2A2D31, 0xD4D4D4))
    static let faint = dynamic(0x646B73, 0x8E8E8E, boosted: (0x5F656C, 0xA3A3A3))
    static let line = dynamic(0xE4E7EA, 0x2A2A2A)
    /// The empty part of a bar, gauge or ring.
    static let track = dynamic(0xD5D9DE, 0x424242)
    static let blue = dynamic(0x2563EB, 0x60A5FA)
    /// Blue for text.
    static let blueInk = dynamic(0x1D4ED8, 0x7DB5FB)
    static let selection = dynamic(0xE6EDFB, 0x22314A)
    static let green = dynamic(0x1A8A4B, 0x57D07A)
    static let amber = dynamic(0xA86E00, 0xF5B83D)
    static let amberInk = dynamic(0x8F5F00, 0xF5B83D)
    static let red = dynamic(0xC93C30, 0xF27166)
    static let redInk = dynamic(0xB83A2E, 0xF27166)

    /// Seven categorical colours for projects and tags; the last is grey, for "other".
    static let c: [Color] = [
        dynamic(0x2F6FEB, 0x5B93F5), dynamic(0xE0662F, 0xEE8150), dynamic(0x1E9E6E, 0x3CC291),
        dynamic(0xC98B00, 0xE0AA2E), dynamic(0xD4578C, 0xE47AA8), dynamic(0x6A6FD8, 0x8E92EC),
        dynamic(0x8A939C, 0x7D858D),
    ]

    /// The notch is always black, so its colours don't follow the appearance.
    static let notchBright = fixed(0xF5F5F5)
    static let notchDim = fixed(0xA3A3A3)
    static let notchTrack = fixed(0x4A4A4A)

    /// Hatching while locked until the reset (the usage batch retunes it).
    static let lockedStripe = dynamic(0xF1B5AE, 0x5A2A27)

    /// The colour of a plan's state mark; nil (couldn't read) is grey.
    static func color(for state: PlanState?) -> Color {
        switch state {
        case .fine: green
        case .runsOutEarly: amber
        case .out: red
        case nil: faint
        }
    }

    // MARK: Old names, for files other batches still own. Each owner removes its uses.


    private static func ns(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func fixed(_ hex: UInt32) -> Color { Color(nsColor: ns(hex)) }

    /// A colour that follows light and dark; `boosted` is what it becomes under Increase Contrast.
    private static func dynamic(_ light: UInt32, _ dark: UInt32, boosted: (UInt32, UInt32)? = nil,
                                alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            var pair = (light, dark)
            if let boosted, NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { pair = boosted }
            return ns(isDark ? pair.1 : pair.0, isDark ? alpha.1 : alpha.0)
        })
    }
}

/// How cards are drawn. Image rendering can't draw live glass or materials, so `--showcase`
/// asks for see-through cards over its own scene.
enum RenderStyle {
    case live, showcase
}

private struct RenderStyleKey: EnvironmentKey {
    static let defaultValue = RenderStyle.live
}

extension EnvironmentValues {
    var renderStyle: RenderStyle {
        get { self[RenderStyleKey.self] }
        set { self[RenderStyleKey.self] = newValue }
    }
}
