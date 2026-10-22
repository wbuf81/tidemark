import CoreGraphics
import Foundation
import Testing
@testable import TidemarkCore

/// A 2560×1440 display with the Dock at the bottom, reserving 90 pt (measured on a real Mac:
/// 48 pt icons, the Liquid Glass bar 82 pt tall floating 6 pt above the edge).
let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let visibleWithDock = CGRect(x: 0, y: 90, width: 2560, height: 1350)

@Suite struct DockFitTests {
    @Test func matchesTheDockBarFromItsReservedSpace() {
        #expect(DockFit.height(screen: screen, visible: visibleWithDock, tileSize: nil) == 82)
        let biggerDock = CGRect(x: 0, y: 106, width: 2560, height: 1334)
        #expect(DockFit.height(screen: screen, visible: biggerDock, tileSize: 64) == 98)
    }

    @Test func autoHiddenOrSideDockUsesTheIconSize() {
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: nil) == 82)
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: 64) == 98)
        let leftDock = CGRect(x: 90, y: 0, width: 2470, height: 1440)
        #expect(DockFit.height(screen: screen, visible: leftDock, tileSize: 32) == 66)
    }

    // The widget's contents track the Dock's icons, not the bar, so a taller widget doesn't
    // also grow wider and run under the Dock. The icons are measured from the bar macOS
    // actually reserves: the size setting can say 64 while macOS shrinks a full Dock to fit
    // the screen.
    @Test func contentsScaleWithTheIconsTheDockActuallyDraws() {
        #expect(DockFit.contentScale(screen: screen, visible: visibleWithDock, tileSize: 64) == 1)
        let biggerDock = CGRect(x: 0, y: 106, width: 2560, height: 1334)
        #expect(DockFit.contentScale(screen: screen, visible: biggerDock, tileSize: 48) == 64.0 / 48)
    }

    @Test func hiddenOrSideDockFallsBackToTheIconSetting() {
        #expect(DockFit.contentScale(screen: screen, visible: screen, tileSize: nil) == 1)
        #expect(DockFit.contentScale(screen: screen, visible: screen, tileSize: 64) == 64.0 / 48)
        #expect(DockFit.contentScale(screen: screen, visible: screen, tileSize: 16) == 0.75)
        #expect(DockFit.contentScale(screen: screen, visible: screen, tileSize: 128) == 1.5)
    }

    @Test func staysReadableAndSane() {
        #expect(DockFit.height(screen: screen, visible: screen, tileSize: 16) == 50)
        #expect(DockFit.height(screen: screen, visible: CGRect(x: 0, y: 400, width: 2560, height: 1040), tileSize: nil) == 140)
    }
}

/// The Dock's width, which macOS doesn't report, estimated from what it holds.
@Suite struct DockWidthTests {
    // Measured on this display: 21 items (apps, a folder, two minimized windows, the Trash)
    // and 2 dividers made a Dock 1503.5 pt wide.
    @Test func matchesTheMeasuredDock() {
        let width = DockFit.estimatedWidth(items: 21, dividers: 2, screen: screen, visible: visibleWithDock)
        #expect(width.map { near($0, 1503.5, 2) } == true)
    }

    @Test func noWidthWhenTheDockIsHiddenOrOnASide() {
        #expect(DockFit.estimatedWidth(items: 21, dividers: 2, screen: screen, visible: screen) == nil)
        let leftDock = CGRect(x: 90, y: 0, width: 2470, height: 1440)
        #expect(DockFit.estimatedWidth(items: 21, dividers: 2, screen: screen, visible: leftDock) == nil)
    }

    // Finder, the pinned apps, a section of running-but-unpinned and recent apps, the pinned
    // folders and the Trash, with a divider before the recent section and the folders.
    @Test func countsWhatTheDockShows() {
        let pinned = (1...13).map { "app.pinned\($0)" }
        let contents = DockFit.contents(pinned: pinned, recent: ["app.mail", "app.preview", "app.chrome"],
                                        running: ["com.apple.finder", "app.pinned1", "app.mail", "app.preview"],
                                        folders: 1, showRecents: true)
        #expect(contents.items == 19 && contents.dividers == 2)
        let noRecents = DockFit.contents(pinned: pinned, recent: ["app.chrome"], running: ["com.apple.finder"],
                                         folders: 1, showRecents: false)
        #expect(noRecents.items == 16 && noRecents.dividers == 1)
        let manyRecents = DockFit.contents(pinned: [], recent: ["a", "b", "c", "d", "e"], running: [],
                                           folders: 0, showRecents: true)
        #expect(manyRecents.items == 5 && manyRecents.dividers == 2)
    }

