import Foundation

/// The widget's and the notch's right-click menu as plain data: what it lists, which check marks are on and
/// what each choice asks for. The app builds the menu from this each time it is drawn, from the settings and the
/// model as they are then, so no mark can outlive the choice behind it.
public enum WidgetMenuModel {
    /// What a menu item asks the app to do.
    public enum Command: Equatable, Sendable {
        case refresh, hideForAnHour, openWeekCalendar, openSettings, signIn, quit
        case setTide(TideStyle)
        case setShowWeek(Bool)
    }

    /// One entry: an item, a divider when `title` is nil, or a submenu when it has `children`.
    public struct Entry: Equatable, Sendable {
        public var title: String?
        public var command: Command?
        public var checked = false
        public var children: [Entry] = []

        public static let divider = Entry(title: nil)
    }

    /// The entries in order. Open week calendar and Show the week need a week to open (`calendar`); Show the week
    /// is left out where there is no band to show (`weekBand` false, the notch). Sign in… shows only while signed out.
    /// `tide` is the current style and `showWeek` whether the band shows; each gets its check mark.
    public static func entries(signedIn: Bool, calendar: Bool, tide: TideStyle, showWeek: Bool, weekBand: Bool = true) -> [Entry] {
        var items = [Entry(title: "Refresh now", command: .refresh), Entry(title: "Hide for 1 hour", command: .hideForAnHour)]
        if calendar { items.append(Entry(title: "Open week calendar", command: .openWeekCalendar)) }
        items.append(Entry(title: "Tide", children: TideStyle.allCases.map { style in
            Entry(title: style.label, command: .setTide(style), checked: style == tide)
        }))
        if calendar && weekBand {
            items.append(Entry(title: "Show the week", command: .setShowWeek(!showWeek), checked: showWeek))
        }
        items += [.divider, Entry(title: "Settings…", command: .openSettings)]
        if !signedIn { items.append(Entry(title: "Sign in…", command: .signIn)) }
        items += [.divider, Entry(title: "Quit Tidemark", command: .quit)]
        return items
    }
}
