import AppKit
import SwiftUI
import TidemarkCore

/// The menu bar's pictures: Tidemark's one-colour icon (a ring with a water line, the mockups'
/// `TIDEMARK_MB`), the small state marks beside each plan in its menu, and a plan's battery.
@MainActor
enum MenuBarIcon {
    /// The icon as a template image, so the menu bar colours it. Drawn in the mockups' 16-unit box.
    static func image(size: CGFloat = 18) -> NSImage {
        let renderer = ImageRenderer(content: IconShape().frame(width: size, height: size))
        renderer.scale = 4
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }

    /// A plan's state mark for a menu line: drawn when the menu draws, so it follows the menu's
    /// light or dark look.
    static func stateImage(_ state: PlanState?, hollow: Bool = false, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let k = rect.width / 10
            var path = Path()
            var stroke = false
            if let state {
                if hollow { StateShape.hollowPath(state, &path); stroke = true } else { StateShape.filledPath(state, &path) }
            } else {
                path.addEllipse(in: CGRect(x: 1.3, y: 1.3, width: 7.4, height: 7.4))
                path.move(to: CGPoint(x: 3, y: 5)); path.addLine(to: CGPoint(x: 7, y: 5))
                stroke = true
            }
            let scaled = path.applying(CGAffineTransform(scaleX: k, y: k)).cgPath
            let colour = NSColor(Palette.color(for: state)).cgColor
            context.addPath(scaled)
            if stroke {
                context.setStrokeColor(colour)
                context.setLineWidth(1.5 * k)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            } else {
                context.setFillColor(colour)
                context.fillPath()
            }
            return true
        }
        return image
    }

    /// A glyph for Claude Code's status line in the menu, drawn like the plan marks.
    static func moodImage(_ mood: CodeMood, size: CGFloat = 12) -> NSImage {
        let renderer = ImageRenderer(content: StatusGlyph(mood, size: size).foregroundStyle(.black).frame(width: size, height: size))
        renderer.scale = 4
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }

    // MARK: Batteries

    /// Amber and red as the mockup draws them: fixed fills, and text tones that read on a light or dark menu bar.
    static let amber = NSColor(srgbRed: 0xE5 / 255, green: 0x9A / 255, blue: 0, alpha: 1)
    static let red = NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x3A / 255, alpha: 1)
    private static func tone(light: UInt32, dark: UInt32) -> NSColor {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light) }
    }
    static let amberText = tone(light: 0xC77700, dark: 0xF5B83D)
    static let redText = tone(light: 0xD03A2C, dark: 0xFF8E7E)

    static let batterySize = NSSize(width: 25, height: 12)

    /// A battery drawn like the system's (the mockup's `battery()`): an outline and nub at 45%, and a fill of what's left
    /// of the week in the menu bar's ink (`ink`; the label colour of whatever it's drawn in when nil), amber or red
    /// when the plan runs out early or is out. An old reading dims it.
    static func batteryImage(left: Int, fill: MenuBarBatteries.Fill, dimmed: Bool = false, ink: NSColor? = nil) -> NSImage {
        let w = batterySize.width, h = batterySize.height
        return NSImage(size: batterySize, flipped: true) { _ in
            let ink = ink ?? .labelColor
            let colour: NSColor = fill == .ink ? ink : fill == .amber ? amber : red
            NSGraphicsContext.current?.cgContext.setAlpha(dimmed ? 0.5 : 1)
            let outline = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: w - 3.5, height: h - 1.5), xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.2
            ink.withAlphaComponent(0.45).setStroke()
            outline.stroke()
            ink.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: w - 2.2, y: h / 2 - 2, width: 1.6, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            let inner = max(0, (w - 5) * CGFloat(left) / 100)
            if inner > 0 {
                colour.setFill()
                let r = min(1.8, inner / 2)
                NSBezierPath(roundedRect: NSRect(x: 2.25, y: 2.25, width: inner, height: h - 4.5), xRadius: r, yRadius: r).fill()
            } else if fill == .red {
                let dash = NSBezierPath()
                dash.move(to: NSPoint(x: w / 2 - 4, y: h / 2)); dash.line(to: NSPoint(x: w / 2 + 2, y: h / 2))
                dash.lineWidth = 1.6; dash.lineCapStyle = .round
                red.setStroke()
                dash.stroke()
            }
            return true
        }
    }

    /// A battery item's whole label: the name (semibold), the battery, then the % (amber or red when it should be).
    /// Colours not set here follow the menu bar's own text colour. Used by the real item and by the renders.
    static func batteryTitle(_ item: MenuBarBatteries.Item, ink: NSColor? = nil, font: NSFont = .menuBarFont(ofSize: 0)) -> NSAttributedString {
        let title = NSMutableAttributedString()
        func plain(_ text: String, _ weight: NSFont.Weight? = nil, _ colour: NSColor? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: weight.map { NSFont.systemFont(ofSize: font.pointSize, weight: $0) } ?? font]
            if let colour = colour ?? ink { attributes[.foregroundColor] = colour }
            title.append(NSAttributedString(string: text, attributes: attributes))
        }
        if !item.label.isEmpty { plain(item.label + " ", .semibold) }
        let attachment = NSTextAttachment()
        attachment.image = batteryImage(left: item.left, fill: item.fill, dimmed: item.dimmed, ink: ink)
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - batterySize.height) / 2, width: batterySize.width, height: batterySize.height)
        title.append(NSAttributedString(attachment: attachment))
        let tone: NSColor? = item.fill == .amber ? amberText : item.fill == .red ? redText : nil
        plain(" " + item.percentText, nil, tone)
        return title
    }

    /// How far from the left of a battery title its battery starts: the width of the name before it.
    static func batteryOffset(in title: NSAttributedString) -> CGFloat {
        let at = (title.string as NSString).range(of: "\u{FFFC}").location
        guard at != NSNotFound, at > 0 else { return 0 }
        return title.attributedSubstring(from: NSRange(location: 0, length: at)).size().width
    }

    /// The menu bar's ink in a fixed look (what the renders use; the real bar's own text colour is the same idea).
    static func ink(dark: Bool, inverse: Bool = false) -> NSColor {
        let light = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1), night = NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        return dark != inverse ? night : light
    }

    /// The menu bar's own colour, for the thin ring round the blue dot.
    static func barColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0.10, green: 0.11, blue: 0.25, alpha: 1) : NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1)
    }

    /// The same label drawn to a picture in a fixed look, for the renders (a real item draws it as a button title).
    /// `effect` adds a still of what moves on the real battery: bubbles a moment into their rise, or the dot.
    static func batteryTitleImage(_ item: MenuBarBatteries.Item, dark: Bool, effect: MenuBarBatteries.Effect? = nil) -> NSImage {
        let title = batteryTitle(item, ink: ink(dark: dark))
        let size = title.size()
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? .currentDrawing()
        let pad: CGFloat = effect == nil ? 0 : 5
        let offset = batteryOffset(in: title)
        let font = NSFont.menuBarFont(ofSize: 0)
        return NSImage(size: NSSize(width: ceil(size.width) + (effect == nil ? 0 : 5), height: ceil(size.height) + 2 * pad), flipped: false) { rect in
            let text = NSRect(x: 0, y: pad, width: ceil(size.width), height: ceil(size.height))
            appearance.performAsCurrentDrawingAppearance { title.draw(in: text) }
            guard let effect, let context = NSGraphicsContext.current?.cgContext else { return true }
            // The battery sits on the text's baseline, centred on its cap height.
            let baseline = text.maxY - font.ascender
            let box = CGRect(x: offset, y: baseline + (font.capHeight - batterySize.height) / 2, width: batterySize.width, height: batterySize.height)
            if effect.bubbles {
                let colour = ink(dark: dark, inverse: item.fill == .ink)
                for bubble in BatteryEffects.Bubble.all {
                    let p = bubble.progress(at: 0.8)
                    let d = BatteryEffects.Bubble.size * (0.6 + 0.4 * p)
                    let cx = box.minX + bubble.x + BatteryEffects.Bubble.size / 2 + bubble.dx * p
                    let cy = box.minY + BatteryEffects.Bubble.bottom + BatteryEffects.Bubble.size / 2 + BatteryEffects.Bubble.rise * p
                    context.setFillColor(colour.withAlphaComponent(BatteryEffects.Bubble.opacity(p)).cgColor)
                    context.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
                }
            }
            if effect.dot {
                let centre = BatteryEffects.dotCentre(batteryWidth: batterySize.width)
                let c = CGPoint(x: box.minX + centre.x, y: box.maxY - centre.y)
                let r = BatteryEffects.dotSize / 2
                context.setFillColor(barColor(dark: dark).cgColor)
                context.fillEllipse(in: CGRect(x: c.x - r - BatteryEffects.dotRing, y: c.y - r - BatteryEffects.dotRing, width: 2 * r + 2 * BatteryEffects.dotRing, height: 2 * r + 2 * BatteryEffects.dotRing))
                context.setFillColor(BatteryEffects.dotColor.cgColor)
                context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            return true
        }
    }

    /// The icon's geometry: a faint ring, a bright arc round most of it, and a wavy water line.
    private struct IconShape: View {
        var body: some View {
            ZStack {
                ScaledShape(box: 16) { $0.addEllipse(in: CGRect(x: 2.4, y: 2.4, width: 11.2, height: 11.2)) }
                    .stroke(.black.opacity(0.35), lineWidth: 1.6)
                ScaledShape(box: 16) {
                    $0.addRelativeArc(center: CGPoint(x: 8, y: 8), radius: 5.6, startAngle: .degrees(-90), delta: .degrees(245.7))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                ScaledShape(box: 16) {
                    $0.move(to: CGPoint(x: 5.4, y: 9.4))
                    $0.addCurve(to: CGPoint(x: 8, y: 9.4), control1: CGPoint(x: 6.3, y: 8.8), control2: CGPoint(x: 7, y: 9.9))
                    $0.addCurve(to: CGPoint(x: 10.6, y: 9.4), control1: CGPoint(x: 9, y: 8.9), control2: CGPoint(x: 9.8, y: 8.8))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }
}
