import AppKit
import SwiftUI
import TidemarkCore

/// The main window: Usage and the Week section, the copied picture and the weekly report.
enum WindowShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The main window", "The main window: the real window at its first size, drawn offscreen and cut at 1180 × 760 where it would scroll (window-usage, window-week-frame), and the Week section's content at 1180 points, its whole height (window-week-*), with the weekly report card and the picture Copy summary puts on the pasteboard. Then Month, Trends and Names & tags (window-month, window-trends-*, window-names-*), each pane alone in a 960 × 700 frame.")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        let s = stage.scenarios
        let demo = DemoCalendar.store()
        let lastWeek = stage.now.addingTimeInterval(-7 * 86400)

        func scene(_ state: String, _ about: String, day: Date? = nil, problems: [CalendarProblem] = [],
                   _ edit: @escaping (WeekModel) -> WeekModel = { $0 }) -> Shot {
            Shot(screen: "window", state: state, about: about, byLook: false) { dark in
                let store = FixtureCalendar(edit: edit, problems: problems)
                return Renderer.picture(WeekScene(model: stage.demo(s[0]), store: store, now: stage.now, day: day), dark: dark)
            }
        }
        func card(_ state: String, _ about: String, tab: ReportModel.Tab, phase: ReportModel.Phase = .idle) -> Shot {
            Shot(screen: "window", state: state, about: about, byLook: false) { dark in
                let settings = stage.model().settings
                let week = demo.week(containing: lastWeek, weekStart: .monday, now: stage.now)
                let model = ReportModel(week: week, settings: settings, store: demo, actions: .none, now: { stage.now }, tab: tab, phase: phase)
                return Renderer.picture(ReportScene { ReportCard(model: model) }, dark: dark)
            }
        }
        return [
            Shot(screen: "window", state: "usage", about: "The real window on Usage, two plans (cut at 1180 × 760)", byLook: false) { dark in
                Offscreen.image(of: MainWindowController.frame(model: stage.demo(s[0]), actions: .none, section: .usage), dark: dark)
            },
            Shot(screen: "window", state: "week-frame", about: "The real window on Week, this week so far (cut at 1180 × 760)", byLook: false) { dark in
                Offscreen.image(of: MainWindowController.frame(model: stage.demo(s[0]), actions: .none, section: .week,
                                                               calendar: demo, now: { stage.now }), dark: dark)
            },
            scene("week-this-week", "Week, this week so far: brief, tiles, project bar, days and the grid"),
            Shot(screen: "window", state: "week-sources-not-chosen", about: "Week before the user has chosen what Tidemark reads: the line and its button", byLook: false) { dark in
                let model = stage.demo(s[0])
                model.settings.sourcesChosen = false
                return Renderer.picture(WeekScene(model: model, store: FixtureCalendar(edit: { $0 }, problems: []), now: stage.now, day: nil), dark: dark)
            },
            scene("week-last-week", "Week, last week (12 – 18 Oct), a complete week", day: lastWeek),
            scene("week-empty", "Week with no sessions: the empty line under the tiles") { WeekModel(start: $0.start, days: $0.days) },
            scene("week-overlaps", "Week with overlapping sessions side by side, and five at once on Thursday", WindowFixtures.overlaps),
            scene("week-long-titles", "Week with very long, Japanese and emoji titles and project names", WindowFixtures.longTitles),
            Shot(screen: "window", state: "week-dst", about: "The week the clocks go back (26 Oct – 1 Nov 2026, New York): every block sits on its own hour, also on the 25-hour Sunday", byLook: false) { dark in
                WindowFixtures.inTimeZone("America/New_York") {
                    let store = FixtureCalendar(edit: WindowFixtures.dstWeek, problems: [])
                    let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28))
                    return Renderer.picture(WeekScene(model: stage.demo(s[0]), store: store, now: stage.now, day: day), dark: dark)
                }
            },
            Shot(screen: "window", state: "week-narrow", about: "Week at the window's smallest width (760 points): the buttons wrap under the range", byLook: false) { dark in
                let store = FixtureCalendar(edit: { $0 }, problems: [])
                return Renderer.picture(WeekScene(model: stage.demo(s[0]), store: store, now: stage.now, day: lastWeek, width: 760), dark: dark)
            },
            scene("week-partial", "Last week with some of Claude Code's logs already deleted", day: lastWeek) { var w = $0; w.isPartial = true; return w },
            scene("problem", "A calendar problem above the pane: title in bold, then what it means", problems: WindowFixtures.problems),
            Shot(screen: "window", state: "copy-summary", about: "The picture Copy summary puts on the pasteboard: header, brief and grid, no sidebar", byLook: false) { dark in
                let week = demo.week(containing: stage.now, weekStart: .monday, now: stage.now)
                return CopyState.image(week: week, now: stage.now, calendar: .current, dark: dark, twentyFourHour: false)
            },
            card("report-plain", "Report card, Plain: three lines from the numbers", tab: .plain),
            Shot(screen: "window", state: "report-consent", about: "The one-time question before Claude Code writes the report", byLook: false) { dark in
                Renderer.picture(ReportScene { ReportConsentSheet(onCancel: {}, onWrite: {}).clipShape(RoundedRectangle(cornerRadius: 12)) }, dark: dark)
            },
            card("report-claude", "Report card, By Claude Code: written, with Edit and Write again", tab: .claude),
            card("report-writing", "Report card while Claude Code writes: Writing with Claude Code… and Cancel", tab: .plain, phase: .writing),
            card("report-failed", "Report card after a failure: Claude Code isn't installed", tab: .plain,
                 phase: .failed(WindowCopy.reportFailure(.notInstalled))),
        ] + PaneShots.shots(stage)
    }
}

