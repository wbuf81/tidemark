import Foundation

/// The names and identifiers that never change after release. Everything else reads them from
/// here. The `legacy…` values name the app's earlier life and exist only so an older install's
/// files and hooks are still recognised.
public enum AppIdentity {
    public static let name = "Tidemark"
    public static let bundleID = "io.github.wbuf81.tidemark"
    public static let supportFolderName = "Tidemark"
    public static let hooksMarker = "# tidemark"
    public static let legacyHooksMarkers = ["# claude-dock"]
    public static let legacyBundleID = "com.wbuf81.claudedock"
    public static let legacySupportFolderName = "ClaudeDock"
    public static let webStoreID = UUID(uuidString: "8AD323F0-8465-42C6-98BD-6E670027E1DC")!
    public static let coworkLogFolderName = "Tidemark Log"
    public static let legacyCoworkLogFolderNames = ["Claude Calendar Log"]
    public static let weekSummaryFormat = "week-summary/1"
    public static let envPrefix = "TIDEMARK_"
    public static let releasesURL = URL(string: "https://github.com/wbuf81/tidemark/releases")!

    /// `home/Library/Application Support/Tidemark`
    public static func supportURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support").appendingPathComponent(supportFolderName)
    }
    /// The calendar's files, under the support folder.
    public static func calendarURL(home: URL) -> URL { supportURL(home: home).appendingPathComponent("calendar") }
    /// The hook files, one per Claude Code process, under the support folder.
    public static func sessionsURL(home: URL) -> URL { supportURL(home: home).appendingPathComponent("sessions") }
}
