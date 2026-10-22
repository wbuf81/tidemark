import Foundation

/// The words and tables of the app shell: menus, sheets, first run, notifications. Copy comes from
/// the approved mockups (`#menubar`, `#consent`, `#firstrun`, `#settings`); anything the mockups
/// don't have is in their voice. The app lays these out; tests pin them here.
public enum ShellCopy {
    // MARK: Menus

    public enum KeyModifier: String, Sendable, CaseIterable {
        case control, option, shift, command

        /// The glyph a menu shows, in the Mac's order: ⌃ ⌥ ⇧ ⌘.
        public var glyph: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    /// One menu item: what it says, which action it is (the app maps `id` to code) and its shortcut.
    public struct MenuItemSpec: Equatable, Sendable {
        public var id: String
        public var title: String
        public var key: String
        public var modifiers: Set<KeyModifier>

        public init(_ id: String, _ title: String, key: String = "", _ modifiers: Set<KeyModifier> = [.command]) {
            self.id = id
            self.title = title
            self.key = key
            self.modifiers = key.isEmpty ? [] : modifiers
        }

        /// "⇧⌘C", or "" without a shortcut.
        public var shortcut: String {
            guard !key.isEmpty else { return "" }
            return KeyModifier.allCases.filter(modifiers.contains).map(\.glyph).joined() + key.uppercased()
        }

        /// "Usage ⌘1", for text listings and tests.
        public var line: String { shortcut.isEmpty ? title : "\(title) \(shortcut)" }
    }

    public enum MenuEntry: Equatable, Sendable {
        case item(MenuItemSpec)
        case separator
    }

    private static func item(_ id: String, _ title: String, key: String = "", _ modifiers: Set<KeyModifier> = [.command]) -> MenuEntry {
        .item(MenuItemSpec(id, title, key: key, modifiers))
    }

    /// The menu bar's menus by title, in order. Standard Edit and Window items use AppKit's own
    /// selectors (their ids are the selector names), so the system fills in the rest.
    public static let mainMenus: [(title: String, entries: [MenuEntry])] = [
        (AppIdentity.name, appMenu), ("File", fileMenu), ("Edit", editMenu), ("View", viewMenu),
        ("Window", windowMenu), ("Help", helpMenu),
    ]

    public static let appMenu: [MenuEntry] = [
        item("about", "About \(AppIdentity.name)"),
        item("updates", "Check for Updates…"),
        .separator,
        item("settings", "Settings…", key: ","),
        .separator,
        item("hide", "Hide \(AppIdentity.name)", key: "h"),
        item("hideOthers", "Hide Others", key: "h", [.command, .option]),
        item("showAll", "Show All"),
        .separator,
        item("quit", "Quit \(AppIdentity.name)", key: "q"),
    ]

    public static let fileMenu: [MenuEntry] = [
        item("close", "Close Window", key: "w"),
        item("copySummary", "Copy Summary", key: "c", [.command, .shift]),
    ]

    public static let editMenu: [MenuEntry] = [
        item("undo:", "Undo", key: "z"),
        item("redo:", "Redo", key: "z", [.command, .shift]),
        .separator,
        item("cut:", "Cut", key: "x"),
        item("copy:", "Copy", key: "c"),
        item("paste:", "Paste", key: "v"),
        item("selectAll:", "Select All", key: "a"),
    ]

    public static let viewMenu: [MenuEntry] = [
        item("usage", "Usage", key: "1"),
        item("week", "Week", key: "2"),
        item("month", "Month", key: "3"),
        item("trends", "Trends", key: "4"),
        item("names", "Names & Tags", key: "5"),
        .separator,
        item("previousWeek", "Previous Week", key: "["),
        item("nextWeek", "Next Week", key: "]"),
        item("today", "Today", key: "t"),
        .separator,
        item("refresh", "Refresh", key: "r"),
        .separator,
        // With the menu bar icon off this is the only keyboard-reachable way to hide the widget (D12).
        item("hideWidget", "Hide the Widget for an Hour"),
        .separator,
        item("sidebar", "Show Sidebar", key: "s", [.command, .control]),
    ]

    public static let windowMenu: [MenuEntry] = [
        item("performMiniaturize:", "Minimize", key: "m"),
        item("performZoom:", "Zoom"),
        .separator,
        item("arrangeInFront:", "Bring All to Front"),
    ]

    public static let helpMenu: [MenuEntry] = [
        item("help", "\(AppIdentity.name) Help"),
    ]

