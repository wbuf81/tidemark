import Foundation

// Shared by the shell's two halves (frozen, docs/contracts.md). The app half codes against these;
// the core half replaces the bodies marked "Wave 0 stand-in" and nothing else.

/// Whether Tidemark's hooks are in Claude Code's settings, and current.
public enum HookState: Equatable, Sendable {
    case notConnected, connected
    /// Ours (by marker, including the old `# claude-dock`) but not today's commands.
    case outdated

    /// Whether Claude Code's live status may come from the hooks. Only today's hooks write where Tidemark
    /// looks; older ones (from before the rename) write elsewhere, so the status falls back to transcript activity.
    public var feedsLiveStatus: Bool { self == .connected }
}

extension ClaudeCodeHookFile {
    /// `.outdated` when ours (by any marker, old or new) but not exactly today's commands.
    public func state() -> HookState { currentState() }

    /// One write: removes every hook group with any of our markers, adds today's, keeps the rest.
    /// A file that can't be read is never written; a backup of the file as it was comes first.
    public func update() throws { try performUpdate() }
}

/// When an item is removed: by Delete all data, or only by Uninstall.
public enum Removal: Hashable, Sendable {
    case deleteAll, uninstall
}

/// Something Tidemark keeps on this Mac, for Delete all data and Uninstall.
public struct DataItem: Equatable, Sendable {
    public var path: URL
    /// In words, for the sheet: "Your calendar, names and reports".
    public var what: String
    public var removedBy: Set<Removal>

    public init(path: URL, what: String, removedBy: Set<Removal>) {
        self.path = path
        self.what = what
        self.removedBy = removedBy
    }
}

public enum DataInventory {
    /// Everything Tidemark keeps under `home`, for the Delete all data and Uninstall sheets. The
    /// login item isn't a path, so the app lists it itself. Calendar folders are listed by their
    /// children, so removing "your calendar" can never take the imported-from folder with it.
    public static func items(home: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> [DataItem] {
        let fm = FileManager.default
        let support = AppIdentity.supportURL(home: home)
        let calendar = AppIdentity.calendarURL(home: home)
        let both: Set<Removal> = [.deleteAll, .uninstall]
        let id = AppIdentity.bundleID
        var items: [DataItem] = []

        let importSource = calendar.appendingPathComponent("import-source")
        let children = ((try? fm.contentsOfDirectory(atPath: calendar.path)) ?? []).filter { $0 != "import-source" }.sorted()
        if children.isEmpty {
            // Nothing there now; a folder of its own would also take import-source with it.
            if !fm.fileExists(atPath: importSource.path) {
                items.append(DataItem(path: calendar, what: "Your calendar, names and reports", removedBy: both))
            }
        } else {
            items += children.map { DataItem(path: calendar.appendingPathComponent($0), what: "Your calendar, names and reports", removedBy: both) }
        }
        items.append(DataItem(path: importSource, what: "The copy of your old calendar that Tidemark imported from", removedBy: [.uninstall]))
        items.append(DataItem(path: support.appendingPathComponent("history.jsonl"), what: "Your usage history", removedBy: both))
        items.append(DataItem(path: AppIdentity.sessionsURL(home: home), what: "What Claude Code is doing right now", removedBy: both))
        items.append(DataItem(path: support.appendingPathComponent("report", isDirectory: true),
                              what: "The empty folder “Write it with Claude Code” runs in", removedBy: both))
        items.append(DataItem(path: support.appendingPathComponent("backups"), what: "Backups Tidemark made before changing files", removedBy: both))
        let loose = ((try? fm.contentsOfDirectory(atPath: support.path)) ?? []).filter {
            $0.hasPrefix("settings-before-") || $0.hasPrefix("settings-after-") || $0 == "settings-was-missing"
        }.sorted()
        items += loose.map { DataItem(path: support.appendingPathComponent($0), what: "Backups Tidemark made before changing files", removedBy: both) }

        let library = home.appendingPathComponent("Library")
        // Delete all puts the settings back through UserDefaults (`resetToDefaults`): deleting the plist under the
        // preferences daemon isn't supported and can bring old values back. Only Uninstall removes the file.
        items.append(DataItem(path: library.appendingPathComponent("Preferences/\(id).plist"), what: "Your settings", removedBy: [.uninstall]))
        items.append(DataItem(path: library.appendingPathComponent("WebKit/\(id)"), what: "The claude.ai sign-in", removedBy: both))
        let storages = library.appendingPathComponent("HTTPStorages")
        let stored = ((try? fm.contentsOfDirectory(atPath: storages.path)) ?? []).filter { $0.hasPrefix(id) }.sorted()
        items += (stored.isEmpty ? [id] : stored).map {
            DataItem(path: storages.appendingPathComponent($0), what: "Network cookies and caches", removedBy: both)
        }
        items.append(DataItem(path: library.appendingPathComponent("Caches/\(id)"), what: "Cached files", removedBy: both))
        items.append(DataItem(path: library.appendingPathComponent("Saved Application State/\(id).savedState"),
                              what: "Where its windows were", removedBy: both))
        items.append(DataItem(path: ClaudePaths.settingsFile(environment: environment, home: home),
                              what: "Tidemark's hooks in Claude Code's settings", removedBy: [.uninstall]))
        return items
    }
}

public enum ShellTime {
    /// When "Hide for an hour" ends, by the wall clock, so sleep can't stretch it.
    /// A wall-clock date: a timer that counts only awake time (a monotonic clock) would stop while the
    /// Mac sleeps, so "an hour" would stretch; comparing `Date()` with this doesn't.
    public static func hideEnds(started: Date, duration: TimeInterval) -> Date { started.addingTimeInterval(duration) }

    /// Whether a hide that began at `started` has run out by `now`.
    public static func hideIsOver(started: Date, duration: TimeInterval, now: Date) -> Bool {
        now >= hideEnds(started: started, duration: duration)
    }
}
