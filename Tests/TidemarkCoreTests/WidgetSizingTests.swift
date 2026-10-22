import CoreGraphics
import Foundation
import Testing
@testable import TidemarkCore

/// The widget's layout from its width: each org's slot picks one of five sizes.
@Suite struct WidgetSizeTests {
    @Test func slotsPickTheSizes() {
        #expect(WidgetSizing.size(forSlot: 50) == .xs)
        #expect(WidgetSizing.size(forSlot: 69.9) == .xs)
        #expect(WidgetSizing.size(forSlot: 70) == .s)
        #expect(WidgetSizing.size(forSlot: 114.9) == .s)
        // M starts at 150 (was 130): the tide slot's full form (name row, big %, verdict, 5-hour line) needs it.
        #expect(WidgetSizing.size(forSlot: 115) == .s)
        #expect(WidgetSizing.size(forSlot: 130) == .s)
        #expect(WidgetSizing.size(forSlot: 149.9) == .s)
        #expect(WidgetSizing.size(forSlot: 150) == .m)
        #expect(WidgetSizing.size(forSlot: 165) == .l)
        #expect(WidgetSizing.size(forSlot: 224.9) == .l)
        #expect(WidgetSizing.size(forSlot: 225) == .xl)
        #expect(WidgetSizing.size(forSlot: 280) == .xl)
    }

    @Test func twoOrgsWithoutAdvice() {
        for (width, size) in [(104.0, WidgetSize.xs), (140, .s), (260, .s), (300, .m), (330, .l), (450, .xl), (560, .xl)] {
            let layout = WidgetSizing.layout(width: width, orgs: 2, advice: false)
            #expect(layout.size == size, "width \(width)")
            #expect(layout.band == .none)
            #expect(layout.slot == width / 2)
        }
    }

    @Test func widthsAreClamped() {
        #expect(WidgetSizing.layout(width: 600, orgs: 2, advice: false).width == 560)
        #expect(WidgetSizing.layout(width: 90, orgs: 2, advice: false).width == 104)
        #expect(WidgetSizing.widthRange(orgs: 2, advice: false) == 104...560)
        #expect(WidgetSizing.widthRange(orgs: 1, advice: false) == 52...280)
        #expect(WidgetSizing.widthRange(orgs: 3, advice: false) == 156...840)
        #expect(WidgetSizing.layout(width: 450, orgs: 3, advice: false).size == .m)
        // No orgs yet (signed out, loading): laid out as one.
        #expect(WidgetSizing.widthRange(orgs: 0, advice: false) == 52...280)
    }

    // The band appears at the minimum without squeezing XS: the minimum grows by its 22 pt.
    @Test func adviceGrowsTheMinimumByTheNarrowBand() {
        #expect(WidgetSizing.widthRange(orgs: 2, advice: true) == 126...560)
        let layout = WidgetSizing.layout(width: 104, orgs: 2, advice: true)
        #expect(layout.width == 126)
        #expect(layout.band == .narrow)
        #expect(layout.bandWidth == 22)
        #expect(layout.slot == 52)
        #expect(layout.size == .xs)
    }

    @Test func theBandIsNarrowUntilTheWideOneStillLeavesL() {
        let medium = WidgetSizing.layout(width: 330, orgs: 2, advice: true)
        #expect(medium.band == .narrow)
        #expect(medium.size == .m)
        #expect(medium.slot == 154)
        // 380: the narrow band leaves 179 (L) but the wide one would leave 155 (M).
        let tight = WidgetSizing.layout(width: 380, orgs: 2, advice: true)
        #expect(tight.band == .narrow)
        #expect(tight.size == .l)
        #expect(tight.slot == 179)
        let roomy = WidgetSizing.layout(width: 400, orgs: 2, advice: true)
        #expect(roomy.band == .wide)
        #expect(roomy.bandWidth == 70)
        #expect(roomy.size == .l)
        #expect(roomy.slot == 165)
    }

    @Test func stripSizes() {
        #expect(WidgetSizing.clampStrip(40) == 56)
        #expect(WidgetSizing.clampStrip(200) == 150)
        #expect(WidgetSizing.stripSize(width: 91) == .narrow)
        #expect(WidgetSizing.stripSize(width: 92) == .wide)
    }

