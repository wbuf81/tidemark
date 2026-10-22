import AppKit
import SwiftUI
import TidemarkCore

/// Month, Trends and Names & tags, each drawn on its own at the size the window gives a pane.
enum PaneShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("Month, Trends, Names & tags", "Each pane alone, in a 960 × 700 frame (the window's content beside the sidebar), from the demo calendar at Wed 21 Oct 2026.")
    }

    private static let size = NSSize(width: 960, height: 700)

    /// A pane built for real in an offscreen window, so text fields and switches draw.
    @MainActor private static func draw<V: View>(_ view: V, dark: Bool) -> NSBitmapImageRep? {
        let host = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        window.setContentSize(size)
        return Offscreen.image(of: window, dark: dark, chrome: false)
    }

    @MainActor private static func settings(_ stage: RenderStage) -> Settings {
        let settings = stage.model().settings
        settings.weekStart = .monday
        return settings
    }

    @MainActor private static func trends(_ stage: RenderStage, count: Int = 8, grouping: TrendGrouping = .project, open: String? = nil) -> TrendsPaneModel {
        let model = TrendsPaneModel(store: DemoCalendar.store(), settings: settings(stage), now: { DemoCalendar.now })
        model.count = count
        model.grouping = grouping
        model.open = open
        return model
    }

    @MainActor private static func names(_ stage: RenderStage, _ kind: NameKind) -> NamesPaneModel {
        let model = NamesPaneModel(store: DemoCalendar.store(), now: { DemoCalendar.now })
        model.kind = kind
        return model
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        func shot(_ state: String, _ about: String, _ make: @escaping @MainActor () -> AnyView) -> Shot {
            Shot(screen: "window", state: state, about: about, byLook: false) { dark in draw(make(), dark: dark) }
        }
        return [
            shot("month", "Month: October 2026, today outlined") {
                let model = MonthPaneModel(store: DemoCalendar.store(), settings: settings(stage), now: { DemoCalendar.now })
                return AnyView(MonthPane(model: model, onOpenWeek: { _ in }))
            },
            shot("trends-8", "Trends over 8 weeks, one row per project") {
                AnyView(TrendsPane(model: trends(stage), onOpenWeek: { _ in }))
            },
            shot("trends-quarter", "Trends over a quarter") {
                AnyView(TrendsPane(model: trends(stage, count: 13), onOpenWeek: { _ in }))
            },
            shot("trends-by-tag", "Trends by tag") {
                AnyView(TrendsPane(model: trends(stage, grouping: .tag), onOpenWeek: { _ in }))
            },
            shot("trends-detail", "One project's chart and weeks") {
                AnyView(TrendsPane(model: trends(stage, count: 13, open: "tide-tables"), onOpenWeek: { _ in }))
            },
            shot("names-sessions", "Names & tags, Sessions") {
                AnyView(NamesPane(model: names(stage, .sessions)))
            },
            shot("names-projects", "Names & tags, Projects, with a hidden project") {
                AnyView(NamesPane(model: names(stage, .projects)))
            },
            shot("names-folders", "Names & tags, Cowork folders") {
                AnyView(NamesPane(model: names(stage, .folders)))
            },
            shot("names-rule", "Names & tags with a starts-with rule being added") {
                let model = names(stage, .sessions)
                model.addingRule = true
                model.rulePrefix = "Email Brief Daily"
                return AnyView(NamesPane(model: model))
            },
            shot("names-error", "A name that couldn’t be saved, in red under its row") {
                let model = names(stage, .sessions)
                if let row = model.rows.dropFirst().first {
                    model.showError(PanesCopy.saveError(NameBookError.unreadable("the file isn’t valid JSON")), row: row)
                }
                model.showRuleError(PanesCopy.saveError(NameBookError.unreadable("the file isn’t valid JSON")))
                return AnyView(NamesPane(model: model))
            },
        ]
    }
}
