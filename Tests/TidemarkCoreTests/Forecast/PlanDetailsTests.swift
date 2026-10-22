import Testing
import Foundation
import CoreGraphics
@testable import TidemarkCore

@Suite struct PlanDetailsSuite {
    static let now = local(2026, 10, 7, 11, 32)
    static let reset = local(2026, 10, 11, 9)

    static func harbor(old: Bool = false, history: Bool = true) -> PlanDetails {
        let r = reading(org: "harbor", week: 81, weekResetsAt: reset, session: 12,
                        sessionResetsAt: now.addingTimeInterval(2.5 * 3600), at: now)
        let past = history ? [reading(org: "harbor", week: 40, weekResetsAt: reset, at: local(2026, 10, 4, 10)),
                              reading(org: "harbor", week: 60, weekResetsAt: reset, at: local(2026, 10, 5, 10)),
                              reading(org: "harbor", week: 70, weekResetsAt: reset, at: local(2026, 10, 7, 9)),
                              reading(org: "harbor", week: 74, weekResetsAt: reset, at: local(2026, 10, 7, 10, 30))] : []
        return PlanDetails.make(reading: r, history: past, now: now, formatting: fmt, isOld: old)
    }

    @Test func fillsEveryPartForAPlanThatRunsOutEarly() throws {
        let d = Self.harbor()
        #expect(d.state == .runsOutEarly)
        #expect(d.left == 19)
        #expect(d.sentence == "34 h until empty, if the pace holds")
        #expect(d.locked == "Locked 59 h, back Sun 9 AM")
        #expect(d.pie != nil)
        #expect(d.chart != nil)
        #expect(d.hasHistory)
        #expect(d.asOf == nil)
        #expect(d.pace?.level == .fast)
        #expect(d.fiveHour.used == 12)
        #expect(d.fiveHour.resets == "resets 2:02 PM")
        let knob = try #require(d.fiveHour.now)
        #expect(near(knob, 50, 0.5))   // 2.5 of 5 hours to go
        #expect(d.busiest.count == 3)
        #expect(d.busiest.allSatisfy { $0.range.contains("–") && $0.used.hasSuffix("%") })
    }

    @Test func aFinePlanSaysTheVerdictLineAndNoLockedLine() {
        let r = reading(week: 40, weekResetsAt: Self.now.addingTimeInterval(84 * 3600), at: Self.now)
        let d = PlanDetails.make(reading: r, history: [], now: Self.now, formatting: fmt, isOld: false)
        #expect(d.state == .fine)
        #expect(d.sentence == "~20% left at reset")
        #expect(d.locked == nil)
    }

    @Test func anOldReadingSaysAsOf() {
        let d = Self.harbor(old: true)
        #expect(d.asOf == "As of 11:32 AM")
    }

    @Test func noHistoryHidesChartAndHours() {
        let d = Self.harbor(history: false)
        #expect(!d.hasHistory)
        #expect(d.busiest.isEmpty)
        #expect(d.left == 19)
    }

    @Test func noFiveHourWindowIsNotStarted() {
        let r = reading(week: 10, weekResetsAt: Self.reset, at: Self.now)
        let d = PlanDetails.make(reading: r, history: [], now: Self.now, formatting: fmt, isOld: false)
        #expect(d.fiveHour.resets == "not started")
        #expect(d.fiveHour.now == nil)
    }

    @Test func aFullWeekSaysSinceWhenItWasLockedAndHasNoPace() {
        let out = local(2026, 10, 5, 18)
        let r = reading(org: "harbor", week: 100, weekResetsAt: Self.reset, at: Self.now)
        let history = [reading(org: "harbor", week: 40, weekResetsAt: Self.reset, at: local(2026, 10, 4, 10)),
                       reading(org: "harbor", week: 100, weekResetsAt: Self.reset, at: out)]
        let d = PlanDetails.make(reading: r, history: history, now: Self.now, formatting: fmt, isOld: false)
        #expect(d.state == .out)
        #expect(d.left == 0)
        #expect(d.locked == "Locked since Mon 6 PM")
        #expect(d.pace == nil)
        #expect(d.sentence == "Out until Sun 9 AM")
    }

    @Test func aNearlyOutWeekIsNotLocked() {
        let r = reading(org: "harbor", week: 92, weekResetsAt: Self.reset, at: Self.now)
        let d = PlanDetails.make(reading: r, history: [], now: Self.now, formatting: fmt, isOld: false)
        #expect(d.state == .out)
        #expect(d.sentence == "Nearly out · 8% left")
        #expect(d.locked == nil)
        #expect(d.pace != nil)
    }
}

@Suite struct DetailsPlacementSuite {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let size = CGSize(width: 300, height: 460)

