import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ShellCopyTests {
    @Test func menuTitlesAndShortcuts() {
        #expect(ShellCopy.mainMenus.map(\.title) == ["Tidemark", "File", "Edit", "View", "Window", "Help"])
        #expect(ShellCopy.lines(ShellCopy.viewMenu) == [
            "Usage ⌘1", "Week ⌘2", "Month ⌘3", "Trends ⌘4", "Names & Tags ⌘5", "-",
            "Previous Week ⌘[", "Next Week ⌘]", "Today ⌘T", "-", "Refresh ⌘R", "-", "Hide the Widget for an Hour", "-", "Show Sidebar ⌃⌘S",
        ])
        #expect(ShellCopy.lines(ShellCopy.appMenu) == [
            "About Tidemark", "Check for Updates…", "-", "Settings… ⌘,", "-", "Hide Tidemark ⌘H", "Hide Others ⌥⌘H",
            "Show All", "-", "Quit Tidemark ⌘Q",
        ])
        #expect(ShellCopy.lines(ShellCopy.fileMenu) == ["Close Window ⌘W", "Copy Summary ⇧⌘C"])
        #expect(ShellCopy.lines(ShellCopy.editMenu).filter { $0 != "-" } == [
            "Undo ⌘Z", "Redo ⇧⌘Z", "Cut ⌘X", "Copy ⌘C", "Paste ⌘V", "Select All ⌘A",
        ])
        #expect(ShellCopy.lines(ShellCopy.statusMenu(widgetHidden: false)) == [
            "Open Tidemark ⌘O", "Refresh now ⌘R", "Hide the widget", "Settings… ⌘,", "-", "Quit Tidemark ⌘Q",
        ])
        #expect(ShellCopy.lines(ShellCopy.statusMenu(widgetHidden: true))[2] == "Show the widget")
    }

    @Test func everyShortcutIsUniquePerMenu() {
        for (_, entries) in ShellCopy.mainMenus {
            let shortcuts = entries.compactMap { entry -> String? in
                if case .item(let spec) = entry, !spec.shortcut.isEmpty { return spec.shortcut }
                return nil
            }
            #expect(Set(shortcuts).count == shortcuts.count)
        }
    }

    @Test func menuBarStatusLine() {
        #expect(ShellCopy.menuBarStatusLine(.thinking) == "Claude Code  thinking")
        #expect(ShellCopy.menuBarStatusLine(.permission) == "Claude Code  needs you")
        #expect(ShellCopy.menuBarStatusLine(nil) == nil)
        #expect(ShellCopy.menuBarLabel(firstPlanSentence: "Personal is fine") == "Tidemark, Personal is fine")
        #expect(ShellCopy.menuBarLabel(firstPlanSentence: nil) == "Tidemark")
    }

    @Test func hideForAnHourUsesWallClock() {
        let started = designNow
        let ends = ShellTime.hideEnds(started: started, duration: ShellCopy.hideDuration)
        #expect(ends == started.addingTimeInterval(3600))
        // The Mac slept for two hours; the wall clock says the hour is over.
        #expect(ShellCopy.isHidden(until: ends, now: started.addingTimeInterval(1800)))
        #expect(!ShellCopy.isHidden(until: ends, now: started.addingTimeInterval(7200)))
        #expect(!ShellCopy.isHidden(until: nil, now: started))
    }

    @Test func notificationsFollowTheirSwitches() {
        func may(_ kind: ShellCopy.NoticeKind, _ s: Bool, _ r: Bool, _ o: Bool) -> Bool {
            ShellCopy.mayPost(kind, notifySwitch: s, notifyRed: r, notifySignedOut: o)
        }
        #expect(may(.switchAdvice, true, false, false) && !may(.switchAdvice, false, true, true))
        #expect(may(.nearlyOut, false, true, false) && !may(.nearlyOut, true, false, true))
        #expect(may(.signedOut, false, false, true) && !may(.signedOut, true, true, false))
    }

    @Test func hooksCopyFollowsTheState() {
        #expect(ShellCopy.hooksStatus(.connected) == "Connected: hooks in ~/.claude/settings.json")
        #expect(ShellCopy.hooksStatus(.notConnected) == "Not connected")
        #expect(ShellCopy.hooksStatus(.outdated) == "Outdated: update to keep the status working")
        #expect(ShellCopy.hooksButton(.notConnected) == "Add hooks…")
        #expect(ShellCopy.hooksButton(.outdated) == "Update hooks")
        #expect(ShellCopy.hooksButton(.connected) == "Remove hooks")
        #expect(ShellCopy.hooksFailureBody(reason: "settings.json isn't plain JSON, so Tidemark left it alone.")
            == "settings.json isn't plain JSON, so Tidemark left it alone. It may contain comments or a trailing comma. Fix it, then try again.")
    }

    @Test func coworkStatusWaitsThenWorks() {
        let formatting = Formatting(calendar: newYork, twentyFourHour: false)
        let task = local(2026, 10, 6, 10, 42)
        #expect(ShellCopy.coworkStatus(lastTask: nil, formatting: formatting, now: designNow) == "Waiting for Cowork’s first log line…")
        #expect(ShellCopy.coworkStatus(lastTask: task, formatting: formatting, now: designNow) == "Logging works · last task 10:42 AM")
    }

    @Test func importCopyUsesTheFoundCounts() {
        let found = LegacyFound(weeks: 39, first: "2026-01-26", last: "2026-10-19", hasNames: true, hasReports: true)
        #expect(ShellCopy.importBody(found) == "Found a week calendar with 39 weeks, 26 Jan to 19 Oct 2026, with your names, tags and reports. Tidemark copies them in; the originals aren’t changed.")
        #expect(ShellCopy.importButton(weeks: 39) == "Import 39 weeks")
        #expect(ShellCopy.importButton(weeks: 1) == "Import 1 week")
        #expect(ShellCopy.importRange(first: "2025-12-29", last: "2026-10-19") == "29 Dec 2025 to 19 Oct 2026")
        #expect(ShellCopy.importContents(hasNames: false, hasReports: false) == "")
        #expect(ShellCopy.importRow(found) == "39 weeks found")
    }

    @Test func exportNameAndDisplayPaths() {
        #expect(ShellCopy.exportFileName(on: local(2026, 10, 21, 11, 32), calendar: newYork) == "Tidemark calendar 2026-10-21.zip")
        let home = URL(fileURLWithPath: "/Users/you")
        #expect(ShellCopy.displayPath(home.appendingPathComponent("Library/Caches/x"), home: home) == "~/Library/Caches/x")
        #expect(ShellCopy.displayPath(URL(fileURLWithPath: "/Applications/Tidemark.app"), home: home) == "/Applications/Tidemark.app")
        #expect(ShellCopy.displayPath(home, home: home) == "~")
    }

    @Test func firstRunStepLabels() {
        #expect(ShellCopy.firstRunStepLabel(1) == "Step 1 of 4")
        #expect(ShellCopy.firstRunStepLabel(3) == "Step 3 of 4 · optional")
    }

    @Test func removalNeverTouchesClaudeCodesFilesOrOutsideHome() {
        let home = URL(fileURLWithPath: "/Users/you")
        func item(_ path: String, _ by: Set<Removal>) -> DataItem { DataItem(path: URL(fileURLWithPath: path), what: "x", removedBy: by) }
        let items = [
            item("/Users/you/Library/Application Support/Tidemark/calendar", [.deleteAll, .uninstall]),
            item("/Users/you/Library/Application Support/Tidemark/calendar/import-source", [.uninstall]),
            item("/Users/you/.claude/settings.json", [.uninstall]),
            item("/Users/you/Library/Caches/io.example.app", [.deleteAll, .uninstall]),
            item("/Applications/Tidemark.app", [.uninstall]),
            item("/Users/you", [.uninstall]),
            item("/Users/you/Library/Preferences/io.example.app.plist", [.deleteAll]),
        ]
        #expect(ShellCopy.pathsToRemove(items, for: .deleteAll, home: home).map(\.path) == [
            "/Users/you/Library/Application Support/Tidemark/calendar", "/Users/you/Library/Caches/io.example.app",
            "/Users/you/Library/Preferences/io.example.app.plist",
        ])
        #expect(ShellCopy.pathsToRemove(items, for: .uninstall, home: home).count == 3)
    }

    @Test func theRoundOneSheetsAreTheirMockupsWords() {
        #expect(ShellCopy.signOutTitle == "Sign out of claude.ai?")
        #expect(ShellCopy.signOutBody == "Tidemark forgets its claude.ai session and cookies, including any Google or single sign-on sign-in. Your usage history and calendar stay.")
        #expect(ShellCopy.dockAccessTitle == "Measure the Dock exactly?")
        #expect(ShellCopy.dockAccessBody == "macOS asks for Accessibility permission. Tidemark uses it only to read the Dock’s size, never what’s on your screen. Without it, the size is estimated.")
    }

    // The permission remedy is for a file that can't be read as JSON, not for every failure.
    @Test func theHooksFailureRemedyIsOnlyForUnreadableFiles() {
        #expect(ShellCopy.hooksFailureBody(reason: "settings.json isn't plain JSON, so Tidemark left it alone.", unreadable: true)
                == "settings.json isn't plain JSON, so Tidemark left it alone. It may contain comments or a trailing comma. Fix it, then try again.")
        #expect(ShellCopy.hooksFailureBody(reason: "You don’t have permission to save the file.", unreadable: false)
                == "You don’t have permission to save the file. Fix it, then try again.")
    }

    // With CLAUDE_CONFIG_DIR set the copy names the file Tidemark really changes.
    @Test func hooksCopyNamesTheRealSettingsFile() {
        let file = "~/work/claude/settings.json"
        #expect(ShellCopy.hooksFailureTitle(file: file) == "Couldn’t change ~/work/claude/settings.json")
        #expect(ShellCopy.hooksStatus(.connected, file: file) == "Connected: hooks in ~/work/claude/settings.json")
        #expect(ShellCopy.hooksCaption(file: file) == "Adds hooks to ~/work/claude/settings.json; asks first")
        #expect(ShellCopy.hooksFileLine(file: file) == "~/work/claude/settings.json, \"hooks\":")
    }

    @Test func consentCopyIsTheMockupsWords() {
        #expect(ShellCopy.planLimitsWarningHead == "Anthropic hasn't approved this.")
        #expect(ShellCopy.planLimitsWarning.hasPrefix("Tidemark reads the usage page claude.ai shows you, from its own signed-in window."))
        #expect(ShellCopy.planLimitsWarning.hasSuffix("and you can turn it off any time."))
        #expect(ShellCopy.planLimitsConfirm == "Turn on and sign in…")
        #expect(ShellCopy.signInHint.hasPrefix("Sign in to claude.ai once; Tidemark only reads your usage."))
        #expect(ShellCopy.signInHint.contains("click Open copied sign-in link below."))
        #expect(ShellCopy.hooksAdded.count == 3 && ShellCopy.hooksAdded.joined().contains("PermissionRequest"))
        #expect(ShellCopy.firstRunSources.map(\.title) == ["Claude Code sessions", "First messages", "Git commits in those projects", "Cowork tasks"])
        #expect(ShellCopy.hooksFailureTitle == "Couldn’t change ~/.claude/settings.json")
        #expect(ShellCopy.launchFailure == "Allow Tidemark in System Settings → General → Login Items")
    }
}

