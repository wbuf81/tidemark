import CoreGraphics
import Foundation
import Testing
@testable import TidemarkCore

/// The notch at rest: its width range and what it shows at a width.
@Suite struct NotchSizingTests {
    // The status glyph (15 pt and its gap) and the side padding come off before the plans share the rest.
    @Test func restWidthsBudgetTheGlyph() {
        #expect(NotchSizing.restRange(orgs: 1) == 87...213)
        #expect(NotchSizing.restRange(orgs: 2) == 121...373)
        #expect(NotchSizing.restRange(orgs: 3) == 155...533)
        #expect(NotchSizing.restRange(orgs: 0) == 87...213)
        #expect(NotchSizing.clampRest(40, orgs: 2) == 121)
        #expect(NotchSizing.clampRest(900, orgs: 2) == 373)
        // 53 pt of padding and glyph, then two slots.
        #expect(NotchSizing.rest(width: 53 + 2 * 62 - 1, orgs: 2, advice: false) == .rings)
        #expect(NotchSizing.rest(width: 53 + 2 * 62, orgs: 2, advice: false) == .percents)
        #expect(NotchSizing.rest(width: 214, orgs: 2, advice: false) == .percents)
        #expect(NotchSizing.rest(width: 53 + 2 * 98, orgs: 2, advice: false) == .bars)
        #expect(NotchSizing.rest(width: 53 + 2 * 136, orgs: 2, advice: false) == .numbers)
        // The switch glyph takes 22 pt first.
        #expect(NotchSizing.rest(width: 53 + 2 * 98, orgs: 2, advice: true) == .percents)
        #expect(NotchSizing.rest(width: 53 + 22 + 2 * 98, orgs: 2, advice: true) == .bars)
    }

    // S2.6: the widest rest shows the urgent plan's % instead of a dash.
    @Test func urgentPercentAtWidest() {
        #expect(NotchSizing.urgentIndex([.fine, .runsOutEarly]) == 1)
        #expect(NotchSizing.urgentIndex([.out, .runsOutEarly, .fine]) == 0)
        #expect(NotchSizing.urgentIndex([.fine, .fine]) == 0)
        #expect(NotchSizing.urgentIndex([.fine, .out, .out]) == 1)
        #expect(NotchSizing.urgentIndex([]) == nil)
    }

    // S2.5: a plan with no reading yet has no state: the hollow "couldn't read" shape, never amber.
    @Test func unreadPlanHasNoState() {
        #expect(NotchSizing.urgentIndex([nil, nil]) == nil)
        #expect(NotchSizing.urgentIndex([nil, .fine]) == 1)
        #expect(NotchSizing.urgentIndex([.fine, nil]) == 0)
    }

    @Test func hairlinesShareOneWidth() {
        #expect(NotchSizing.hairlineWidth >= NotchSizing.continuousBelow)
    }

    @Test func openWidthIsTheWidgetsMOrL() {
        let m = NotchSizing.openWidth(orgs: 2, size: .m, advice: false)
        let l = NotchSizing.openWidth(orgs: 2, size: .l, advice: false)
        #expect(m == 300)
        #expect(l == 420)
        // With Claude Code's status slot (56 at M, 66 at L) in front of the cards.
        #expect(NotchSizing.openWidth(orgs: 2, size: .m, advice: false, status: .tool) == 356)
        #expect(NotchSizing.openWidth(orgs: 2, size: .l, advice: false, status: .tool) == 486)
        #expect(WidgetSizing.layout(width: 356, orgs: 2, advice: false, week: false, status: .tool).size == .m)
        #expect(WidgetSizing.layout(width: 486, orgs: 2, advice: false, week: false, status: .tool).size == .l)
        #expect(WidgetSizing.layout(width: m, orgs: 2, advice: false).size == .m)
        #expect(WidgetSizing.layout(width: l, orgs: 2, advice: false).size == .l)
    }

    // M4: the open notch at its default (Large) shows what the widget does at its default width: the 5-hour line with its
    // reset time ("↺ 4:20pm") and the week's note with the words ("~20% would go unused"), not the clipped short forms.
    // The widget's two-plan default leaves each plan a 199 pt slot, so the open notch gives at least that.
    @Test func theOpenNotchAtLargeKeepsBothResetTimes() {
        let fmt = Formatting(calendar: newYork, twentyFourHour: false)
        let widgetRoom = GlanceLayout.noteWidth(size: .l, slot: 199)
        #expect(NotchSizing.openWidth(orgs: 1, size: .l, advice: false) >= 199)
        for orgs in 1...3 { for advice in [false, true] where !advice || orgs > 1 {   // advice needs two plans
            let width = NotchSizing.openWidth(orgs: orgs, size: .l, advice: advice, status: .tool)
            let layout = WidgetSizing.layout(width: width, orgs: orgs, advice: advice, week: false, status: .tool)
            #expect(layout.size == .l, "\(orgs) plans, advice \(advice): \(layout.size)")
            let room = GlanceLayout.noteWidth(size: layout.size, slot: layout.slot)
            #expect(room >= widgetRoom, "\(orgs) plans, advice \(advice): room \(room)")
            let g = Glance.make(reading(week: 40, weekResetsAt: local(2026, 10, 9, 4)), history: [], now: designNow)
            let picked = Copy.fitting(Copy.weekNoteForms(g.week, now: designNow, formatting: fmt), width: room, fontSize: GlanceLayout.noteFontSize(layout.size))
            #expect(picked.text.contains("would go unused"), "\(picked.text) in \(room)")
        } }
    }