    /// The menu bar icon's menu, under the plan lines and Claude Code's status.
    public static func statusMenu(widgetHidden: Bool) -> [MenuEntry] {
        [
            item("open", "Open \(AppIdentity.name)", key: "o"),
            item("refresh", "Refresh now", key: "r"),
            item("toggleWidget", widgetHidden ? "Show the widget" : "Hide the widget"),
            item("settings", "Settings…", key: ","),
            .separator,
            item("quit", "Quit \(AppIdentity.name)", key: "q"),
        ]
    }

    /// Every item of a menu as text, one per line ("Usage ⌘1"; "-" for a separator).
    public static func lines(_ entries: [MenuEntry]) -> [String] {
        entries.map {
            switch $0 {
            case .item(let spec): spec.line
            case .separator: "-"
            }
        }
    }

    /// "Claude Code  thinking": Claude Code's status line in the menu bar icon's menu; nil with no mood.
    public static func menuBarStatusLine(_ mood: CodeMood?) -> String? {
        mood.map { "Claude Code  \($0.word.lowercased())" }
    }

    /// The menu bar button's VoiceOver label.
    public static func menuBarLabel(firstPlanSentence: String?) -> String {
        firstPlanSentence.map { "\(AppIdentity.name), \($0)" } ?? AppIdentity.name
    }

    // MARK: Notifications

    public enum NoticeKind: Sendable { case switchAdvice, nearlyOut, signedOut }

    /// Whether a notice may be posted, from the three Notifications switches.
    public static func mayPost(_ kind: NoticeKind, notifySwitch: Bool, notifyRed: Bool, notifySignedOut: Bool) -> Bool {
        switch kind {
        case .switchAdvice: notifySwitch
        case .nearlyOut: notifyRed
        case .signedOut: notifySignedOut
        }
    }

    // MARK: Hide for an hour

    public static let hideDuration: TimeInterval = 3600

    /// Whether a hide that ends at `ends` is still on at `now`. Compared on the wall clock, so a
    /// sleep in between counts.
    public static func isHidden(until ends: Date?, now: Date) -> Bool {
        ends.map { $0 > now } ?? false
    }

    // MARK: Plan limits (claude.ai)

    public static let planLimitsTitle = "Turn on plan limits?"
    public static let planLimitsIntro = "You’ll sign in to claude.ai in Tidemark’s own window. Tidemark then reads your usage page every 3 minutes."
    public static let planLimitsWarningHead = "Anthropic hasn't approved this."
    public static let planLimitsWarning = "Tidemark reads the usage page claude.ai shows you, from its own signed-in window. Anthropic's terms don't allow apps to use your claude.ai sign-in this way, so they could block it or act on your account. It's off unless you turn it on, and you can turn it off any time."
    public static let planLimitsPassword = "Your password goes to claude.ai, never to Tidemark."
    public static let planLimitsConfirm = "Turn on and sign in…"

    public static let signInHint = "Sign in to claude.ai once; Tidemark only reads your usage. Signing in by email? In the email, right-click the sign-in link and choose Copy Link, then click Open copied sign-in link below."
    public static let openCopiedLink = "Open copied sign-in link"
    public static let signInWindowTitle = "Sign in to claude.ai"

    // MARK: Cowork log

    public static let coworkTitle = "Log Cowork tasks for Tidemark"
    public static let coworkIntro = "Cowork can’t tell other apps what it did, so it writes a line to a file after each task, and Tidemark reads that file."
    public static let coworkStep1 = "Choose a folder you share with Cowork."
    public static let coworkStep2 = "Paste the instruction into Cowork’s instructions."
    public static let coworkNote = "Tidemark reads only that file, nothing else in the folder."
    public static let coworkWaiting = "Waiting for Cowork’s first log line…"
    public static let coworkNotSet = "Not set · Tidemark shows what to paste into Cowork"

    /// What sits under a chosen folder: the folder to create inside it.
    public static func coworkSuggestion(folderName: String = AppIdentity.coworkLogFolderName) -> String {
        "Create a folder called “\(folderName)” inside it; Tidemark reads the log there."
    }

    /// "Logging works · last task 10:42 AM", or the waiting line until there is a first one.
    public static func coworkStatus(lastTask: Date?, formatting: Formatting = Formatting(), now: Date = Date()) -> String {
        guard let lastTask else { return coworkWaiting }
        return "Logging works · last task \(formatting.dayTime(lastTask, now: now))"
    }

    // MARK: Hooks

    public static let hooksTitle = "Show what Claude Code is doing?"
    public static let hooksIntro = "Tidemark adds a hook to eight of Claude Code’s events, so it knows within a second when Claude Code is thinking, working, or waiting for you. Each hook writes one word and the time to a file in Tidemark’s folder."
    public static let defaultSettingsFile = "~/.claude/settings.json"

