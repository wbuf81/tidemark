import Testing
@testable import TidemarkCore

@Suite struct WidgetMenuModelTests {
    private func tide(_ entries: [WidgetMenuModel.Entry]) -> WidgetMenuModel.Entry? {
        entries.first { $0.title == "Tide" }
    }

    private func checked(_ entry: WidgetMenuModel.Entry?) -> [String] {
        (entry?.children ?? []).filter(\.checked).compactMap(\.title)
    }

    @Test func tideCheckFollowsTheSettingBothWays() {
        for style in TideStyle.allCases {
            let entries = WidgetMenuModel.entries(signedIn: true, calendar: true, tide: style, showWeek: true)
            #expect(checked(tide(entries)) == [style.label])
        }
    }

    @Test func eachTideChoiceSetsItsStyle() {
        let entries = WidgetMenuModel.entries(signedIn: true, calendar: false, tide: .level, showWeek: true)
        let commands = tide(entries)?.children.map(\.command)
        #expect(commands == TideStyle.allCases.map { .setTide($0) })
    }

    @Test func showTheWeekIsCheckedWhileTheBandShowsAndTogglesIt() {
        for shown in [true, false] {
            let entries = WidgetMenuModel.entries(signedIn: true, calendar: true, tide: .level, showWeek: shown)
            let item = entries.first { $0.title == "Show the week" }
            #expect(item?.checked == shown)
            #expect(item?.command == .setShowWeek(!shown))
        }
    }

    @Test func weekItemsNeedAWeekAndTheNotchHasNoBandToToggle() {
        let none = WidgetMenuModel.entries(signedIn: true, calendar: false, tide: .level, showWeek: true)
        #expect(!none.contains { $0.title == "Open week calendar" || $0.title == "Show the week" })
        let notch = WidgetMenuModel.entries(signedIn: true, calendar: true, tide: .level, showWeek: true, weekBand: false)
        #expect(notch.contains { $0.title == "Open week calendar" })
        #expect(!notch.contains { $0.title == "Show the week" })
    }

    @Test func signInShowsOnlyWhileSignedOutAndTheRestAlwaysShow() {
        let out = WidgetMenuModel.entries(signedIn: false, calendar: false, tide: .level, showWeek: true).compactMap(\.title)
        let signedIn = WidgetMenuModel.entries(signedIn: true, calendar: false, tide: .level, showWeek: true).compactMap(\.title)
        #expect(out.contains("Sign in…") && !signedIn.contains("Sign in…"))
        for title in ["Refresh now", "Hide for 1 hour", "Tide", "Settings…", "Quit Tidemark"] {
            #expect(out.contains(title) && signedIn.contains(title))
        }
    }
}