    // The open notch shows the widget's tide slots: 86 pt tall, and even at M each plan gets the full form.
    @Test func theOpenNotchHoldsTideSlots() {
        #expect(NotchSizing.openHeight == 86)
        for size in [NotchOpenSize.m, .l] {
            let width = NotchSizing.openWidth(orgs: 2, size: size, advice: false)
            let layout = WidgetSizing.layout(width: width, orgs: 2, advice: false, week: false, status: nil)
            #expect(TideSlotLayout.form(for: layout.size) == .full, "\(size)")
        }
    }

    @Test func openWidthMakesRoomForTheSwitchBand() {
        let m = NotchSizing.openWidth(orgs: 2, size: .m, advice: true)
        let l = NotchSizing.openWidth(orgs: 2, size: .l, advice: true)
        #expect(m == 322)
        #expect(l == 490)
        let ml = WidgetSizing.layout(width: m, orgs: 2, advice: true)
        #expect(ml.size == .m)
        #expect(ml.band == .narrow)
        let ll = WidgetSizing.layout(width: l, orgs: 2, advice: true)
        #expect(ll.size == .l)
        #expect(ll.band == .wide)
    }
}

/// Where the notch's glass and window go. The 2560 × 1440 display has a 25 pt menu bar and a
/// bottom Dock reserving 90 pt.
@Suite struct NotchPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let visible = CGRect(x: 0, y: 90, width: 2560, height: 1325)
    let rest = CGSize(width: 214, height: 38)
    let open = CGSize(width: 380, height: 84)

    func frames(_ size: CGSize, _ place: NotchPlace, _ look: NotchLook, visible v: CGRect? = nil) -> NotchFrames {
        NotchPlacement.frames(size: size, place: place, look: look, screen: screen, visible: v ?? visible)
    }

    @Test func hardwareTopRightIsFlushUnderTheMenuBarWithFlares() {
        let f = frames(rest, .topRight, .hardware)
        #expect(f.glass == CGRect(x: 2346, y: 1377, width: 214, height: 38))
        #expect(f.window == CGRect(x: 2332, y: 1363, width: 228, height: 52))
    }

    @Test func hardwareBottomRightIsFlushInTheCorner() {
        let f = frames(rest, .bottomRight, .hardware)
        #expect(f.glass == CGRect(x: 2346, y: 0, width: 214, height: 38))
        #expect(f.window == CGRect(x: 2332, y: 0, width: 228, height: 52))
    }

    @Test func islandFloatsOffTheEdges() {
        let top = frames(rest, .topRight, .island)
        #expect(top.glass == CGRect(x: 2338, y: 1371, width: 214, height: 38))
        #expect(top.window == CGRect(x: 2314, y: 1347, width: 262, height: 86))
        let bottom = frames(rest, .bottomRight, .island)
        #expect(bottom.glass == CGRect(x: 2338, y: 8, width: 214, height: 38))
        #expect(bottom.window == CGRect(x: 2314, y: -16, width: 262, height: 86))
    }

    @Test func theFlareScalesWithTheText() {
        let f = NotchPlacement.frames(size: CGSize(width: 428, height: 76), place: .topRight, look: .hardware,
                                      screen: screen, visible: visible, scale: 2)
        #expect(f.glass == CGRect(x: 2132, y: 1339, width: 428, height: 76))
        #expect(f.window == CGRect(x: 2104, y: 1311, width: 456, height: 104))
    }

    @Test func itGrowsFromItsCorner() {
        for look in NotchLook.allCases {
            for place in NotchPlace.allCases {
                let a = frames(rest, place, look).glass, b = frames(open, place, look).glass
                #expect(a.maxX == b.maxX, "\(look) \(place)")
                if place == .topRight { #expect(a.maxY == b.maxY, "\(look) \(place)") }
                else { #expect(a.minY == b.minY, "\(look) \(place)") }
            }
        }
    }

    @Test func aRightDockPushesItLeft() {
        let rightDock = CGRect(x: 0, y: 0, width: 2470, height: 1415)
        #expect(frames(rest, .topRight, .hardware, visible: rightDock).glass.maxX == 2470)
        #expect(frames(rest, .bottomRight, .island, visible: rightDock).glass.maxX == 2462)
    }

    @Test func opensNoNarrowerThanRest() {
        #expect(NotchSizing.openWidth(orgs: 2, size: .m, advice: false, restWidth: 320) == 320)
        #expect(NotchSizing.openWidth(orgs: 2, size: .m, advice: false, restWidth: 214) == 300)
    }
}
