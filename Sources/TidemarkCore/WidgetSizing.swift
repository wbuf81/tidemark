import CoreGraphics
import Foundation

/// The five horizontal layouts, from two gauges per org to the week's heat strip.
public enum WidgetSize: Int, Comparable, CaseIterable, Sendable {
    case xs, s, m, l, xl

    public static func < (a: WidgetSize, b: WidgetSize) -> Bool { a.rawValue < b.rawValue }
}

/// The side strip's two layouts.
public enum StripSize: Sendable { case narrow, wide }

/// The switch band beside the orgs: none, "⇄" alone, or "⇄ harbor first".
public enum SwitchBand: Sendable { case none, narrow, wide }

/// How wide the widget is and what it shows at that width. Widths are points at text size 1:
/// on screen they're multiplied by the text scale.
public enum WidgetSizing {
    static let narrowBand = 22.0
    static let wideBand = 70.0
    /// Each org's slot: the smallest and largest.
    static let slotMin = 52.0
    static let slotMax = 280.0
    /// Where each size starts, by slot.
    static let slotS = 70.0, slotM = 150.0, slotL = 165.0, slotXL = 225.0
    public static let stripMin = 56.0
    public static let stripMax = 150.0
    static let stripWideFrom = 92.0
    /// The week band at the end of the bar, when a week calendar is set up.
    public static let weekBand = 96.0

    public struct Layout: Equatable, Sendable {
        public var size: WidgetSize
        public var band: SwitchBand
        /// Each org's width.
        public var slot: Double
        /// The whole widget's width, clamped.
        public var width: Double
        public var bandWidth: Double
        /// The week band's width; 0 when it isn't shown.
        public var weekWidth: Double = 0
        /// The Claude Code status slot's width at the start; 0 when it isn't shown.
        public var statusWidth: Double = 0
    }

    /// The status slot (glyph, its word, "Claude Code") by the size the plans get: 66 pt at L and up,
    /// 56 at S and M, and at XS the glyph alone (30), or nothing while Claude Code is idle. No mood
    /// (neither hooks nor transcript activity report one) shows no slot at all.
    public static func statusWidth(for size: WidgetSize, mood: CodeMood?) -> Double {
        guard let mood else { return 0 }
        switch size {
        case .xl, .l: return 66
        case .m, .s: return 56
        case .xs: return mood == .idle ? 0 : 30
        }
    }

    /// The mood for the status slot at the start, or nil when no slot is wanted: Claude Code's status
    /// sits on the plan it's signed in to (a chip in the name row, a badge at narrow widths) whenever plan
    /// cards show and that plan is one of them. Without plan cards (limits off, a message in their place)
    /// or while its plan isn't shown, the slot stays, as before.
    public static func leftStatus(_ mood: CodeMood?, plansShown: Bool, onShownPlan: Bool) -> CodeMood? {
        plansShown && onShownPlan ? nil : mood
    }

    /// The layout with Claude Code's status slot at the start: the slot comes out of the plans'
    /// room, so it can lower their size (and the slot with it); the week band still needs L.
    public static func layout(width: Double, orgs: Int, advice: Bool, week: Bool, status mood: CodeMood?) -> Layout {
        let base = layout(width: width, orgs: orgs, advice: advice)
        let n = Double(max(orgs, 1))
        func place(week showsWeek: Bool, status: Double) -> Layout {
            var layout = base
            layout.weekWidth = showsWeek ? weekBand : 0
            layout.statusWidth = status
            layout.slot = (base.width - base.bandWidth - layout.weekWidth - status) / n
            layout.size = size(forSlot: layout.slot)
            return layout
        }
        let full = statusWidth(for: .l, mood: mood)
        if week {
            let withWeek = place(week: true, status: full)
            if withWeek.size >= .l { return withWeek }
        }
        var layout = place(week: false, status: statusWidth(for: base.size, mood: mood))
        let narrower = statusWidth(for: layout.size, mood: mood)
        if narrower != layout.statusWidth { layout = place(week: false, status: narrower) }
        return layout
    }

    public static func size(forSlot slot: Double) -> WidgetSize {
        slot >= slotXL ? .xl : slot >= slotL ? .l : slot >= slotM ? .m : slot >= slotS ? .s : .xs
    }

