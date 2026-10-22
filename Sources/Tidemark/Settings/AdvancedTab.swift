import SwiftUI
import TidemarkCore

/// Advanced: Claude Code's status hooks, the status picture, demo data, thresholds, updates and uninstall.
struct AdvancedTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
    }

    var body: some View {
        Form {
            Section("Claude Code status") {
                SettingRow("Show what Claude Code is doing", caption: hub.hookState == .notConnected ? ShellCopy.hooksCaption(file: hub.settingsFile) : ShellCopy.hooksStatus(hub.hookState, file: hub.settingsFile)) {
                    HStack {
                        Button(ShellCopy.hooksButton(hub.hookState)) {
                            hub.changeHooks(hub.hookState == .connected ? .remove : hub.hookState == .outdated ? .update : .add)
                        }
                        if hub.hookState == .outdated {
                            Button("Remove hooks") { hub.changeHooks(.remove) }
                        }
                    }
                }
                SettingRow("Status picture", caption: "Your own GIFs: in a later version") {
                    Picker("Status picture", selection: Binding.constant("Built-in")) {
                        Text("Built-in").tag("Built-in")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow("Choose a GIF folder…") {
                    Button("Coming later") {}.disabled(true)
                }
                .foregroundStyle(Palette.dim)
            }
            Section("Other") {
                CaptionedToggle("Demo data", caption: "Show invented plans and weeks, for screenshots",
                                isOn: Binding(get: { settings.demoMode }, set: hub.setDemoMode))
                SettingRow("Reset thresholds") {
                    Button("Reset") { settings.thresholds = Thresholds() }
                }
                SettingRow("Check for updates", caption: hub.version) {
                    Button("Check…", action: hub.checkForUpdates)
                }
                SettingRow("Uninstall Tidemark") {
                    Button(role: .destructive, action: hub.uninstall) {
                        Text("Uninstall…").foregroundStyle(Palette.redInk)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