    @Test func aboveAWidgetInTheLowerHalf() {
        let widget = CGRect(x: 600, y: 8, width: 240, height: 82)
        let f = DetailsPlacement.frame(anchor: widget, from: .slot, size: Self.size, screen: Self.screen)
        #expect(f.minY == widget.maxY + DetailsPlacement.gap)
        #expect(f.midX == widget.midX)
        #expect(f.width == 300)
    }

    @Test func belowAnItemInTheUpperHalf() {
        let item = CGRect(x: 900, y: 878, width: 60, height: 22)
        let f = DetailsPlacement.frame(anchor: item, from: .slot, size: Self.size, screen: Self.screen)
        #expect(f.maxY == item.minY - DetailsPlacement.gap)
    }

    @Test func staysOnTheScreen() {
        let corner = CGRect(x: 1400, y: 878, width: 40, height: 22)
        let f = DetailsPlacement.frame(anchor: corner, from: .slot, size: Self.size, screen: Self.screen)
        #expect(f.maxX <= Self.screen.maxX - DetailsPlacement.margin)
        let low = CGRect(x: 0, y: 0, width: 80, height: 60)
        let g = DetailsPlacement.frame(anchor: low, from: .slot, size: Self.size, screen: Self.screen)
        #expect(g.minX >= Self.screen.minX + DetailsPlacement.margin)
    }

    @Test func besideAStripOnTheLeftOpensToItsRight() {
        let strip = CGRect(x: 6, y: 400, width: 70, height: 120)
        let f = DetailsPlacement.frame(anchor: strip, from: .stripSlot, size: Self.size, screen: Self.screen)
        #expect(f.minX == strip.maxX + DetailsPlacement.gap)
        #expect(f.midY == strip.midY)
    }

    @Test func besideAStripOnTheRightOpensToItsLeft() {
        let strip = CGRect(x: 1364, y: 100, width: 70, height: 120)
        let f = DetailsPlacement.frame(anchor: strip, from: .stripSlot, size: Self.size, screen: Self.screen)
        #expect(f.maxX == strip.minX - DetailsPlacement.gap)
        #expect(f.minY >= Self.screen.minY + DetailsPlacement.margin)
    }

    @Test func aTallCardIsShrunkToFit() {
        let widget = CGRect(x: 600, y: 8, width: 240, height: 82)
        let f = DetailsPlacement.frame(anchor: widget, from: .slot, size: CGSize(width: 300, height: 2000), screen: Self.screen)
        #expect(f.maxY <= Self.screen.maxY - DetailsPlacement.margin)
    }

    @Test func aMenuBarBatteryDropsTheCardBelowEvenWhenTheWidgetIsAStrip() {
        // The visible frame stops under the menu bar; the battery sits in the bar above it.
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 878)
        let battery = CGRect(x: 1100, y: 878, width: 90, height: 22)
        let f = DetailsPlacement.frame(anchor: battery, from: .menuBar, size: Self.size, screen: visible)
        #expect(f.maxY <= visible.maxY - DetailsPlacement.margin)
        #expect(f.midX == battery.midX)
        // Never beside the item, over the other menu bar items.
        #expect(f.minY < battery.minY)
        #expect(f.width == 300)
    }

    @Test func theNotchDropsTheCardBelowIt() {
        let notch = CGRect(x: 600, y: 860, width: 240, height: 40)
        let f = DetailsPlacement.frame(anchor: notch, from: .notch, size: Self.size, screen: CGRect(x: 0, y: 0, width: 1440, height: 878))
        #expect(f.maxY <= 878 - DetailsPlacement.margin)
        #expect(f.midX == notch.midX)
    }

    @Test func aCardThatGrowsKeepsItsTopUnderTheMenuBar() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 878)
        let battery = CGRect(x: 1100, y: 878, width: 90, height: 22)
        let short = DetailsPlacement.frame(anchor: battery, from: .menuBar, size: CGSize(width: 300, height: 400), screen: visible)
        let tall = DetailsPlacement.frame(anchor: battery, from: .menuBar, size: CGSize(width: 300, height: 460), screen: visible)
        #expect(short.maxY == tall.maxY)
        #expect(tall.minY < short.minY)
        // Above a widget slot it grows up: the bottom edge stays.
        let slot = CGRect(x: 600, y: 8, width: 240, height: 82)
        let a = DetailsPlacement.frame(anchor: slot, from: .slot, size: CGSize(width: 300, height: 400), screen: visible)
        let b = DetailsPlacement.frame(anchor: slot, from: .slot, size: CGSize(width: 300, height: 460), screen: visible)
        #expect(a.minY == b.minY)
    }
}
