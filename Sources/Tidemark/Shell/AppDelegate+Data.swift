import AppKit
import ServiceManagement
import TidemarkCore

/// What the shell does with the user's data: the Cowork log, importing an old calendar, showing the
/// data, Delete all data and Uninstall.
extension AppDelegate {
    // MARK: Cowork log

    func showCoworkSheet() {
        let current = model.settings.sources.coworkLogFolder.map { URL(fileURLWithPath: $0) }
        CoworkLogSheet.present(over: sheetParent, folder: current,
                               lastEntry: { [calendar] in calendar.lastCoworkLogEntry(in: $0) }) { [weak self] url in
            self?.model.settings.sources.coworkLogFolder = url.path
            self?.refreshHub()
        }
    }

    // MARK: Import

    /// Offers the old calendar copied into `import-source` (at the end of first run, or a later launch) until it is
    /// answered. The calendar reads nothing meanwhile (`importWaiting`): Import brings the names and weeks in first and
    /// then reads, Not now reads without them.
    func offerImport() {
        guard !model.settings.importOffered, let found = calendar.findLegacy(in: importSource), found.weeks > 0 else { return }
        showImportSheet(found)
    }

    /// Settings → Week → Import…: the import sheet when the kept copy already holds a calendar, else a folder to choose.
    func importOrChoose() {
        if let found = calendar.findLegacy(in: importSource), found.weeks > 0 { showImportSheet(found) } else { chooseImportSource() }
    }

    private func showImportSheet(_ found: LegacyFound) {
        ImportSheet.present(over: sheetParent, found: found, notNow: { [weak self] in
            guard let self else { return }
            self.model.settings.importOffered = true
            self.refreshCalendar()   // waited for the answer
        }, onImport: { [weak self] in self?.runImport() })
    }

    /// Settings → Week → Import…: pick the old calendar's folder, check it is one, copy what it holds in,
    /// then offer the import. The copy already kept is only replaced once the new one has been checked.
    func chooseImportSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose the folder of your old week calendar."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let target = importSource
        // Choosing the kept copy itself: nothing to copy.
        if folder.standardizedFileURL == target.standardizedFileURL {
            guard let found = calendar.findLegacy(in: target), found.weeks > 0 else { return notFound() }
            return showImportSheet(found)
        }
        // Look before copying: a wrong folder is refused without copying it or touching the copy kept.
        guard let picked = calendar.findLegacy(in: folder), picked.weeks > 0 else { return notFound() }
        let data = folder.appendingPathComponent("data")
        var isDirectory: ObjCBool = false
        let hasData = FileManager.default.fileExists(atPath: data.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let staging = target.deletingLastPathComponent().appendingPathComponent("import-source.new")
        Task {
            do {
                try await Self.copyLegacy(hasData ? data : folder, into: hasData ? staging.appendingPathComponent("data") : staging,
                                          staging: staging)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                self.alert("Couldn’t copy that folder", error.localizedDescription)
                return
            }
            guard let found = calendar.findLegacy(in: staging), found.weeks > 0 else {
                try? FileManager.default.removeItem(at: staging)
                return notFound()
            }
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: staging) } else { try fm.moveItem(at: staging, to: target) }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                self.alert("Couldn’t copy that folder", error.localizedDescription)
                return
            }
            refreshHub()
            showImportSheet(found)
        }
    }

    private func notFound() {
        alert("No week calendar found", "That folder doesn’t hold a week calendar Tidemark can read.")
    }

    /// Copies `source` to `destination` inside a fresh `staging` folder, off the main thread.
    private nonisolated static func copyLegacy(_ source: URL, into destination: URL, staging: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                do {
                    let fm = FileManager.default
                    try? fm.removeItem(at: staging)
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    if destination != staging { try fm.copyItem(at: source, to: destination) } else {
                        try fm.removeItem(at: staging)
                        try fm.copyItem(at: source, to: staging)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Imports off the main thread (39 weeks to parse and save), then shows the weeks and lets the calendar read.
    private func runImport() {
        model.settings.importOffered = true
        let source = importSource
        let sources = model.settings.sources
        let calendar = self.calendar
        Task {
            var done: (title: String, text: String)
            do {
                let result = try await Task.detached { try calendar.importLegacy(from: source, sources: sources) }.value
                var text = "\(result.weeks) weeks imported; \(result.sessionsAdded) sessions added."
                if !result.mismatches.isEmpty {
                    text += " \(result.mismatches.count) weeks add up differently than before (by more than a minute); the originals are kept."
                }
                done = ("Imported your week calendar", text)
            } catch {
                done = ("Couldn’t import the calendar", error.localizedDescription)
            }
            // Whatever happened, the imported weeks show now and the read that waited for the answer can go.
            feedWeek()
            mainWindow.reload()
            refreshCalendar()
            refreshHub()
            alert(done.title, done.text)
        }
    }

    // MARK: Showing the data

    func showDataInFinder() {
        let folder = AppIdentity.supportURL(home: home)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Delete all data

    func askDeleteAll() {
        DeleteAllSheet.present(over: sheetParent, home: home) { [weak self] in self?.deleteAllData() }
    }

    /// Removes the calendar, history and caches, signs out and puts settings back to their defaults,
    /// except what the user chose to let Tidemark read and whether it reads claude.ai (`SettingsReset`).
    /// Keeps the hooks and the copied old calendar, and keeps running.
    private func deleteAllData() {
        calendarPaused = true
        demoOff()          // first: leaving demo data can start the poller and a calendar read
        poller.stop()
        session.shutDown()
        try? calendar.deleteAll()
        Task {
            await session.signOut()
            for url in ShellCopy.pathsToRemove(DataInventory.items(home: home), for: .deleteAll, home: home) {
                try? FileManager.default.removeItem(at: url)
            }
            model.settings.resetToDefaults()   // through UserDefaults, never by deleting the preferences file
            clearReadings()
            calendarPaused = false
            refreshHub()
            feedWeek()
            mainWindow.reload()
        }
    }

    private func demoOff() {
        if model.settings.demoMode { setDemoMode(false) }
    }

    // MARK: Uninstall

    func askUninstall() {
        UninstallSheet.present(over: sheetParent, home: home) { [weak self] in self?.uninstall() }
    }

    /// Removes everything: the hooks, the login item, the data and the settings, then quits. The app
    /// itself stays in Applications for the user to put in the Bin. If the hooks can't be taken out of
    /// Claude Code's settings it stops and says why, and removes nothing: leaving them behind would have
    /// Claude Code keep writing into a folder that's gone.
    private func uninstall() {
        do {
            // A settings file with none of Tidemark's hooks (even one that isn't plain JSON) has nothing to take out.
            if hookFile.state() != .notConnected { try hookFile.disconnect() }
        } catch {
            HooksFailureAlert.run(error, settings: ClaudePaths.settingsFile(environment: environment, home: home), file: hub.settingsFile)
            return
        }
        calendarPaused = true
        poller.stop()
        session.shutDown()
        try? SMAppService.mainApp.unregister()
        try? calendar.deleteAll()
        Task {
            await session.signOut()
            for url in ShellCopy.pathsToRemove(DataInventory.items(home: home), for: .uninstall, home: home) {
                try? FileManager.default.removeItem(at: url)
            }
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            // The support folder goes last, and only when nothing else is in it.
            let support = AppIdentity.supportURL(home: home)
            if ((try? FileManager.default.contentsOfDirectory(atPath: support.path)) ?? ["?"]).isEmpty {
                try? FileManager.default.removeItem(at: support)
            }
            NSApp.terminate(nil)
        }
    }

    // MARK: Alerts

    func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