    @Test func neverWiderThanTheScreen() {
        #expect(DockFit.estimatedWidth(items: 80, dividers: 2, screen: screen, visible: visibleWithDock) == 2560)
    }
}

@Suite struct WidgetPlacementTests {
    let size = CGSize(width: 570, height: 82)

    @Test func defaultsToTheCornerBesideTheDock() {
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: nil)
                == CGPoint(x: 1978, y: 6))
    }

    @Test func bottomCornersSitBesideADockThatLeavesRoom() {
        let dock = DockFit.estimatedWidth(items: 21, dividers: 2, screen: screen, visible: visibleWithDock)
        let size = CGSize(width: 497, height: 82)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: nil, dockWidth: dock)
                == CGPoint(x: 2051, y: 6))
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .snapped(.bottomLeft), dockWidth: dock)
                == CGPoint(x: 12, y: 6))
    }

    // A 13-inch MacBook Air with 48 pt icons and a typical Dock: the corner beside the Dock
    // is under it, so the widget sits just above the Dock instead.
    @Test func bottomCornersRiseAboveADockTheyWouldOverlap() {
        let air = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let visible = CGRect(x: 0, y: 74, width: 1470, height: 857)
        let dock = DockFit.estimatedWidth(items: 18, dividers: 2, screen: air, visible: visible)
        let size = CGSize(width: 497, height: 66)
        #expect(WidgetPlacement.origin(size: size, screen: air, visible: visible, spot: nil, dockWidth: dock)
                == CGPoint(x: 961, y: 86))
        #expect(WidgetPlacement.origin(size: size, screen: air, visible: visible, spot: .snapped(.bottomLeft), dockWidth: dock)
                == CGPoint(x: 12, y: 86))
    }

    @Test func sideOrHiddenDockStaysInsideTheVisibleFrame() {
        let rightDock = CGRect(x: 0, y: 0, width: 2470, height: 1440)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: rightDock, spot: nil)
                == CGPoint(x: 1888, y: 12))
    }

    @Test func savedSpotIsKeptFromTheBottomRight() {
        let saved = WidgetOffset(right: 100, bottom: 400)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(saved))
                == CGPoint(x: 1890, y: 400))
        // A bigger widget grows left and up from the same bottom-right anchor.
        let bigger = CGSize(width: 700, height: 100)
        #expect(WidgetPlacement.origin(size: bigger, screen: screen, visible: visibleWithDock, spot: .free(saved))
                == CGPoint(x: 1760, y: 400))
    }

    @Test func savedSpotIsPulledBackOnScreen() {
        let offScreen = WidgetOffset(right: -300, bottom: 5000)
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(offScreen))
                == CGPoint(x: 1990, y: 1358))
    }

    @Test func offsetRoundTrips() {
        let origin = CGPoint(x: 1200, y: 300)
        let offset = WidgetPlacement.offset(origin: origin, size: size, screen: screen)
        #expect(offset == WidgetOffset(right: 790, bottom: 300))
        #expect(WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .free(offset)) == origin)
    }
}

@Suite struct SnapPointTests {
    let wide = CGSize(width: 481, height: 82)
    let tall = CGSize(width: 104, height: 300)

    func origin(_ point: SnapPoint, _ size: CGSize) -> CGPoint {
        WidgetPlacement.origin(size: size, screen: screen, visible: visibleWithDock, spot: .snapped(point))
    }

    @Test func cornersSitBesideTheDockOrInsideTheScreen() {
        #expect(origin(.bottomRight, wide) == CGPoint(x: 2067, y: 6))
        #expect(origin(.bottomLeft, wide) == CGPoint(x: 12, y: 6))
        #expect(origin(.topRight, wide) == CGPoint(x: 2067, y: 1346))
        #expect(origin(.topLeft, wide) == CGPoint(x: 12, y: 1346))
    }

    @Test func edgesCentreTheWidgetVertically() {
        #expect(origin(.rightMiddle, tall) == CGPoint(x: 2450, y: 615))
        #expect(origin(.leftMiddle, tall) == CGPoint(x: 6, y: 615))
    }

    @Test func noSpotMeansBottomRight() {
        #expect(WidgetPlacement.origin(size: wide, screen: screen, visible: visibleWithDock, spot: nil) == CGPoint(x: 2067, y: 6))
    }