@Suite struct CalendarScheduleTests {
    // The calendar reads nothing until the user has chosen what it reads (first run's step 2 or Settings → Week).
    @Test func nothingIsReadUntilTheSourcesAreChosen() {
        #expect(!CalendarSchedule.mayRefresh(sourcesChosen: false))
        #expect(CalendarSchedule.mayRefresh(sourcesChosen: true))
    }

    @Test func aPausedCalendarNeverReads() {
        #expect(!CalendarSchedule.mayRefresh(sourcesChosen: true, paused: true))
    }

    // M3: an old calendar waiting to be offered (its hidden titles live in its names file) holds the first read back,
    // so no real title shows before the user has answered; Import brings the names and weeks in first, Not now reads without them.
    @Test func anOldCalendarWaitingHoldsTheReadBack() {
        #expect(CalendarSchedule.importWaiting(importOffered: false, legacyWeeks: 39))
        #expect(!CalendarSchedule.importWaiting(importOffered: true, legacyWeeks: 39))
        #expect(!CalendarSchedule.importWaiting(importOffered: false, legacyWeeks: 0))
        #expect(!CalendarSchedule.importWaiting(importOffered: false, legacyWeeks: nil))
        #expect(!CalendarSchedule.mayRefresh(sourcesChosen: true, importWaiting: true))
        #expect(CalendarSchedule.mayRefresh(sourcesChosen: true, importWaiting: false))
        #expect(!CalendarSchedule.mayRefresh(sourcesChosen: false, importWaiting: false))
    }