/// The Week section with its sidebar, at 1180 points and its whole height.
struct WeekScene: View {
    @StateObject private var state = MainState()
    @StateObject private var calendar: CalendarViewModel
    @StateObject private var copy = CopyState()
    @ObservedObject var model: AppModel

    let width: CGFloat

    init(model: AppModel, store: CalendarStoring, now: Date, day: Date?, width: CGFloat = 1180) {
        self.model = model
        self.width = width
        let vm = CalendarViewModel(store: store, settings: model.settings, now: { now })
        if let day { vm.shownDay = day }
        _calendar = StateObject(wrappedValue: vm)
    }

    var body: some View {
        // A fixed clock setting, so the pictures don't depend on the Mac that draws them.
        MainView(state: state, model: model, calendar: calendar, copy: copy, actions: .none, onCopy: {}, scrolls: false,
                 twentyFourHour: false)
            .onAppear { state.section = .week }
            .frame(width: width)
            .background(Palette.tile)
    }
}

/// A card or sheet on the page colour, as a sheet would sit over the window.
struct ReportScene<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.frame(width: content is ReportConsentSheet ? 440 : 560).padding(24).background(Palette.page)
    }
}

enum WindowFixtures {
    static let problems = [
        CalendarProblem(id: "unreadable", title: "Some of this week’s sessions couldn’t be read",
                        detail: "Claude Code’s logs for Monday are unreadable. Tidemark kept what it had saved."),
        CalendarProblem(id: "cowork", title: "Cowork tasks haven’t been logged",
                        detail: "Turn on logging in Settings → Week to see them here."),
    ]