    /// The code box's first line; `file` is the settings file as the user sees it (it moves with CLAUDE_CONFIG_DIR).
    public static func hooksFileLine(file: String = defaultSettingsFile) -> String { "\(file), \"hooks\":" }
    public static let hooksAdded = ["SessionStart, UserPromptSubmit, PreToolUse,", "PostToolUse, Notification, PermissionRequest,",
                                    "Stop, SessionEnd (each marked # tidemark)"]
    public static let hooksNote = "A copy of the file is kept first. Disconnect removes only Tidemark’s hooks."

    public static func hooksStatus(_ state: HookState, file: String = defaultSettingsFile) -> String {
        switch state {
        case .connected: "Connected: hooks in \(file)"
        case .notConnected: "Not connected"
        case .outdated: "Outdated: update to keep the status working"
        }
    }

    public static func hooksButton(_ state: HookState) -> String {
        switch state {
        case .notConnected: "Add hooks…"
        case .outdated: "Update hooks"
        case .connected: "Remove hooks"
        }
    }

    public static let hooksCaption = hooksCaption()
    public static let hooksFailureTitle = hooksFailureTitle()

    public static func hooksCaption(file: String = defaultSettingsFile) -> String { "Adds hooks to \(file); asks first" }
    public static func hooksFailureTitle(file: String = defaultSettingsFile) -> String { "Couldn’t change \(file)" }

    /// "<reason>. It may contain comments or a trailing comma. Fix it, then try again." The remedy is only
    /// for a file that can't be read as JSON (`unreadable`); any other reason gets "Fix it, then try again."
    public static func hooksFailureBody(reason: String, unreadable: Bool = true) -> String {
        var why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while why.hasSuffix(".") { why.removeLast() }
        return "\(why). " + (unreadable ? "It may contain comments or a trailing comma. " : "") + "Fix it, then try again."
    }

    // MARK: Sign out, Measure the Dock (round 1's sheets)

    public static let signOutTitle = "Sign out of claude.ai?"
    public static let signOutBody = "Tidemark forgets its claude.ai session and cookies, including any Google or single sign-on sign-in. Your usage history and calendar stay."
    public static let signOutConfirm = "Sign out"
    public static let dockAccessTitle = "Measure the Dock exactly?"
    public static let dockAccessBody = "macOS asks for Accessibility permission. Tidemark uses it only to read the Dock’s size, never what’s on your screen. Without it, the size is estimated."
    public static let dockAccessConfirm = "Open System Settings"

    // MARK: Delete all, export, uninstall

    public static let deleteTitle = "Delete all of Tidemark’s data?"
    public static let deleteBody = "Removes your calendar, names, tags, reports and usage history from this Mac, and signs out of claude.ai. Claude Code’s own files and your git repositories aren’t touched."
    public static let deleteNote = "Weeks older than 30 days exist only in Tidemark. Export them first if you want to keep them."
    /// What Delete all leaves, so "all" isn't a promise it breaks.
    public static let deleteKeeps = "The copy of your old week calendar and Claude Code’s hooks stay until you uninstall. What Tidemark may read stays as you set it."

    /// `Tidemark calendar 2026-10-21.zip`, in the Mac's current calendar.
    public static func exportFileName(on date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "\(AppIdentity.name) calendar %04d-%02d-%02d.zip", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static let uninstallTitle = "Uninstall Tidemark?"
    public static let uninstallBody = "Removes everything Tidemark keeps on this Mac, takes its hooks out of Claude Code’s settings, stops it launching at login, then quits. Claude Code’s own files and your git repositories aren’t touched."
    public static let uninstallList = "This removes:"
    public static let uninstallNote = "Tidemark itself stays in Applications: drag it to the Bin when it has quit."
    public static let uninstallExportNote = "Weeks older than 30 days exist only in Tidemark. Export them first if you want to keep them."

    /// `url` as the sheet shows it: `~/…` under `home`, else the full path.
    public static func displayPath(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path, root = home.standardizedFileURL.path
        if path == root { return "~" }
        return path.hasPrefix(root + "/") ? "~" + path.dropFirst(root.count) : path
    }

    /// The files and folders to delete for `removal`: the inventory's items for it, only those under
    /// `home`, and never Claude Code's own files (its settings and anything in `.claude`; the hooks
    /// are taken out of that file by the hook code, not deleted with it). Longest paths last-safe:
    /// a folder and something inside it both listed is fine, deleting the folder takes both.
    public static func pathsToRemove(_ items: [DataItem], for removal: Removal, home: URL) -> [URL] {
        let root = home.standardizedFileURL.path + "/"
        return items.filter { $0.removedBy.contains(removal) }.map(\.path).filter { url in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root), path != root else { return false }
            let parts = url.standardizedFileURL.pathComponents
            return !parts.contains(".claude") && url.lastPathComponent != "settings.json" && url.lastPathComponent != ".claude.json"
        }
    }

