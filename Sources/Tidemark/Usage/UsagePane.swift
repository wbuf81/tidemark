import AppKit
import Combine
import SwiftUI
import TidemarkCore

/// The plan and limit chosen in the pane. Held in an object rather than `@State`, which the macOS 27
/// SDK makes a macro the Command Line Tools can't expand.
@MainActor
final class UsageSelection: ObservableObject {
    /// A plan's id; nil shows no detail.
    @Published var org: String?
    @Published var kind: LimitKind = .week
    /// The Week panel shows the week before this one.
    @Published var lastWeek = false

    var id: LimitID? { org.map { LimitID(org: $0, kind: kind) } }
}

/// The Usage section of the main window, on the sky. `selectedPlan` is a plan's id; it follows the card
/// chosen here and selects that plan when set from outside (nil shows the most urgent plan).
struct UsagePane: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    @Binding var selectedPlan: String?
    @StateObject private var chosen = UsageSelection()

    init(model: AppModel, actions: AppActions, selectedPlan: Binding<String?>) {
        self.model = model
        self.actions = actions
        _selectedPlan = selectedPlan
    }

    var body: some View {
        ScrollView {
            UsageContent(model: model, actions: actions, chosen: chosen)
                .padding(24)
        }
        .background { TideSky(.page).ignoresSafeArea() }
        .onAppear { adopt(selectedPlan) }
        .onChange(of: selectedPlan) { _, plan in adopt(plan) }
        .onReceive(chosen.$org) { org in
            if selectedPlan != org { selectedPlan = org }
        }
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
    }

    /// Opens `plan`'s detail, unless it is open already; nil closes it.
    private func adopt(_ plan: String?) {
        guard chosen.org != plan else { return }
        chosen.org = plan
        chosen.kind = .week
        chosen.lastWeek = false
    }

    /// ↑ ↓ move between plans.
    private func step(_ delta: Int) {
        let ids = model.orgs.map(\.id)
        guard !ids.isEmpty else { return }
        let shown = UsageContent.shownOrg(model, chosen: chosen.org)?.id
        let current = shown.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        let next = min(max(current + delta, 0), ids.count - 1)
        if chosen.org != ids[next] { chosen.kind = .week; chosen.lastWeek = false }
        chosen.org = ids[next]
    }
}
