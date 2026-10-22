import Foundation

/// When the calendar may read Claude Code's and Cowork's files. Nothing is read (at launch, on the
/// 10-minute timer, after Claude Code works, after a wake) until the user has chosen what Tidemark
/// reads: first run's "What Tidemark reads" step, or Settings → Week. The first read runs the moment
/// they do, even when first run was closed early.
public enum CalendarSchedule {
    /// `sourcesChosen` is the saved setting: true once first run has left step 2 or a source was changed
    /// in Settings (the switches are theirs); `paused` while Delete all is running; `importWaiting` while an
    /// old calendar's offer is unanswered (the read would show titles its names file hides).
    public static func mayRefresh(sourcesChosen: Bool, paused: Bool = false, importWaiting: Bool = false) -> Bool {
        !paused && sourcesChosen && !importWaiting
    }

    /// Whether an old calendar waits in `calendar/import-source` and the user hasn't answered the offer yet.
    public static func importWaiting(importOffered: Bool, legacyWeeks: Int?) -> Bool {
        !importOffered && (legacyWeeks ?? 0) > 0
    }

    /// Whether leaving first run's `step` is the moment the sources get chosen: step 2.
    public static func sourcesChosen(leavingStep step: Int) -> Bool { step == 2 }
}

/// What Delete all data puts back to defaults: every saved setting except these, which are the
/// user's consent (what may be read, whether claude.ai is read), the fact that first run is done and that the old
/// calendar's import was answered (its copy stays, and an unanswered offer would hold the calendar's reads back).
public enum SettingsReset {
    public static let keptKeys: Set<String> = ["sources", "sourcesChosen", "planLimits", "firstRunDone", "importOffered", "settingsVersion"]

    /// The saved keys to remove so they come back as defaults.
    public static func keysToRemove(existing: [String]) -> [String] {
        existing.filter { !keptKeys.contains($0) }
    }
}

/// Cowork's log folder: the one the user shares with Cowork holds a "Tidemark Log" folder, and Tidemark
/// reads that one.
public enum CoworkLogFolder {
    /// The folder to store for `chosen`: itself when it already is a log folder, else `Tidemark Log`
    /// inside it, made when missing.
    public static func prepare(chosen: URL) throws -> URL {
        let names = [AppIdentity.coworkLogFolderName] + AppIdentity.legacyCoworkLogFolderNames
        if names.contains(chosen.lastPathComponent) { return chosen }
        let log = chosen.appendingPathComponent(AppIdentity.coworkLogFolderName)
        try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
        return log
    }
}