    // MARK: Import

    public static let importTitle = "Import your week calendar?"

    /// "26 Jan to 19 Oct 2026" (years on both ends when they differ).
    public static func importRange(first: String, last: String) -> String {
        func parts(_ s: String) -> (y: Int, m: Int, d: Int)? {
            let p = s.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? (p[0], p[1], p[2]) : nil
        }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard let a = parts(first), let b = parts(last), (1...12).contains(a.m), (1...12).contains(b.m) else { return "\(first) to \(last)" }
        let start = a.y == b.y ? "\(a.d) \(months[a.m - 1])" : "\(a.d) \(months[a.m - 1]) \(a.y)"
        return "\(start) to \(b.d) \(months[b.m - 1]) \(b.y)"
    }

    /// ", with your names, tags and reports", or "" when it has neither.
    public static func importContents(hasNames: Bool, hasReports: Bool) -> String {
        switch (hasNames, hasReports) {
        case (true, true): ", with your names, tags and reports"
        case (true, false): ", with your names and tags"
        case (false, true): ", with your reports"
        case (false, false): ""
        }
    }

    /// "Found a week calendar with 39 weeks, 26 Jan to 19 Oct 2026, with your names, tags and reports. …"
    public static func importBody(_ found: LegacyFound) -> String {
        let weeks = found.weeks == 1 ? "1 week" : "\(found.weeks) weeks"
        return "Found a week calendar with \(weeks), \(importRange(first: found.first, last: found.last))"
            + "\(importContents(hasNames: found.hasNames, hasReports: found.hasReports)). "
            + "Tidemark copies them in; the originals aren’t changed."
    }

    public static func importButton(weeks: Int) -> String { weeks == 1 ? "Import 1 week" : "Import \(weeks) weeks" }

    /// Settings → Week's row: "39 weeks found", or a plain line without one.
    public static func importRow(_ found: LegacyFound?) -> String {
        guard let found else { return "No old week calendar found" }
        return found.weeks == 1 ? "1 week found" : "\(found.weeks) weeks found"
    }

    // MARK: Notifications sheet

    public static let notifyTitle = "Get notified?"
    public static let notifyBody = "Tidemark can tell you when Claude Code should move to another plan, when the plan it’s on is nearly out, and if claude.ai signs you out. macOS asks next."

    // MARK: Settings captions

    public static let launchFailure = "Allow Tidemark in System Settings → General → Login Items"
    public static let launchOff = "Off until you turn it on"
    public static let switchNeedsTwoPlans = "Switch advice needs two plans"

    // MARK: First run

    public static let firstRunSteps = 4
    public static let firstRunWelcomeTitle = "Welcome to Tidemark"
    public static let firstRunWelcomeBody = "What Claude Code did this week, how much of your Claude plan is left, and what Claude Code is doing right now, at the edge of your screen."
    public static let firstRunBullets = ["A calendar of your Claude Code sessions, built on this Mac", "Claude Code’s status, beside your Dock",
                                         "Your plan’s limits and a forecast, if you want them"]
    public static let firstRunReadsTitle = "What Tidemark reads"
    public static let firstRunReadsBody = "Everything stays on this Mac. Turn off anything you don’t want."
    public static let firstRunSources: [(title: String, detail: String)] = [
        ("Claude Code sessions", "When each ran, its title and project, from ~/.claude/projects."),
        ("First messages", "What you first asked in each session. Off unless you turn it on."),
        ("Git commits in those projects", "Only your own commits."),
        ("Cowork tasks", "Needs a log folder; set it up later in Settings → Week."),
    ]
    /// Settings → Week while nothing has been chosen yet: the one row, and its button (opens step 2 on its own).
    public static let sourcesNotChosenRow = "Tidemark isn’t reading anything yet"
    public static let sourcesNotChosenRowButton = "Choose what it reads…"
    public static let firstRunReadsNote = "Settings → Week → Delete all data removes everything Tidemark has kept."
    public static let firstRunLimitsTitle = "Show your plan’s limits?"
    public static let firstRunLimitsBody = "Tidemark can show your 5-hour window and week for each plan, and warn you before one runs out. It needs you to sign in to claude.ai in Tidemark’s own window."
    public static let firstRunDoneTitle = "You’re set"
    public static let firstRunDoneBody = "Tidemark is beside your Dock and in the menu bar. Click either to open the window."
    public static let firstRunDoneNote = "Optional, in Settings: show what Claude Code is doing (hooks), launch at login, notifications."

    /// "Step 3 of 4 · optional"
    public static func firstRunStepLabel(_ step: Int) -> String {
        "Step \(step) of \(firstRunSteps)" + (step == 3 ? " · optional" : "")
    }
}
