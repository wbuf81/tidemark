/// The parts of the main window, in the order of its sidebar.
enum MainSection: String, CaseIterable {
    case usage, week, month, trends, names

    var title: String {
        switch self {
        case .usage: "Usage"
        case .week: "Week"
        case .month: "Month"
        case .trends: "Trends"
        case .names: "Names & tags"
        }
    }

    /// The SF Symbol beside the title in the sidebar.
    var symbol: String {
        switch self {
        case .usage: "chart.xyaxis.line"
        case .week: "calendar.day.timeline.left"
        case .month: "calendar"
        case .trends: "chart.bar.xaxis"
        case .names: "tag"
        }
    }
}
