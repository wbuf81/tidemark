import SwiftUI
import TidemarkCore

/// Plans: which plans to show, the one the desktop app shares, and the thresholds behind the colours.
struct PlansTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
        model = hub.model
    }

    private var shown: [Org] { settings.knownOrgs.filter { settings.isShown($0) } }

    var body: some View {
        Form {
            if !settings.planLimits {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan limits are off")
                        Caption("Turn them on in General to choose which plans to show.")
                    }
                }
            }
            if settings.planLimits {
                Section("Show these plans") {
                    ForEach(settings.knownOrgs) { org in
                        Toggle(org.name, isOn: Binding(get: { settings.isShown(org) }, set: { show(org, $0) }))
                    }
                    if settings.knownOrgs.isEmpty { Caption("Plans appear here once Tidemark has read claude.ai.") }
                    if shown.count > 1 {
                        Picker("Shared with the desktop app", selection: Binding(
                            get: { settings.primaryOrg ?? "" },
                            set: { settings.primaryOrg = $0; refreshOrgs() })) {
                            ForEach(shown) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            Section("In the usage window") {
                Toggle("Show model limits", isOn: $settings.showModelRows)
                Toggle("Show 5-hour windows", isOn: $settings.showSessionRows)
            }
            Section {
                DisclosureGroup("Show thresholds", isExpanded: Binding(get: { hub.thresholdsOpen }, set: { hub.thresholdsOpen = $0 })) {
                    threshold("Red when week left is under", \.redWeekLeft)
                    threshold("Red when the 5-hour window reaches", \.redSession)
                    threshold("Amber when the 5-hour window reaches", \.yellowSession)
                    threshold("On pace when less than this would go unused", \.onPaceUnused)
                    if shown.count > 1 {
                        threshold("Suggest plans with at least this much week left", \.eligibleWeekLeft)
                        threshold("…and a 5-hour window used under", \.eligibleSessionBelow)
                        threshold("Desktop app buffer (week left)", \.primaryReserveWeekLeft)
                    } else {
                        Caption(ShellCopy.switchNeedsTwoPlans)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func show(_ org: Org, _ on: Bool) {
        settings.orgChoices[org.id] = on
        refreshOrgs()
        if on { hub.refresh() }
    }

    private func refreshOrgs() {
        model.setAvailableOrgs(settings.knownOrgs, claudeCodeOrg: model.claudeCodeOrg)
    }

    private func threshold(_ label: String, _ key: WritableKeyPath<Thresholds, Double>) -> some View {
        Stepper(value: Binding(get: { settings.thresholds[keyPath: key] },
                               set: { settings.thresholds[keyPath: key] = $0 }), in: 0...100, step: 1) {
            HStack {
                Text(label)
                Spacer()
                SettingValue("\(Int(settings.thresholds[keyPath: key]))%")
            }
        }
    }
}
