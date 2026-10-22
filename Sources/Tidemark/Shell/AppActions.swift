import CoreGraphics
import Foundation
import TidemarkCore

/// Everything a view can ask the app to do. Each action does nothing until the app fills it in,
/// so a view in a render or a test can take `.none`.
struct AppActions {
    /// Saves the week's report through the Claude Code report writer.
    var writeReport: (WeekModel) async -> Result<WeekReport, ReportFailure> = { _ in .failure(.notInstalled) }
    /// Opens the main window on a section, on a plan (its id) where the section has one.
    var openWindow: (MainSection?, String?) -> Void = { _, _ in }
    /// Opens the details card for a plan (its id) from the frame of what was clicked, in screen points, and
    /// what that was (a widget slot, a strip slot, a menu bar battery or the notch), which says where the card goes.
    var openDetails: (String, CGRect, DetailsAnchor) -> Void = { _, _, _ in }
    var refresh: () -> Void = {}
    var hideForAnHour: () -> Void = {}
    var openSettings: (SettingsTab) -> Void = { _ in }
    /// Opens first run's "What Tidemark reads" on its own, for a user who closed first run before choosing.
    var chooseSources: () -> Void = {}
    var signIn: () -> Void = {}
    var turnOnPlanLimits: () -> Void = {}
    var signOut: () -> Void = {}
    var quit: () -> Void = {}
    var dragChanged: () -> Void = {}
    var dragEnded: () -> Void = {}
    /// A trackpad pinch: the magnification so far, and whether the pinch has ended.
    var pinch: (CGFloat, Bool) -> Void = { _, _ in }

    static let none = AppActions()
}