    @Test func dropsNearASnapPointSnap() {
        func drop(_ frame: CGRect) -> SnapPoint? { WidgetPlacement.snap(frame: frame, screen: screen, visible: visibleWithDock) }
        #expect(drop(CGRect(x: 40, y: 30, width: 481, height: 82)) == .bottomLeft)
        #expect(drop(CGRect(x: 2040, y: 1320, width: 481, height: 82)) == .topRight)
        #expect(drop(CGRect(x: 2420, y: 700, width: 104, height: 300)) == .rightMiddle)
        #expect(drop(CGRect(x: 30, y: 500, width: 481, height: 82)) == .leftMiddle)
        #expect(drop(CGRect(x: 1000, y: 600, width: 481, height: 82)) == nil)
    }

    // A wide widget dropped beside a wide Dock is drawn narrower there, so it snaps by that width.
    @Test func bottomCornersSnapByTheWidthDrawnThere() {
        let drop = CGRect(x: 2028, y: 6, width: 520, height: 82)
        #expect(WidgetPlacement.snap(frame: drop, screen: screen, visible: visibleWithDock, dockWidth: 1773) == nil)
        #expect(WidgetPlacement.snap(frame: drop, screen: screen, visible: visibleWithDock, dockWidth: 1773,
                                     width: { _ in 373 }) == .bottomRight)
    }

    @Test func sideEdgesAreVerticalUnlessOverridden() {
        #expect(WidgetLayout.isVertical(spot: .snapped(.rightMiddle), choice: .automatic))
        #expect(WidgetLayout.isVertical(spot: .snapped(.leftMiddle), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: .snapped(.bottomLeft), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: .free(WidgetOffset(right: 0, bottom: 0)), choice: .automatic))
        #expect(!WidgetLayout.isVertical(spot: nil, choice: .automatic))
        #expect(WidgetLayout.isVertical(spot: .snapped(.bottomRight), choice: .vertical))
        #expect(!WidgetLayout.isVertical(spot: .snapped(.rightMiddle), choice: .horizontal))
    }

    @Test func sizesStayBetween60And200Percent() {
        #expect(WidgetLayout.clampSize(0.3) == 0.6)
        #expect(WidgetLayout.clampSize(1.25) == 1.25)
        #expect(WidgetLayout.clampSize(3) == 2)
    }

    @Test func spotsSurviveSaving() throws {
        for spot in [WidgetSpot.snapped(.leftMiddle), .free(WidgetOffset(right: 12, bottom: 40))] {
            let data = try JSONEncoder().encode(spot)
            #expect(try JSONDecoder().decode(WidgetSpot.self, from: data) == spot)
        }
    }
}

/// The widget grows and shrinks from its outer edges.
@Suite struct GrowthTests {
    func anchor(_ frame: CGRect, _ spot: WidgetSpot? = nil) -> GrowthAnchor {
        WidgetPlacement.anchor(glass: frame, visible: visibleWithDock, spot: spot)
    }

    @Test func growsTowardTheMiddleOfTheScreen() {
        #expect(anchor(CGRect(x: 2398, y: 6, width: 150, height: 82)) == GrowthAnchor(.right, .bottom))
        #expect(anchor(CGRect(x: 12, y: 6, width: 150, height: 82)) == GrowthAnchor(.left, .bottom))
        #expect(anchor(CGRect(x: 2398, y: 1346, width: 150, height: 82)) == GrowthAnchor(.right, .top))
        #expect(anchor(CGRect(x: 12, y: 1346, width: 150, height: 82)) == GrowthAnchor(.left, .top))
        #expect(anchor(CGRect(x: 900, y: 300, width: 150, height: 82), .free(WidgetOffset(right: 1510, bottom: 300)))
                == GrowthAnchor(.left, .bottom))
    }

    @Test func sideStripsGrowFromTheirMiddle() {
        let strip = CGRect(x: 2486, y: 685, width: 68, height: 160)
        #expect(anchor(strip, .snapped(.rightMiddle)) == GrowthAnchor(.right, .center))
        #expect(anchor(CGRect(x: 6, y: 685, width: 68, height: 160), .snapped(.leftMiddle)) == GrowthAnchor(.left, .center))
    }
}

@Suite struct BesideDockToleranceTests {
    // A 1773 pt Dock on 2560 pt leaves 373.5 pt at the right, from x = 2174.5.
    func origin(width: Double) -> CGPoint {
        WidgetPlacement.origin(size: CGSize(width: width, height: 82), screen: screen, visible: visibleWithDock,
                               spot: .snapped(.bottomRight), dockWidth: 1773)
    }

    @Test func aHairOverTheGapStillSitsBesideTheDock() {
        #expect(origin(width: 373.8).y == 6)
    }

    @Test func aPointOverTheGapSitsAboveTheDock() {
        #expect(origin(width: 374.5).y == visibleWithDock.minY + 12)
    }
}
