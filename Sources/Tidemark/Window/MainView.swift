import SwiftUI
import TidemarkCore

/// What the main window shows right now.
@MainActor
final class MainState: ObservableObject {
    @Published var section = MainSection.usage
    @Published var plan: String?
    @Published var sidebarShown = true
    @Published var showReport = false
}

/// The sidebar and one pane. Drawn with plain stacks (not a split view) so the renders show the
/// real thing; `scrolls` is false only for renders that want the whole height.
struct MainView: View {
    @ObservedObject var state: MainState
    @ObservedObject var model: AppModel
    @ObservedObject var calendar: CalendarViewModel
    @ObservedObject var copy: CopyState
    let actions: AppActions
    var onCopy: () -> Void
    var scrolls = true
    var twentyFourHour = Formatting.prefers24Hour()

    var body: some View {
        HStack(spacing: 0) {
            if state.sidebarShown {
                Sidebar(model: model, section: $state.section, plan: $state.plan)
            }
            VStack(spacing: 0) {
                if state.section != .usage, !calendar.problems.isEmpty {
                    ProblemBanner(problems: calendar.problems)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }
                pane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(state.section == .usage ? Color.clear : Palette.tile)
        }
        .onChange(of: state.section) { _, _ in calendar.reloadAll() }
        .sheet(isPresented: $state.showReport) {
            ReportCard(model: reportModel(), onClose: { state.showReport = false })
                .frame(width: 560)
        }
    }

    private func reportModel() -> ReportModel {
        let report = ReportModel(week: calendar.reportWeek(), settings: calendar.settings, store: calendar.store, actions: actions, now: calendar.now)
        report.onSaved = { calendar.reload() }
        return report
    }

    @ViewBuilder private var pane: some View {
        switch state.section {
        case .usage:
            UsagePane(model: model, actions: actions, selectedPlan: $state.plan)
        case .week:
            WeekGate(settings: calendar.settings, calendar: calendar, copy: copy, onReport: { state.showReport = true }, onCopy: onCopy,
                     onChooseSources: actions.chooseSources, scrolls: scrolls, twentyFourHour: twentyFourHour)
        case .month:
            MonthPane(model: calendar.monthPane, onOpenWeek: openWeek)
        case .trends:
            TrendsPane(model: calendar.trendsPane, onOpenWeek: openWeek)
        case .names:
            NamesPane(model: calendar.namesPane)
        }
    }

    private func openWeek(_ day: Date) {
        calendar.shownDay = day
        state.section = .week
    }
}