    /// From one minimum slot per org (plus the narrow band while there's advice) to one
    /// maximum slot per org. No orgs counts as one.
    public static func widthRange(orgs: Int, advice: Bool) -> ClosedRange<Double> {
        let n = Double(max(orgs, 1))
        return (n * slotMin + (advice ? narrowBand : 0))...(n * slotMax)
    }

    public static func clampWidth(_ width: Double, orgs: Int, advice: Bool) -> Double {
        let range = widthRange(orgs: orgs, advice: advice)
        return min(max(width, range.lowerBound), range.upperBound)
    }

    /// The layout at `width`: with advice, the wide band when the slot it leaves still
    /// reaches L, otherwise the narrow one. With a week to show, the week band takes its width
    /// from the orgs when what's left of each slot still reaches L; narrower widgets leave it out.
    public static func layout(width: Double, orgs: Int, advice: Bool, week: Bool) -> Layout {
        var layout = layout(width: width, orgs: orgs, advice: advice)
        guard week else { return layout }
        let slot = (layout.width - layout.bandWidth - weekBand) / Double(max(orgs, 1))
        guard size(forSlot: slot) >= .l else { return layout }
        layout.slot = slot
        layout.size = size(forSlot: slot)
        layout.weekWidth = weekBand
        return layout
    }

    public static func layout(width: Double, orgs: Int, advice: Bool) -> Layout {
        let n = Double(max(orgs, 1))
        let w = clampWidth(width, orgs: orgs, advice: advice)
        guard advice else { return Layout(size: size(forSlot: w / n), band: .none, slot: w / n, width: w, bandWidth: 0) }
        let wideSlot = (w - wideBand) / n
        if size(forSlot: wideSlot) >= .l {
            return Layout(size: size(forSlot: wideSlot), band: .wide, slot: wideSlot, width: w, bandWidth: wideBand)
        }
        let slot = (w - narrowBand) / n
        return Layout(size: size(forSlot: slot), band: .narrow, slot: slot, width: w, bandWidth: narrowBand)
    }

    public static func clampStrip(_ width: Double) -> Double { min(max(width, stripMin), stripMax) }

    public static func stripSize(width: Double) -> StripSize { width >= stripWideFrom ? .wide : .narrow }

    /// The width to draw at, on screen: the owner's, narrowed to the gap beside a bottom Dock
    /// when the widget sits in a bottom corner (or was never moved), the setting is on, and the
    /// gap holds at least `minimum`. Otherwise `wanted`, and the placement puts a widget too
    /// wide for the gap above the Dock.
    public static func fittedWidth(wanted: Double, minimum: Double, spot: WidgetSpot?, fitBesideDock: Bool,
                                   screen: CGRect, visible: CGRect, dockWidth: Double?) -> Double {
        guard fitBesideDock, let dockWidth, visible.minY > screen.minY + 1 else { return wanted }
        let room: Double
        switch spot {
        case nil, .snapped(.bottomRight)?:
            room = ((visible.maxX - 12) - (screen.midX + dockWidth / 2 + 8)).rounded(.down)
        case .snapped(.bottomLeft)?:
            room = ((screen.midX - dockWidth / 2 - 8) - (visible.minX + 12)).rounded(.down)
        default:
            return wanted
        }
        return room >= minimum ? min(wanted, room) : wanted
    }

    /// The width to save when a drag on the inner edge is released, nil to save nothing: a click
    /// or a drag that went nowhere changes nothing, and widening a widget that was narrowed
    /// beside the Dock keeps the owner's wider `saved` width (unless the drag went past it).
    /// Dragging narrower always sticks.
    public static func widthToSave(start: Double, end: Double, saved: Double, narrowed: Bool) -> Double? {
        guard abs(end - start) >= 0.5 else { return nil }
        return narrowed && end > start ? max(saved, end) : end
    }

    /// The widths that replace the compact and full widgets: compact (the default) was about
    /// 280 pt across and a 68 pt strip; full about 520 and 104.
    public static func migratedWidths(compact: Bool?) -> (width: Double, strip: Double) {
        compact == false ? (520, 104) : (280, 68)
    }
}

/// The tide slot's forms and what each has room for, in points at text size 1.
public enum TideSlotLayout {
    /// XS: the % over the water and the shape with the plan's first letter. Narrow: name row, the % and
    /// the short verdict, the 5-hour line. Full: the same with the whole verdict, a chip in the name row
    /// and the reset time.
    public enum Form: Sendable { case xs, narrow, full }