    @Test func releaseSavesWhatTheDragEndedOn() {
        // A click, or a drag that went nowhere, saves nothing.
        #expect(WidgetSizing.widthToSave(start: 280, end: 280.3, saved: 280, narrowed: false) == nil)
        // Dragging narrower sticks, even from a narrowed widget.
        #expect(WidgetSizing.widthToSave(start: 373, end: 300, saved: 520, narrowed: true) == 300)
        // Widening a widget narrowed beside the Dock keeps the wider saved width.
        #expect(WidgetSizing.widthToSave(start: 373, end: 400, saved: 520, narrowed: true) == 520)
        #expect(WidgetSizing.widthToSave(start: 373, end: 560, saved: 520, narrowed: true) == 560)
        // A plain widen saves where it ended.
        #expect(WidgetSizing.widthToSave(start: 280, end: 340, saved: 280, narrowed: false) == 340)
    }

    @Test func compactMigratesToWidths() {
        // (#expect can't take a tuple comparison, so compare the parts.)
        let unset = WidgetSizing.migratedWidths(compact: nil)
        #expect(unset.width == 280 && unset.strip == 68)
        let compact = WidgetSizing.migratedWidths(compact: true)
        #expect(compact.width == 280 && compact.strip == 68)
        let full = WidgetSizing.migratedWidths(compact: false)
        #expect(full.width == 520 && full.strip == 104)
    }
}

/// Beside a bottom Dock, the widget narrows to the gap instead of covering the Dock. On the
/// 2560 pt display a 1773 pt Dock leaves 373.5 pt each side, floored to 373 pt (from its edge + 8 pt to 12 pt
/// from the screen edge).
@Suite struct FitBesideDockTests {
    func fitted(_ wanted: Double, spot: WidgetSpot? = nil, fit: Bool = true, dock: Double? = 1773,
                visible: CGRect = visibleWithDock) -> Double {
        WidgetSizing.fittedWidth(wanted: wanted, minimum: 104, spot: spot, fitBesideDock: fit,
                                 screen: screen, visible: visible, dockWidth: dock)
    }

    @Test func aWidgetThatFitsKeepsItsWidth() {
        #expect(fitted(280) == 280)
    }

    @Test func aWideWidgetNarrowsToTheGap() {
        #expect(fitted(520) == 373)
        #expect(fitted(520, spot: .snapped(.bottomLeft)) == 373)
        #expect(fitted(520, spot: .snapped(.bottomRight)) == 373)
    }

    // The saved width isn't touched, so a smaller Dock gives the room back.
    @Test func theWidthComesBackWhenTheDockShrinks() {
        #expect(fitted(520, dock: 1773) == 373)
        #expect(fitted(520, dock: 1400) == 520)
    }

    @Test func noRoomLeavesTheWidthToSitAboveTheDock() {
        #expect(fitted(280, dock: 2400) == 280)
    }

    @Test func onlyBottomCornersBesideABottomDock() {
        #expect(fitted(520, fit: false) == 520)
        #expect(fitted(520, spot: .snapped(.topRight)) == 520)
        #expect(fitted(520, spot: .snapped(.rightMiddle)) == 520)
        #expect(fitted(520, spot: .free(WidgetOffset(right: 40, bottom: 6))) == 520)
        #expect(fitted(520, dock: nil) == 520)
        #expect(fitted(520, visible: CGRect(x: 0, y: 0, width: 2560, height: 1415)) == 520)
    }

    // The fitted widget sits beside the Dock, at the Dock's height, not above it.
    @Test func theFittedWidgetSitsBesideTheDock() {
        let width = fitted(520)
        let origin = WidgetPlacement.origin(size: CGSize(width: width, height: 82), screen: screen,
                                            visible: visibleWithDock, spot: nil, dockWidth: 1773)
        #expect(origin.y == 6)
        #expect(origin.x >= 1280 + 1773 / 2 + 8)
    }
}