    @Test func leavingStepTwoIsTheMomentSourcesAreChosen() {
        #expect(!CalendarSchedule.sourcesChosen(leavingStep: 1))
        #expect(CalendarSchedule.sourcesChosen(leavingStep: 2))
        #expect(!CalendarSchedule.sourcesChosen(leavingStep: 3))
    }
}

@Suite struct SettingsResetTests {
    // Delete all keeps the user's privacy choices and first run; everything else goes back.
    @Test func deleteAllKeepsSourcesLimitsAndFirstRun() {
        let saved = ["sources", "sourcesChosen", "planLimits", "firstRunDone", "importOffered", "settingsVersion", "themeChoice", "widgetSpot", "orgChoices", "unknownLaterKey"]
        #expect(Set(SettingsReset.keysToRemove(existing: saved)) == ["themeChoice", "widgetSpot", "orgChoices", "unknownLaterKey"])
        #expect(SettingsReset.keptKeys == ["sources", "sourcesChosen", "planLimits", "firstRunDone", "importOffered", "settingsVersion"])
    }
}

@Suite struct CoworkLogFolderTests {
    func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // The sheet says to create "Tidemark Log" inside the folder; Tidemark makes it and reads that one.
    @Test func makesTheLogFolderInsideTheChosenOne() throws {
        let chosen = temp()
        let log = try CoworkLogFolder.prepare(chosen: chosen)
        #expect(log.lastPathComponent == AppIdentity.coworkLogFolderName)
        #expect(log.deletingLastPathComponent().standardizedFileURL == chosen.standardizedFileURL)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: log.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        // Choosing again changes nothing.
        #expect(try CoworkLogFolder.prepare(chosen: chosen).path == log.path)
    }

    @Test func aChosenLogFolderIsUsedAsIs() throws {
        let chosen = temp().appendingPathComponent(AppIdentity.coworkLogFolderName)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        #expect(try CoworkLogFolder.prepare(chosen: chosen) == chosen)
        let old = temp().appendingPathComponent(AppIdentity.legacyCoworkLogFolderNames[0])
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        #expect(try CoworkLogFolder.prepare(chosen: old) == old)
    }
}