    private static func item(_ id: String, day: Int, _ week: WeekModel, _ from: (Int, Int), _ to: (Int, Int), title: String,
                             project: String, color: Int, commits: Int = 3, noCommit: Bool = false) -> WeekItem {
        let cal = Calendar.current
        func at(_ t: (Int, Int)) -> Date { cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: week.days[day]) ?? week.days[day] }
        let span = DateInterval(start: at(from), end: at(to))
        return WeekItem(id: "\(id)|\(day)", sessionID: id, day: day, title: title, project: project, colorIndex: color,
                        spans: [span], seconds: span.duration, commits: commits, commitSubjects: [], noCommit: noCommit)
    }

    /// Runs `body` with `id` as the local time zone (a render of a daylight-saving week).
    @MainActor static func inTimeZone<T>(_ id: String, _ body: () -> T) -> T {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: id) ?? saved
        defer { NSTimeZone.default = saved }
        return body()
    }

    /// 26 Oct – 1 Nov 2026: a morning and an afternoon session every day, and an early one on
    /// Sunday 1 Nov, the 25-hour day.
    static func dstWeek(_: WeekModel) -> WeekModel {
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 26)) ?? Date()
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
        let week = WeekModel(start: monday, days: days)
        var extra: [WeekItem] = []
        for d in 0..<7 {
            extra.append(item("dst-a", day: d, week, (9, 0), (10, 30), title: "Morning at 9:00", project: "tide-tables", color: 0))
            extra.append(item("dst-b", day: d, week, (13, 0), (14, 0), title: "Afternoon at 1:00", project: "field-notes", color: 2))
        }
        extra.append(item("dst-c", day: 6, week, (6, 30), (8, 0), title: "Early at 6:30", project: "lighthouse-api", color: 1))
        return adding(extra, to: week)
    }

    private static func adding(_ extra: [WeekItem], to week: WeekModel) -> WeekModel {
        var w = week
        w.items = (w.items + extra).sorted { ($0.day, $0.spans[0].start) < ($1.day, $1.spans[0].start) }
        for e in extra {
            w.perDay[e.day] += e.seconds
            w.total += e.seconds
            w.sessions += 1
            w.claudeCodeSessions += 1
            w.commits += e.commits
        }
        return w
    }

    /// Two overlapping sessions on Tuesday, a chain on Wednesday, five at once on Thursday.
    static func overlaps(_ w: WeekModel) -> WeekModel {
        var extra = [
            item("ov-1", day: 1, w, (10, 0), (12, 0), title: "Spike: tide chart zoom", project: "tide-tables", color: 0),
            item("ov-2", day: 1, w, (10, 30), (12, 30), title: "Review the nav PR", project: "harbor-site", color: 4, commits: 0, noCommit: true),
            item("ov-3", day: 2, w, (12, 0), (14, 0), title: "Try the new export format", project: "tide-tables", color: 0),
            item("ov-4", day: 2, w, (12, 30), (13, 30), title: "Fix the flaky sign-in test", project: "lighthouse-api", color: 1),
            item("ov-5", day: 2, w, (13, 15), (15, 0), title: "Update the field-notes index", project: "field-notes", color: 2),
        ]
        let thursday = ["Migrate the tile cache", "Profile the map view", "Answer API questions", "Draft the 2.4 notes", "Fix a typo in the docs"]
        for (i, title) in thursday.enumerated() {
            extra.append(item("th-\(i)", day: 3, w, (9, 30 + 5 * i), (12, 0), title: title, project: ["tide-tables", "lighthouse-api", "field-notes", "harbor-site", "Daily briefs"][i],
                              color: i, commits: i == 4 ? 0 : 2, noCommit: i == 4))
        }
        return adding(extra, to: w)
    }

    /// Titles of 60+ characters, Japanese and emoji, and a project name to match.
    static func longTitles(_ w: WeekModel) -> WeekModel {
        let long = "Investigate why the offline tile cache grows without bound after a long session on a slow connection"
        var out = w
        for (i, title) in [long, "潮汐表のオフライン対応と地図タイルのキャッシュを見直す作業", "Ship it 🚀🚢 and celebrate the release with a very long note 🎉"].enumerated() {
            if let index = out.items.indices.first(where: { out.items[$0].day == i && out.items[$0].origin == .claudeCode }) {
                out.items[index].title = title
            }
        }
        let project = "harbor-site-redesign-with-a-really-long-repository-name-for-the-marketing-team"
        out.projects.append(ProjectTotal(name: project, seconds: 2 * 3600, sessions: 1, commits: 4, colorIndex: 4))
        return adding([
            item("lt-1", day: 3, out, (9, 30), (11, 30), title: "ハーバーサイトのナビゲーションを作り直す", project: project, color: 4),
            item("lt-2", day: 3, out, (13, 0), (14, 30), title: long, project: project, color: 4, commits: 0, noCommit: true),
        ], to: out)
    }
}

/// The demo calendar with the week and the problems changed, for states the demo doesn't have.
final class FixtureCalendar: CalendarStoring, @unchecked Sendable {
    private let base = DemoCalendar.store()
    private let edit: (WeekModel) -> WeekModel
    private let list: [CalendarProblem]

    init(edit: @escaping (WeekModel) -> WeekModel, problems: [CalendarProblem]) {
        self.edit = edit
        list = problems
    }

    func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel { edit(base.week(containing: day, weekStart: weekStart, now: now)) }
    func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel { base.month(containing: day, weekStart: weekStart, now: now) }
    func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        base.trends(endingWith: day, count: count, grouping: grouping, weekStart: weekStart, now: now)
    }
    func nameRows(_ kind: NameKind, now: Date) -> [NameRow] { base.nameRows(kind, now: now) }
    var names: NameBook { base.names }
    func apply(_ change: NameChange) throws -> NameBook { try base.apply(change) }
    func replaceNames(_ book: NameBook) throws { try base.replaceNames(book) }
    func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary { base.weekSummary(containing: day, weekStart: weekStart, now: now) }
    func save(_ report: WeekReport) throws { try base.save(report) }
    func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary { await base.refresh(sources, now: now) }
    func findLegacy(in folder: URL) -> LegacyFound? { base.findLegacy(in: folder) }
    func importLegacy(from folder: URL) throws -> ImportResult { try base.importLegacy(from: folder) }
    func deleteAll() throws { try base.deleteAll() }
    func lastCoworkLogEntry(in folder: URL) -> Date? { base.lastCoworkLogEntry(in: folder) }
    var problems: [CalendarProblem] { list }
}
