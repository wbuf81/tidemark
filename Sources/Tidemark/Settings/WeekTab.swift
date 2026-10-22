import SwiftUI
import TidemarkCore

/// Week: what builds the week (a switch per source), the week's start, the report, importing an old
/// calendar, and the data Tidemark keeps.
struct WeekTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
    }

    static let weekStarts: [(WeekStart, String)] = [(.region, "Follow the region"), (.monday, "Monday"), (.sunday, "Sunday")]
    static let reportModes: [(ReportMode, String)] = [(.plain, "Plain"), (.claudeCode, "Written by Claude Code")]

    var body: some View {
        Form {
            if !settings.sourcesChosen {
                Section {
                    SettingRow(ShellCopy.sourcesNotChosenRow) {
                        Button(ShellCopy.sourcesNotChosenRowButton, action: hub.chooseSources)
                    }
                }
            }
            Section("Build your week from") {
                CaptionedToggle("Claude Code sessions", caption: "When each ran, its title and project", isOn: $settings.sources.claudeCode)
                CaptionedToggle("First messages", caption: "What you first asked in each session; off by default", isOn: $settings.sources.firstMessages)
                CaptionedToggle("Git commits in those projects", caption: "Only your own commits", isOn: $settings.sources.git)
                SettingRow("Cowork log folder", caption: coworkCaption) {
                    Button("Choose…", action: hub.chooseCoworkFolder)
                }
                CaptionedToggle("Claude Desktop’s older Cowork tasks",
                                caption: "Reads ~/Library/Application Support/Claude/local-agent-mode-sessions",
                                isOn: $settings.sources.desktopCowork)
            }
            Section("Calendar") {
                Picker("Week starts on", selection: $settings.weekStart) {
                    ForEach(Self.weekStarts, id: \.0) { Text($0.1).tag($0.0) }
                }
                SettingRow("Weekly report", caption: "Or written by Claude Code, after you say yes once") {
                    Picker("Weekly report", selection: $settings.reportMode) {
                        ForEach(Self.reportModes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow("Import a week calendar", caption: ShellCopy.importRow(hub.legacyFound)) {
                    Button("Import…", action: hub.showImport)
                }
            }
            Section("Your data") {
                SettingRow("Everything Tidemark keeps") {
                    HStack {
                        Button("Show in Finder", action: hub.showInFinder)
                        Button(role: .destructive, action: hub.deleteAll) {
                            Text("Delete all data…").foregroundStyle(Palette.redInk)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Under "Cowork log folder": where it is and whether it works, or what to do.
    private var coworkCaption: String {
        guard let folder = settings.sources.coworkLogFolder else { return ShellCopy.coworkNotSet }
        let path = ShellCopy.displayPath(URL(fileURLWithPath: folder), home: hub.home)
        return [path, hub.coworkStatus].compactMap { $0 }.joined(separator: " · ")
    }
}
