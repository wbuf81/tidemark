import Foundation
import Testing
@testable import TidemarkCore

@Suite struct DataInventoryTests {
    /// A home with a calendar (one file beside `import-source`), history, sessions and a backup.
    func populated() throws -> URL {
        let home = fakeHome()
        let fm = FileManager.default
        let calendar = AppIdentity.calendarURL(home: home)
        try fm.createDirectory(at: calendar.appendingPathComponent("import-source"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: calendar.appendingPathComponent("names.json"))
        try fm.createDirectory(at: calendar.appendingPathComponent("weeks"), withIntermediateDirectories: true)
        let support = AppIdentity.supportURL(home: home)
        try Data().write(to: support.appendingPathComponent("history.jsonl"))
        try Data().write(to: support.appendingPathComponent("settings-before-update-20261021-101500.json"))
        try fm.createDirectory(at: AppIdentity.sessionsURL(home: home), withIntermediateDirectories: true)
        return home
    }

    func items(_ home: URL) -> [DataItem] { DataInventory.items(home: home, environment: [:]) }

    @Test func deleteAllKeepsHooksAndImportSource() throws {
        let home = try populated()
        let removed = items(home).filter { $0.removedBy.contains(.deleteAll) }
        let paths = removed.map(\.path.path)
        let calendar = AppIdentity.calendarURL(home: home).path
        #expect(paths.contains("\(calendar)/names.json"))
        #expect(paths.contains("\(calendar)/weeks"))
        #expect(!paths.contains(calendar))
        #expect(!paths.contains { $0.contains("import-source") })
        #expect(!paths.contains { $0.hasSuffix(".claude/settings.json") })
        // No removed path is the parent of import-source.
        let importSource = AppIdentity.calendarURL(home: home).appendingPathComponent("import-source").path
        #expect(!paths.contains { importSource.hasPrefix($0 + "/") })
        for name in ["history.jsonl", "sessions", "report", "settings-before-update-20261021-101500.json", AppIdentity.bundleID] {
            #expect(paths.contains { $0.hasSuffix("/" + name) }, "missing \(name)")
        }
    }

    // L9: Delete all resets settings through UserDefaults; the preferences file itself is Uninstall's to remove.
    @Test func deleteAllLeavesThePreferencesFileToTheDefaultsSystem() throws {
        let home = try populated()
        let plist = "\(AppIdentity.bundleID).plist"
        let deleteAll = items(home).filter { $0.removedBy.contains(.deleteAll) }.map(\.path.lastPathComponent)
        #expect(!deleteAll.contains(plist))
        let uninstall = items(home).filter { $0.removedBy.contains(.uninstall) }.map(\.path.lastPathComponent)
        #expect(uninstall.contains(plist))
    }

    @Test func uninstallCoversEverything() throws {
        let home = try populated()
        let all = items(home)
        let uninstallOnly = all.filter { $0.removedBy == [.uninstall] }.map(\.path.path)
        #expect(uninstallOnly.contains { $0.hasSuffix("calendar/import-source") })
        #expect(uninstallOnly.contains(ClaudePaths.settingsFile(environment: [:], home: home).path))
        #expect(all.allSatisfy { $0.removedBy.contains(.uninstall) })
        #expect(all.allSatisfy { !$0.what.isEmpty })
        let paths = all.map(\.path.path)
        for part in ["Library/Preferences/\(AppIdentity.bundleID).plist", "Library/WebKit/\(AppIdentity.bundleID)",
                     "Library/HTTPStorages/\(AppIdentity.bundleID)", "Library/Caches/\(AppIdentity.bundleID)"] {
            #expect(paths.contains { $0.hasSuffix(part) }, "missing \(part)")
        }
    }

    @Test func httpStoragesMatchesEveryVariantOnDisk() throws {
        let home = try populated()
        let storages = home.appendingPathComponent("Library/HTTPStorages")
        for name in [AppIdentity.bundleID, "\(AppIdentity.bundleID).binarycookies", "com.example.other"] {
            try FileManager.default.createDirectory(at: storages.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let found = items(home).map(\.path.lastPathComponent)
        #expect(found.contains("\(AppIdentity.bundleID).binarycookies"))
        #expect(!found.contains("com.example.other"))
    }

    // macOS keeps a window-state folder for the app; it goes with Delete all and Uninstall.
    @Test func savedWindowStateIsRemovedToo() throws {
        let home = try populated()
        let saved = items(home).first { $0.path.lastPathComponent == "\(AppIdentity.bundleID).savedState" }
        #expect(saved?.path.deletingLastPathComponent().lastPathComponent == "Saved Application State")
        #expect(saved?.removedBy == [.deleteAll, .uninstall])
    }

    @Test func pathsAreUnderHome() throws {
        for home in [try populated(), fakeHome()] {
            let prefix = home.standardizedFileURL.path + "/"
            #expect(items(home).allSatisfy { $0.path.standardizedFileURL.path.hasPrefix(prefix) })
        }
    }

    @Test func anEmptyHomeStillListsTheCalendarAndHooks() {
        let all = items(fakeHome())
        #expect(all.contains { $0.path.lastPathComponent == "calendar" && $0.removedBy.contains(.deleteAll) })
        #expect(all.contains { $0.removedBy == [.uninstall] })
    }
}

@Suite struct ShellTimeTests {
    @Test func hideEndsByTheWallClockSoSleepCantStretchIt() {
        let started = designNow
        let ends = ShellTime.hideEnds(started: started, duration: 3600)
        #expect(ends == started.addingTimeInterval(3600))
        // The Mac slept for eight hours: on waking, the hour is long over, whatever a timer counted.
        #expect(ShellTime.hideIsOver(started: started, duration: 3600, now: started.addingTimeInterval(8 * 3600)))
        #expect(!ShellTime.hideIsOver(started: started, duration: 3600, now: started.addingTimeInterval(3599)))
    }
}
