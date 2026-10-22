import CoreGraphics
import Foundation

/// Where the notch sits: under the menu bar at the right edge, or in the bottom-right corner.
public enum NotchPlace: String, Codable, CaseIterable, Sendable { case topRight, bottomRight }

/// How the notch looks: flush to the edges with flared corners, or a pill floating off them.
public enum NotchLook: String, Codable, CaseIterable, Sendable { case hardware, island }

/// How big the notch opens on hover: the widget's M or L glance.
public enum NotchOpenSize: String, Codable, CaseIterable, Sendable { case m, l }

/// What the notch shows at rest, each plan after Claude Code's status glyph: a small ring and its
/// state shape; plus the week's %; plus the 5-hour hairline; plus the urgent plan's % in its ink.
public enum NotchRest: Int, Comparable, Sendable {
    case rings, percents, bars, numbers

    public static func < (a: NotchRest, b: NotchRest) -> Bool { a.rawValue < b.rawValue }
}

/// The notch's sizes, in points at text size 1 (multiplied by the text scale on screen).
public enum NotchSizing {
    public static let restHeight = 38.0
    public static let openHeight = 86.0
    /// The content's side padding at rest, the status glyph's room (15 pt and its gap), and the
    /// switch glyph's room when there's advice.
    static let padding = 28.0, glyph = 25.0, switchGlyph = 22.0
    /// Each plan's slot at rest: the smallest and largest, and where the week %, the hairline and the
    /// urgent % start. A ring (18) and a shape (8) need 34; "58%" 30 more; a hairline 38 more.
    static let slotMin = 34.0, slotMax = 160.0, percentsFrom = 62.0, barsFrom = 98.0, numbersFrom = 136.0
    /// The hairline bars all share this width at rest (so no plan's is shorter), continuous (no
    /// cells) below `continuousBelow`.
    public static let hairlineWidth = 36.0, continuousBelow = 30.0
    /// Each plan's slot when open: the widget's M and L (the 86 pt tall tide slots).
    static let openSlotM = 150.0, openSlotL = 210.0

    /// No plans counts as one.
    public static func restRange(orgs: Int) -> ClosedRange<Double> {
        let n = Double(max(orgs, 1))
        return (padding + glyph + n * slotMin)...(padding + glyph + n * slotMax)
    }

    public static func clampRest(_ width: Double, orgs: Int) -> Double {
        let range = restRange(orgs: orgs)
        return min(max(width, range.lowerBound), range.upperBound)
    }

    /// What a width has room for after the glyph and (with advice) the switch glyph.
    public static func rest(width: Double, orgs: Int, advice: Bool) -> NotchRest {
        let slot = (clampRest(width, orgs: orgs) - padding - glyph - (advice ? switchGlyph : 0)) / Double(max(orgs, 1))
        return slot >= numbersFrom ? .numbers : slot >= barsFrom ? .bars : slot >= percentsFrom ? .percents : .rings
    }

    /// Which plan's % the widest rest shows: the most urgent state (out, then runs out early), the
    /// first of equals; nil when none can be read.
    public static func urgentIndex(_ states: [PlanState?]) -> Int? {
        func rank(_ state: PlanState?) -> Int { switch state { case .out?: 3; case .runsOutEarly?: 2; case .fine?: 1; case nil: 0 } }
        guard let best = states.indices.max(by: { rank(states[$0]) < rank(states[$1]) || (rank(states[$0]) == rank(states[$1]) && $0 > $1) }),
              states[best] != nil else { return nil }
        return best
    }

    /// The open width: one M or L slot per plan, plus the switch band and Claude Code's status slot
    /// that size uses.
    public static func openWidth(orgs: Int, size: NotchOpenSize, advice: Bool, status: CodeMood? = nil) -> Double {
        let n = Double(max(orgs, 1))
        let slot = size == .m ? openSlotM : openSlotL
        let band = advice ? (size == .m ? WidgetSizing.narrowBand : WidgetSizing.wideBand) : 0
        let statusWidth = WidgetSizing.statusWidth(for: size == .m ? .m : .l, mood: status)
        return WidgetSizing.clampWidth(n * slot + band + statusWidth, orgs: orgs, advice: advice)
    }

    /// The open width, but never narrower than the notch is at rest.
    public static func openWidth(orgs: Int, size: NotchOpenSize, advice: Bool, restWidth: Double, status: CodeMood? = nil) -> Double {
        max(openWidth(orgs: orgs, size: size, advice: advice, status: status), restWidth)
    }
}

/// The notch's glass (where it draws) and its window (the glass plus room for the hardware
/// notch's flares or the island's shadow), in screen coordinates.
public struct NotchFrames: Equatable, Sendable {
    public var glass: CGRect
    public var window: CGRect
}

public enum NotchPlacement {
    /// The hardware notch's flared corners where it meets the screen's edges.
    public static let flare = 14.0
    /// The island's gap from the right and bottom edges, and below the menu bar.
    static let islandInset = 8.0
    static let islandBelowMenuBar = 6.0
    /// Room around the island for its shadow (radius 12 at a 8 offset, so about 20 is drawn).
    public static let shadowMargin = 24.0

    /// The notch at `size` (on screen): flush to the visible frame's right edge, under the menu
    /// bar or at the bottom of the screen; the island a few points off those edges. Rest and open
    /// share the anchored corner, so the notch grows leftward and away from its edge. `scale`
    /// is the text scale `size` was multiplied by: it scales the flare and the shadow margin.
    public static func frames(size: CGSize, place: NotchPlace, look: NotchLook,
                              screen: CGRect, visible: CGRect, scale: Double = 1) -> NotchFrames {
        let w = size.width, h = size.height
        let flare = flare * scale, shadowMargin = shadowMargin * scale
        switch (look, place) {
        case (.hardware, .topRight):
            let glass = CGRect(x: visible.maxX - w, y: visible.maxY - h, width: w, height: h)
            return NotchFrames(glass: glass, window: CGRect(x: glass.minX - flare, y: glass.minY - flare,
                                                            width: w + flare, height: h + flare))
        case (.hardware, .bottomRight):
            let glass = CGRect(x: visible.maxX - w, y: screen.minY, width: w, height: h)
            return NotchFrames(glass: glass, window: CGRect(x: glass.minX - flare, y: glass.minY,
                                                            width: w + flare, height: h + flare))
        case (.island, .topRight):
            let glass = CGRect(x: visible.maxX - islandInset - w, y: visible.maxY - islandBelowMenuBar - h, width: w, height: h)
            return NotchFrames(glass: glass, window: glass.insetBy(dx: -shadowMargin, dy: -shadowMargin))
        case (.island, .bottomRight):
            let glass = CGRect(x: visible.maxX - islandInset - w, y: screen.minY + islandInset, width: w, height: h)
            return NotchFrames(glass: glass, window: glass.insetBy(dx: -shadowMargin, dy: -shadowMargin))
        }
    }
}
