import SwiftUI
import TidemarkCore

/// Notifications: the three things Tidemark can tell you about, each its own switch.
struct NotificationsTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
        model = hub.model
    }

    private var oneShownPlan: Bool { settings.planLimits && settings.knownOrgs.filter { settings.isShown($0) }.count < 2 }

    var body: some View {
        Form {
            switch hub.notifications {
            case .notAsked:
                Section {
                    SettingRow("macOS hasn’t been asked yet", caption: "Tidemark asks first, then macOS does.") {
                        Button("Allow notifications…", action: hub.askNotifications)
                    }
                }
            case .denied:
                Section {
                    SettingRow("Notifications are off for Tidemark", caption: "Allow them in System Settings → Notifications.") {
                        Button("Open System Settings…", action: hub.openNotificationSettings)
                    }
                }
            case .allowed, .unavailable:
                EmptyView()
            }
            Section("Tell me") {
                CaptionedToggle("When Claude Code should move to another plan",
                                caption: oneShownPlan ? ShellCopy.switchNeedsTwoPlans : nil, isOn: $settings.notifySwitch)
                    .disabled(oneShownPlan)
                Toggle("When Claude Code’s plan runs low", isOn: $settings.notifyRed)
                Toggle("If claude.ai signs you out", isOn: $settings.notifySignedOut)
            }
        }
        .formStyle(.grouped)
    }
}
