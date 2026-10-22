import AppKit
import SwiftUI

/// The tabs of the Settings window.
enum SettingsTab: String, CaseIterable {
    case general, widget, plans, week, notifications, advanced

    var title: String {
        switch self {
        case .general: "General"
        case .widget: "Widget"
        case .plans: "Plans"
        case .week: "Week"
        case .notifications: "Notifications"
        case .advanced: "Advanced"
        }
    }

    /// The SF Symbol in the toolbar.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .widget: "rectangle.bottomhalf.inset.filled"
        case .plans: "gauge.with.dots.needle.33percent"
        case .week: "calendar"
        case .notifications: "bell"
        case .advanced: "slider.horizontal.3"
        }
    }

    /// The tab's content.
    @MainActor func content(_ hub: SettingsHub) -> AnyView {
        switch self {
        case .general: AnyView(GeneralTab(hub: hub))
        case .widget: AnyView(WidgetTab(hub: hub))
        case .plans: AnyView(PlansTab(hub: hub))
        case .week: AnyView(WeekTab(hub: hub))
        case .notifications: AnyView(NotificationsTab(hub: hub))
        case .advanced: AnyView(AdvancedTab(hub: hub))
        }
    }
}
