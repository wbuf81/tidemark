import Foundation
import TidemarkCore

/// Show the widget beside the Dock, or the notch at the screen's edge.
enum DisplayMode: String, CaseIterable, Codable {
    case widget, notch
    var title: String { self == .widget ? "Widget" : "Notch" }
}

/// How the weekly report is written: from the calendar's own text, or by Claude Code.
enum ReportMode: String, CaseIterable, Codable {
    case plain, claudeCode
}

/// The owner's choices, saved in UserDefaults on this Mac only.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var thresholds: Thresholds { didSet { save(thresholds, "thresholds") } }
    @Published var primaryOrg: String? { didSet { defaults.set(primaryOrg, forKey: "primaryOrg") } }
    /// Org id → shown, for the orgs the owner turned on or off; the rest follow the default.
    @Published var orgChoices: [String: Bool] { didSet { defaults.set(orgChoices, forKey: "orgChoices") } }
    @Published var knownOrgs: [Org] { didSet { save(knownOrgs, "knownOrgs") } }
    @Published var notifySwitch: Bool { didSet { defaults.set(notifySwitch, forKey: "notifySwitch") } }
    /// Which version of the saved settings this is; see `SettingsSchema`.
    @Published var settingsVersion: Int { didSet { defaults.set(settingsVersion, forKey: "settingsVersion") } }
    /// What the menu bar shows: a battery per plan, Tidemark's icon, or nothing. Replaced the old `menuBarIcon` switch.
    @Published var menuBarMode: MenuBarMode { didSet { defaults.set(menuBarMode.rawValue, forKey: "menuBarMode") } }
    /// Whether a battery shows its plan's name or first letter.
    @Published var planNameStyle: PlanNameStyle { didSet { defaults.set(planNameStyle.rawValue, forKey: "planNameStyle") } }
    /// Whether Tidemark reads claude.ai for plan limits. Off until the owner opts in.
    @Published var planLimits: Bool { didSet { defaults.set(planLimits, forKey: "planLimits") } }
    @Published var notifyRed: Bool { didSet { defaults.set(notifyRed, forKey: "notifyRed") } }
    @Published var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demoMode") } }
    /// Where the owner put the widget; nil means the bottom-right corner.
    @Published var widgetSpot: WidgetSpot? { didSet { save(widgetSpot, "widgetSpot") } }
    @Published var layoutChoice: LayoutChoice { didSet { defaults.set(layoutChoice.rawValue, forKey: "layoutChoice") } }
    /// A multiple of the Dock-matched size, 0.6...2.
    @Published var sizeScale: Double { didSet { defaults.set(sizeScale, forKey: "sizeScale") } }
    /// The horizontal widget's width and the side strip's, in points at text size 1.
    @Published var widgetWidth: Double { didSet { defaults.set(widgetWidth, forKey: "widgetWidth") } }
    @Published var stripWidth: Double { didSet { defaults.set(stripWidth, forKey: "stripWidth") } }
    /// Beside a bottom Dock, narrow the widget to the gap instead of covering the Dock.
    @Published var fitBesideDock: Bool { didSet { defaults.set(fitBesideDock, forKey: "fitBesideDock") } }
    /// Read the Dock's real size through the Accessibility API, so minimized windows count.
    @Published var measureDock: Bool { didSet { defaults.set(measureDock, forKey: "measureDock") } }
    @Published var displayMode: DisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") } }
    @Published var notchLook: NotchLook { didSet { defaults.set(notchLook.rawValue, forKey: "notchLook") } }
    @Published var notchPlace: NotchPlace { didSet { defaults.set(notchPlace.rawValue, forKey: "notchPlace") } }
    @Published var notchOpensTo: NotchOpenSize { didSet { defaults.set(notchOpensTo.rawValue, forKey: "notchOpensTo") } }
    /// A line along the notch's inner edge in the most urgent colour.
    @Published var notchRim: Bool { didSet { defaults.set(notchRim, forKey: "notchRim") } }
    /// The notch's width at rest, in points at text size 1.
    @Published var notchWidth: Double { didSet { defaults.set(notchWidth, forKey: "notchWidth") } }
    /// How an org that's in use shows it, and how many particles.
    /// How each plan's tide is drawn in the widget: the water level, or the week as it filled.
    @Published var tideStyle: TideStyle { didSet { defaults.set(tideStyle.rawValue, forKey: "tideStyle") } }
    @Published var effectStyle: EffectStyle { didSet { defaults.set(effectStyle.rawValue, forKey: "effectStyle") } }
    @Published var effectAmount: EffectAmount { didSet { defaults.set(effectAmount.rawValue, forKey: "effectAmount") } }
    @Published var themeChoice: ThemeChoice { didSet { defaults.set(themeChoice.rawValue, forKey: "themeChoice") } }
    /// The Insights window's model rows (Fable) and 5-hour rows.
    @Published var showModelRows: Bool { didSet { defaults.set(showModelRows, forKey: "showModelRows") } }
    @Published var showSessionRows: Bool { didSet { defaults.set(showSessionRows, forKey: "showSessionRows") } }
    /// Picture files behind the Insights window, for the light and dark looks.
    @Published var wallpaperDay: String? { didSet { defaults.set(wallpaperDay, forKey: "wallpaperDay") } }
    @Published var wallpaperNight: String? { didSet { defaults.set(wallpaperNight, forKey: "wallpaperNight") } }
    /// What builds the week, and which day it starts on.
    @Published var sources: SourceSwitches { didSet { save(sources, "sources"); sourcesChosen = true } }
    /// The user has chosen what Tidemark reads (first run's step 2, or any change in Settings → Week); the calendar reads nothing before.
    @Published var sourcesChosen: Bool { didSet { defaults.set(sourcesChosen, forKey: "sourcesChosen") } }
    @Published var weekStart: WeekStart { didSet { defaults.set(weekStart.rawValue, forKey: "weekStart") } }
    /// Back to "Plain" takes the consent back too: the next "Write it with Claude Code" asks again.
    @Published var reportMode: ReportMode {
        didSet {
            defaults.set(reportMode.rawValue, forKey: "reportMode")
            if reportMode == .plain, claudeCodeReportConsented { claudeCodeReportConsented = false }
        }
    }
    @Published var claudeCodeReportConsented: Bool { didSet { defaults.set(claudeCodeReportConsented, forKey: "claudeCodeReportConsented") } }
    @Published var firstRunDone: Bool { didSet { defaults.set(firstRunDone, forKey: "firstRunDone") } }
    @Published var importOffered: Bool { didSet { defaults.set(importOffered, forKey: "importOffered") } }
    /// The notices already posted, so a relaunch doesn't post them again.
    @Published var noticeLog: NoticeLog { didSet { save(noticeLog, "noticeLog") } }
    @Published var notifySignedOut: Bool { didSet { defaults.set(notifySignedOut, forKey: "notifySignedOut") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        Self.migrate(defaults)
        thresholds = Self.load(Thresholds.self, "thresholds", defaults) ?? Thresholds()
        primaryOrg = defaults.string(forKey: "primaryOrg")
        let known = Self.load([Org].self, "knownOrgs", defaults) ?? []
        knownOrgs = known
        // Earlier versions saved the list of shown orgs.
        orgChoices = defaults.dictionary(forKey: "orgChoices") as? [String: Bool]
            ?? defaults.stringArray(forKey: "shownOrgs").map { OrgFilter.choices(fromShown: $0, known: known) } ?? [:]
        notifySwitch = defaults.object(forKey: "notifySwitch") as? Bool ?? true
        notifyRed = defaults.object(forKey: "notifyRed") as? Bool ?? true
        settingsVersion = defaults.object(forKey: "settingsVersion") as? Int ?? SettingsSchema.version
        menuBarMode = MenuBarMode.migrated(saved: defaults.string(forKey: "menuBarMode"), legacyIcon: defaults.object(forKey: "menuBarIcon") as? Bool)
        planNameStyle = PlanNameStyle(rawValue: defaults.string(forKey: "planNameStyle") ?? "") ?? .names
        planLimits = defaults.object(forKey: "planLimits") as? Bool ?? false
        demoMode = defaults.bool(forKey: "demoMode")
        widgetSpot = Self.load(WidgetSpot.self, "widgetSpot", defaults)
        layoutChoice = LayoutChoice(rawValue: defaults.string(forKey: "layoutChoice") ?? "") ?? .automatic
        sizeScale = WidgetLayout.clampSize(defaults.object(forKey: "sizeScale") as? Double ?? 1)
        widgetWidth = defaults.object(forKey: "widgetWidth") as? Double ?? WidgetSizing.migratedWidths(compact: nil).width
        stripWidth = defaults.object(forKey: "stripWidth") as? Double ?? WidgetSizing.migratedWidths(compact: nil).strip
        fitBesideDock = defaults.object(forKey: "fitBesideDock") as? Bool ?? true
        measureDock = defaults.object(forKey: "measureDock") as? Bool ?? false
        displayMode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .widget
        notchLook = NotchLook(rawValue: defaults.string(forKey: "notchLook") ?? "") ?? .hardware
        notchPlace = NotchPlace(rawValue: defaults.string(forKey: "notchPlace") ?? "") ?? .topRight
        notchOpensTo = NotchOpenSize(rawValue: defaults.string(forKey: "notchOpensTo") ?? "") ?? .l
        notchRim = defaults.object(forKey: "notchRim") as? Bool ?? false
        notchWidth = defaults.object(forKey: "notchWidth") as? Double ?? 214
        tideStyle = TideStyle(rawValue: defaults.string(forKey: "tideStyle") ?? "") ?? .level
        effectStyle = EffectStyle(rawValue: defaults.string(forKey: "effectStyle") ?? "") ?? .flow
        effectAmount = EffectAmount(rawValue: defaults.string(forKey: "effectAmount") ?? "") ?? .normal
        themeChoice = ThemeChoice(rawValue: defaults.string(forKey: "themeChoice") ?? "") ?? .followMac
        showModelRows = defaults.object(forKey: "showModelRows") as? Bool ?? true
        showSessionRows = defaults.object(forKey: "showSessionRows") as? Bool ?? true
        wallpaperDay = defaults.string(forKey: "wallpaperDay")
        wallpaperNight = defaults.string(forKey: "wallpaperNight")
        sources = Self.load(SourceSwitches.self, "sources", defaults) ?? SourceSwitches()
        sourcesChosen = defaults.object(forKey: "sourcesChosen") as? Bool ?? false
        weekStart = WeekStart(rawValue: defaults.string(forKey: "weekStart") ?? "") ?? .region
        reportMode = ReportMode(rawValue: defaults.string(forKey: "reportMode") ?? "") ?? .plain
        claudeCodeReportConsented = defaults.object(forKey: "claudeCodeReportConsented") as? Bool ?? false
        firstRunDone = defaults.object(forKey: "firstRunDone") as? Bool ?? false
        importOffered = defaults.object(forKey: "importOffered") as? Bool ?? false
        notifySignedOut = defaults.object(forKey: "notifySignedOut") as? Bool ?? true
        noticeLog = Self.load(NoticeLog.self, "noticeLog", defaults) ?? NoticeLog()
        // Save the migration once; otherwise it would rerun on every launch against whatever
        // orgs are known by then, hiding any joined since.
        if defaults.object(forKey: "shownOrgs") != nil {
            defaults.set(orgChoices, forKey: "orgChoices")
            defaults.removeObject(forKey: "shownOrgs")
        }
    }

    /// Back to the defaults a new install starts with, for Delete all data. What `SettingsReset` keeps
    /// stays: what Tidemark may read (`sources`, `sourcesChosen`), whether it reads claude.ai (`planLimits`), that first
    /// run is done, and the settings' version. Every other saved key is removed from the defaults (so a
    /// key a later version adds comes back as its default too), then read again.
    func resetToDefaults() {
        for key in SettingsReset.keysToRemove(existing: Array(defaults.dictionaryRepresentation().keys)) {
            defaults.removeObject(forKey: key)
        }
        let fresh = Settings(defaults: defaults)
        thresholds = fresh.thresholds; primaryOrg = fresh.primaryOrg; orgChoices = fresh.orgChoices
        knownOrgs = fresh.knownOrgs; notifySwitch = fresh.notifySwitch; menuBarMode = fresh.menuBarMode; planNameStyle = fresh.planNameStyle
        notifyRed = fresh.notifyRed; demoMode = fresh.demoMode
        widgetSpot = fresh.widgetSpot; layoutChoice = fresh.layoutChoice; sizeScale = fresh.sizeScale
        widgetWidth = fresh.widgetWidth; stripWidth = fresh.stripWidth; fitBesideDock = fresh.fitBesideDock
        measureDock = fresh.measureDock; displayMode = fresh.displayMode; notchLook = fresh.notchLook
        notchPlace = fresh.notchPlace; notchOpensTo = fresh.notchOpensTo; notchRim = fresh.notchRim
        notchWidth = fresh.notchWidth; tideStyle = fresh.tideStyle; effectStyle = fresh.effectStyle; effectAmount = fresh.effectAmount
        themeChoice = fresh.themeChoice; showModelRows = fresh.showModelRows; showSessionRows = fresh.showSessionRows
        wallpaperDay = fresh.wallpaperDay; wallpaperNight = fresh.wallpaperNight
        weekStart = fresh.weekStart; reportMode = fresh.reportMode
        claudeCodeReportConsented = fresh.claudeCodeReportConsented
        importOffered = fresh.importOffered; notifySignedOut = fresh.notifySignedOut; noticeLog = fresh.noticeLog
    }

    /// Runs `SettingsSchema.migrate` on what's saved, writing only what changed.
    private static func migrate(_ defaults: UserDefaults) {
        let before = defaults.dictionaryRepresentation()
        let after = SettingsSchema.migrate(before, from: defaults.object(forKey: "settingsVersion") as? Int)
        for key in before.keys where after[key] == nil { defaults.removeObject(forKey: key) }
        for (key, value) in after where before[key].map({ !($0 as AnyObject).isEqual(value) }) ?? true {
            defaults.set(value, forKey: key)
        }
    }

    /// Whether an org is shown: the owner's choice, or by default every paid org (or every
    /// org, for an account with none).
    func isShown(_ org: Org) -> Bool {
        OrgFilter.shown(knownOrgs, choices: orgChoices).contains { $0.id == org.id }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