    /// A slot this wide has room for the chip beside the name and the 5-hour line's reset time; narrower
    /// ones show the chip as a badge and drop the time.
    static let roomy = 190.0

    public static func form(for size: WidgetSize) -> Form {
        switch size {
        case .xs: .xs
        case .s: .narrow
        case .m, .l, .xl: .full
        }
    }

    public static func chipInline(slot: Double) -> Bool { slot >= roomy }
    public static func showsReset(slot: Double) -> Bool { slot >= roomy }

    /// What a slot's height allows, in points at text size 1.
    public struct Fit: Equatable, Sendable {
        /// Padding above and below the content.
        public var padding: Double
        /// The 5-hour row at the bottom (dropped when the room is too short for it).
        public var fiveHour: Bool

        /// The height the slot's content takes with this fit.
        public func height(for form: Form) -> Double {
            TideSlotLayout.content(form, fiveHour: fiveHour) + 2 * padding
        }
    }

    /// The content's height without padding: the name row (12), the used % (30 full, 24 otherwise), the
    /// verdict line under it when narrow (13), the 5-hour row (13) and the gaps between them (2 each).
    static func content(_ form: Form, fiveHour: Bool) -> Double {
        switch form {
        case .xs: 12 + 2 + 24
        case .narrow: 12 + 2 + 24 + 2 + 13 + (fiveHour ? 2 + 13 : 0)
        case .full: 12 + 2 + 30 + (fiveHour ? 2 + 13 : 0)
        }
    }

    /// How a slot fits `room` points of height (the widget's height divided by its text scale). The Dock's
    /// icon size sets it: about 82 for 48 pt icons, 73.5 for 64, 70.7 for 72, and 66.7 for an auto-hiding
    /// Dock. Padding gives way first (down to 3.5), then the 5-hour row goes.
    public static func fit(_ form: Form, room: Double) -> Fit {
        let desired = form == .full ? 9.0 : 8.0
        let least = 3.5
        let with = content(form, fiveHour: true)
        if room >= with + 2 * desired { return Fit(padding: desired, fiveHour: true) }
        if form == .xs { return Fit(padding: max((room - with) / 2, least), fiveHour: false) }
        if room >= with + 2 * least { return Fit(padding: (room - with) / 2, fiveHour: true) }
        let without = content(form, fiveHour: false)
        return Fit(padding: min(desired, max((room - without) / 2, least)), fiveHour: false)
    }

    /// The side strip stacks narrow slots; a strip thinner than the S size falls back to the XS form.
    public static func stripForm(width: Double) -> Form { width >= WidgetSizing.slotS ? .narrow : .xs }
}

/// The measures inside a plan's card, in points at text size 1.
public enum GlanceLayout {
    /// Padding on each side of a card.
    public static let padding = 8.0
    /// Between the ring and the text, and the room the state shape and its gap take before a name.
    public static let ringGap = 8.0
    static let shapeRoom = 12.0

    /// The week ring's size at each widget size: 24 pt at XS (number only) up to 46 (32 at S and M).
    public static func ringSize(_ size: WidgetSize) -> Double {
        switch size {
        case .xs: 24
        case .s: 32
        case .m: 32
        case .l: 40
        case .xl: 46
        }
    }

    /// How wide a plan's name may be in a slot: what the padding, the ring and the shape leave (at XS
    /// and S the ring sits above the name, so only the padding and the shape come off). A longer name
    /// truncates in this width; VoiceOver keeps the whole name.
    public static func nameWidth(size: WidgetSize, slot: Double) -> Double {
        let ring = size <= .s ? 0 : ringSize(size) + ringGap
        return max(slot - 2 * padding - ring - shapeRoom, 0)
    }

    /// The week note's type size: 10 pt at M, where the room is least, 11 pt above.
    public static func noteFontSize(_ size: WidgetSize) -> Double { size == .m ? 10 : 11 }

    /// How wide the week note may be in a wide card (M, L, XL): the slot less the padding, the ring and
    /// the gap after it.
    public static func noteWidth(size: WidgetSize, slot: Double) -> Double {
        max(slot - 2 * padding - ringSize(size) - ringGap, 0)
    }
}
