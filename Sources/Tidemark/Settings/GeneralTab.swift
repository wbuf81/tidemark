import ServiceManagement
import SwiftUI
import TidemarkCore

/// General: how Tidemark shows, its theme, the menu bar, launch at login, and the one switch
/// that lets it read claude.ai.
struct GeneralTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
        model = hub.model
    }

    var body: some View {
        Form {
            if settings.planLimits && !model.signedIn {
                Section {
                    SettingRow("Signed out of claude.ai", caption: "Plan limits need you signed in.") {
                        Button("Sign in to claude.ai…", action: hub.signIn)
                    }
                }
            }
            Section(AppIdentity.name) {
                Picker("Show as", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Theme", selection: $settings.themeChoice) {
                    ForEach(ThemeChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Menu bar", selection: $settings.menuBarMode) {
                    ForEach(MenuBarMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.menuBarMode == .batteries {
                    Picker("Plan names", selection: $settings.planNameStyle) {
                        ForEach(PlanNameStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    CaptionedToggle("Launch at login", caption: hub.launchFailed || hub.launchesAtLogin ? nil : ShellCopy.launchOff,
                                    isOn: Binding(get: { hub.launchesAtLogin }, set: hub.setLaunchAtLogin))
                    if hub.launchFailed {
                        HStack {
                            Caption(ShellCopy.launchFailure)
                            Spacer()
                            Button("Open") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                        }
                    }
                }
            }
            Section("Plan limits from claude.ai") {
                CaptionedToggle("Read plan limits", caption: limitsCaption,
                                isOn: Binding(get: { settings.planLimits }, set: hub.setPlanLimits))
                SettingRow("Sign out of claude.ai") {
                    Button("Sign out…", action: hub.signOut).disabled(!settings.planLimits || !model.signedIn)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var limitsCaption: String {
        if !settings.planLimits { return "Off until you turn it on. No requests go to claude.ai." }
        return model.signedIn ? "Signed in · Tidemark’s own session" : "Not signed in"
    }
}