/// The status slot at the start of the widget (B3.3).
@Suite struct WidgetStatusSlotTests {
    @Test func layoutWithStatusSlot() {
        #expect(WidgetSizing.statusWidth(for: .xl, mood: .thinking) == 66)
        #expect(WidgetSizing.statusWidth(for: .l, mood: .idle) == 66)
        #expect(WidgetSizing.statusWidth(for: .m, mood: .tool) == 56)
        #expect(WidgetSizing.statusWidth(for: .s, mood: .done) == 56)
        #expect(WidgetSizing.statusWidth(for: .xs, mood: .idle) == 0)
        #expect(WidgetSizing.statusWidth(for: .xs, mood: .permission) == 30)
        #expect(WidgetSizing.statusWidth(for: .xl, mood: nil) == 0)
        // Two plans at 520: 66 comes off before they share the rest.
        let layout = WidgetSizing.layout(width: 520, orgs: 2, advice: false, week: false, status: .thinking)
        #expect(layout.statusWidth == 66)
        #expect(layout.slot == (520 - 66) / 2)
        #expect(layout.size == .xl)
        // With no mood there is no slot and the layout is the old one.
        #expect(WidgetSizing.layout(width: 520, orgs: 2, advice: false, week: false, status: nil)
                == WidgetSizing.layout(width: 520, orgs: 2, advice: false))
    }

    @Test func theSlotCanLowerTheSizeAndShrinksWithIt() {
        // 2 × 150 = 300 is M; the 66 pt slot would leave 117 (S), so the slot becomes 56 (slot 122, still S).
        let layout = WidgetSizing.layout(width: 300, orgs: 2, advice: false, week: false, status: .tool)
        #expect(layout.size == .s)
        #expect(layout.statusWidth == 56)
        #expect(layout.slot == (300 - 56) / 2)
        // At XS, idle takes no room.
        let xs = WidgetSizing.layout(width: 104, orgs: 2, advice: false, week: false, status: .idle)
        #expect(xs.statusWidth == 0 && xs.size == .xs && xs.slot == 52)
    }

    @Test func theWeekBandStillNeedsLarge() {
        let fits = WidgetSizing.layout(width: 520, orgs: 2, advice: false, week: true, status: .thinking)
        #expect(fits.weekWidth == WidgetSizing.weekBand && fits.statusWidth == 66)
        #expect(fits.slot == (520 - 96 - 66) / 2)
        #expect(fits.size == .l)
        let narrow = WidgetSizing.layout(width: 420, orgs: 2, advice: false, week: true, status: .thinking)
        #expect(narrow.weekWidth == 0)
    }

    // Review Focus 4: a 60-character name truncates; it never pushes the ring or the next plan.
    @Test func longPlanNameTruncatesNotOverlaps() {
        for size in WidgetSize.allCases {
            let slot = [WidgetSize.xs: 60.0, .s: 90, .m: 140, .l: 190, .xl: 250][size]!
            let room = GlanceLayout.nameWidth(size: size, slot: slot)
            #expect(room >= 0)
            #expect(room <= slot - 2 * GlanceLayout.padding - 12, "\(size)")
        }
        #expect(GlanceLayout.nameWidth(size: .l, slot: 190) == 190 - 16 - GlanceLayout.ringSize(.l) - GlanceLayout.ringGap - 12)
        #expect(GlanceLayout.nameWidth(size: .xl, slot: 20) == 0)
        #expect(GlanceLayout.ringSize(.xs) == 24 && GlanceLayout.ringSize(.xl) == 46)
    }
}

/// Claude Code's status moves onto the plan it is signed in to; the left slot stays only without one.
@Suite struct TideStatusPlacementTests {
    @Test func theLeftSlotStaysOnlyWhenNoPlanCarriesTheStatus() {
        // Plan cards show and Claude Code's plan is one of them: the chip is on the plan, no left slot.
        #expect(WidgetSizing.leftStatus(.thinking, plansShown: true, onShownPlan: true) == nil)
        // Its plan isn't shown, or limits are off (no plan cards), or a message replaces them: the slot stays.
        #expect(WidgetSizing.leftStatus(.thinking, plansShown: true, onShownPlan: false) == .thinking)
        #expect(WidgetSizing.leftStatus(.permission, plansShown: false, onShownPlan: false) == .permission)
        #expect(WidgetSizing.leftStatus(.idle, plansShown: false, onShownPlan: true) == .idle)
        // No mood at all: nothing to show either way.
        #expect(WidgetSizing.leftStatus(nil, plansShown: true, onShownPlan: false) == nil)
    }

    @Test func noLeftSlotLeavesTheRoomToThePlans() {
        let moved = WidgetSizing.layout(width: 300, orgs: 2, advice: false, week: false,
                                        status: WidgetSizing.leftStatus(.tool, plansShown: true, onShownPlan: true))
        #expect(moved.statusWidth == 0)
        #expect(moved.slot == 150)
        #expect(moved.size == .m)
    }
}

/// The tide slot's three forms and what each has room for.
@Suite struct TideSlotLayoutTests {
    @Test func theFormFollowsTheSize() {
        #expect(TideSlotLayout.form(for: .xs) == .xs)
        #expect(TideSlotLayout.form(for: .s) == .narrow)
        for size in [WidgetSize.m, .l, .xl] { #expect(TideSlotLayout.form(for: size) == .full) }
    }

    @Test func theChipAndTheResetTimeNeedRoom() {
        #expect(!TideSlotLayout.chipInline(slot: 150))
        #expect(!TideSlotLayout.chipInline(slot: 189.9))
        #expect(TideSlotLayout.chipInline(slot: 190))
        #expect(!TideSlotLayout.showsReset(slot: 165))
        #expect(TideSlotLayout.showsReset(slot: 250))
    }

    @Test func theStripStacksNarrowSlotsAndFallsBackToXSWhenThin() {
        #expect(TideSlotLayout.stripForm(width: 56) == .xs)
        #expect(TideSlotLayout.stripForm(width: 69.9) == .xs)
        #expect(TideSlotLayout.stripForm(width: 70) == .narrow)
        #expect(TideSlotLayout.stripForm(width: 150) == .narrow)
    }

    // MARK: Tide slots at the Dock's sizes

    /// The room a slot has at text size 1 for a Dock of `tile` pt icons: the widget's height over its scale.
    private func room(tile: Double, reserved: Double? = nil) -> Double {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // A bottom Dock reserves its bar plus 8 pt; an auto-hiding one reserves nothing.
        let visible = reserved.map { CGRect(x: 0, y: $0, width: 1512, height: 982 - $0 - 38) } ?? CGRect(x: 0, y: 0, width: 1512, height: 944)
        let height = DockFit.height(screen: screen, visible: visible, tileSize: tile)
        return height / DockFit.contentScale(screen: screen, visible: visible, tileSize: tile)
    }

    @Test func theRoomAtTheDocksSizesIsWhatTheReviewMeasured() {
        #expect(near(room(tile: 48, reserved: 90), 82, 0.1))
        #expect(near(room(tile: 64, reserved: 106), 73.5, 0.2))
        #expect(near(room(tile: 72, reserved: 114), 70.7, 0.2))
        #expect(near(room(tile: 16), 66.7, 0.1))   // auto-hide: height 50 over scale 0.75
    }

    @Test func everySlotFormFitsEveryDockSize() {
        let rooms = [66.7, 70.7, 73.5, 82, 90, 110]
        for form in [TideSlotLayout.Form.xs, .narrow, .full] {
            for r in rooms {
                let fit = TideSlotLayout.fit(form, room: r)
                #expect(fit.height(for: form) <= r + 0.001, "\(form) in \(r) pt needs \(fit.height(for: form))")
                #expect(fit.padding >= 3.5)
            }
        }
    }

    @Test func roomyFormsKeepTheirPaddingAndTheFiveHourRow() {
        #expect(TideSlotLayout.fit(.full, room: 82) == TideSlotLayout.Fit(padding: 9, fiveHour: true))
        let narrow = TideSlotLayout.fit(.narrow, room: 90)
        #expect(narrow == TideSlotLayout.Fit(padding: 8, fiveHour: true))
    }

    @Test func tightFormsTrimPaddingFirstThenDropTheFiveHourRow() {
        // Narrow needs 84 at full padding: at 82 the padding gives a little, the row stays.
        let a = TideSlotLayout.fit(.narrow, room: 82)
        #expect(a.fiveHour && a.padding < 8 && a.padding >= 3.5)
        // At 70.7 (72 pt icons) narrow can't hold the row even at minimum padding.
        #expect(TideSlotLayout.fit(.narrow, room: 70.7).fiveHour == false)
        // Full keeps its row down to the auto-hiding Dock's 66.7.
        let full = TideSlotLayout.fit(.full, room: 66.7)
        #expect(full.fiveHour)
        #expect(near(full.height(for: .full), 66.7, 0.001))
    }
}
