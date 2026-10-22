import Foundation

/// Invented sample weeks for the renders, the tests and "Show demo data". All of it is made up.
///
/// Weeks always start on Monday in the demo, whatever `weekStart` a caller asks for. Every date
/// is built from components in `Calendar.current` (year 2026, local time). The store is read-only:
/// every change is ignored. The numbers are pinned by `ContractsTests`.
public enum DemoCalendar {
    /// Wed 21 Oct 2026, 11:32.
    public static let now: Date = demoDate(10, 21, 11, 32)

    public static let names: NameBook = {
        var book = NameBook()
        book.sessions["Email Brief Daily*"] = NameEntry(name: "Daily email brief", tags: ["routine"], project: "Daily briefs")
        book.sessions["Add chart export"] = NameEntry(tags: ["feature"])
        book.sessions["Login loop on SSO"] = NameEntry(name: "Fix sign-in redirect", tags: ["bug"])
        book.projects["tide-tables"] = NameEntry(tags: ["feature"])
        book.projects["lighthouse-api"] = NameEntry(tags: ["bug"])
        book.projects["field-notes"] = NameEntry(tags: ["docs"])
        book.projects["Daily briefs"] = NameEntry(tags: ["routine"])
        book.projects["harbor-site"] = NameEntry(tags: ["feature"])
        book.projects["Side projects"] = NameEntry(hideTitles: true)
        for folder in ["garden-planner", "recipe-box", "bike-log"] {
            book.projects[folder] = NameEntry(project: "Side projects")
        }
        return book
    }()

    public static func store() -> CalendarStoring { DemoStore(sessions: DemoSessions.make(), names: names) }

    /// The report writer while demo data is on: it never runs Claude Code. After a short pause it answers with the demo's
    /// three lines, filed under the week that was asked for.
    public static func reportWriter(delay: Duration = .milliseconds(1500)) -> @Sendable (WeekModel, Date) async -> Result<WeekReport, ReportFailure> {
        return { week, now in
            try? await Task.sleep(for: delay)
            let lines = demoOverlays["2026-10-12"]?.report?.lines ?? []
            let start = dayString(week.days[0])
            return .success(WeekReport(weekStart: start, lines: lines, days: [:], author: .claudeCode, written: now))
        }
    }
}

private func demoDate(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
}

// MARK: - The sessions

private enum DemoSessions {
    enum Kind { case code, cowork, scheduled }

    static let commitSubjects: [String: [String]] = [
        "Add chart export": ["Add PNG export", "Add CSV export", "Hook export into the chart menu"],
        "field-notes drafts": ["Draft the release notes", "Reword the intro", "Fix broken links"],
        "Offline mode": ["Cache tide tables on launch", "Show an offline banner", "Retry failed requests"],
        "Login loop on SSO": ["Fix redirect after SSO", "Keep the return address", "Add a sign-in test"],
        "Fix sign-in redirect": ["Fix redirect after SSO", "Keep the return address", "Add a sign-in test"],
        "Release notes": ["Write the 2.3 notes", "Update the changelog"],
        "Offline cache": ["Add a tile cache", "Drop old tiles first"],
        "Release 2.3": ["Bump the version to 2.3", "Update the changelog", "Tag the release"],
        "Token refresh": ["Refresh tokens before they expire", "Handle a revoked token"],
        "harbor-site nav": ["Add the main menu", "Fix the phone menu"],
        "Chart axes": ["Label the axes", "Fix tick spacing"],
        "Map tiles": ["Load tiles in the background", "Fix tile seams"],
        "Rate limits": ["Add a request budget", "Return a retry hint"],
        "Release 2.2": ["Bump the version to 2.2", "Update the changelog"],
    ]

    static func make() -> [CalendarSession] {
        var out: [CalendarSession] = []
        var counter = 0

        func add(_ id: String, _ title: String, _ root: String, _ kind: Kind, _ start: Date, _ end: Date, _ commits: Int) {
            let isCode = kind == .code
            let subjects = commitSubjects[title] ?? ["Update \(root)", "Fix a typo", "Tidy up the tests"]
            let span = end.timeIntervalSince(start)
            let made: [Commit] = (0..<commits).map { i in
                counter += 1
                return Commit(sha: String(format: "%07x", 0xd3a000 + counter),
                              time: start.addingTimeInterval(span * Double(i + 1) / Double(commits + 1)),
                              repo: root, subject: subjects[i % subjects.count])
            }
            out.append(CalendarSession(id: id, origin: isCode ? .claudeCode : .cowork, title: title, root: root,
                                       isGit: isCode, scheduled: kind == .scheduled, logged: !isCode,
                                       blocks: [Block(start: start, end: end)], commits: made, lastActivity: end))
        }

        func row(_ id: String, _ title: String, _ root: String, _ kind: Kind, _ month: Int, _ day: Int,
                 _ from: String, _ to: String, _ commits: Int) {
            func hm(_ s: String) -> (Int, Int) { (Int(s.prefix(2)) ?? 0, Int(s.suffix(2)) ?? 0) }
            add(id, title, root, kind, demoDate(month, day, hm(from).0, hm(from).1), demoDate(month, day, hm(to).0, hm(to).1), commits)
        }

        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func brief(_ month: Int, _ day: Int) {
            row("demo-brief-\(String(format: "%02d%02d", month, day))", "Email Brief Daily \(day) \(monthNames[month - 1])",
                "Daily briefs", .scheduled, month, day, "09:00", "09:20", 0)
        }
        func triage(_ month: Int, _ day: Int, _ from: String, _ to: String) {
            row("demo-triage-\(String(format: "%02d%02d", month, day))", "Inbox triage", "Daily briefs", .cowork, month, day, from, to, 0)
        }

        // Earlier weeks, generated: 27 Jul … 21 Sep.
        let cal = Calendar.current
        let firstMonday = demoDate(7, 27)
        let tideTitles = ["Map tiles", "Chart axes", "Offline cache", "Tide predictions"]
        for week in 0..<9 {
            for day in 0..<5 {
                guard let date = cal.date(byAdding: .day, value: week * 7 + day, to: firstMonday) else { continue }
                let c = cal.dateComponents([.month, .day], from: date)
                let (m, d) = (c.month ?? 1, c.day ?? 1)
                let tag = "\(week)-\(day)"
                brief(m, d)
                if day < 4 {
                    let hours = 2 + (week + day) % 3
                    row("demo-gen-tide-\(tag)", tideTitles[(week + day) % tideTitles.count], "tide-tables", .code, m, d,
                        "09:30", String(format: "%02d:30", 9 + hours), hours * 60 / 12)
                }
                if day == 1 || day == 3 {
                    row("demo-gen-api-\(tag)", day == 1 ? "Rate limits" : "Token refresh", "lighthouse-api", .code, m, d, "14:00", "16:00", 10)
                }
                if day == 2 && week >= 5 {
                    row("demo-gen-notes-\(tag)", "field-notes outline", "field-notes", .code, m, d, "14:00", "15:30", 7)
                }
            }
        }

        // 28 Sep and 5 Oct, by hand.
        for (m, d) in [(9, 28), (9, 29), (9, 30), (10, 1), (10, 2), (10, 5), (10, 6), (10, 7), (10, 8), (10, 9)] { brief(m, d) }
        row("demo-tiles-1001", "Map tiles", "tide-tables", .code, 10, 1, "09:30", "12:30", 15)
        row("demo-limits-1002", "Rate limits", "lighthouse-api", .code, 10, 2, "10:00", "12:30", 12)
        row("demo-axes-1005", "Chart axes", "tide-tables", .code, 10, 5, "09:30", "12:30", 15)
        row("demo-outline-1006", "field-notes outline", "field-notes", .code, 10, 6, "10:00", "12:00", 10)
        row("demo-rel22-1007", "Release 2.2", "tide-tables", .code, 10, 7, "09:30", "13:30", 20)
        row("demo-token-1008", "Token refresh", "lighthouse-api", .code, 10, 8, "10:00", "13:00", 15)
        row("demo-harbor-1009", "harbor-site", "harbor-site", .code, 10, 9, "10:00", "12:00", 10)

        // Last week, Mon 12 – Fri 16 Oct.
        row("demo-brief-1012", "Email Brief Daily 12 Oct", "Daily briefs", .scheduled, 10, 12, "09:00", "09:20", 0)
        row("demo-cache-1", "Offline cache", "tide-tables", .code, 10, 12, "09:30", "12:30", 14)
        row("demo-cache-2", "Offline cache", "tide-tables", .code, 10, 12, "13:30", "16:00", 12)
        row("demo-sso-1", "Fix sign-in redirect", "lighthouse-api", .code, 10, 12, "16:10", "16:50", 7)
        row("demo-sso-2", "Fix sign-in redirect", "lighthouse-api", .code, 10, 12, "16:50", "17:30", 7)
        row("demo-brief-1013", "Email Brief Daily 13 Oct", "Daily briefs", .scheduled, 10, 13, "09:00", "09:20", 0)
        row("demo-rel23-1", "Release 2.3", "tide-tables", .code, 10, 13, "09:30", "12:00", 15)
        row("demo-rel23-2", "Release 2.3", "tide-tables", .code, 10, 13, "12:30", "14:00", 12)
        row("demo-sso-3", "Fix sign-in redirect", "lighthouse-api", .code, 10, 13, "14:10", "15:40", 8)
        row("demo-sso-4", "Fix sign-in redirect", "lighthouse-api", .code, 10, 13, "15:40", "17:10", 7)
        triage(10, 13, "17:20", "18:10")
        row("demo-notes-1013", "field-notes drafts", "field-notes", .code, 10, 13, "18:20", "19:15", 10)
        row("demo-brief-1014", "Email Brief Daily 14 Oct", "Daily briefs", .scheduled, 10, 14, "09:00", "09:20", 0)
        row("demo-notes-1014a", "field-notes drafts", "field-notes", .code, 10, 14, "09:30", "12:30", 14)
        row("demo-notes-1014b", "field-notes drafts", "field-notes", .code, 10, 14, "13:30", "14:36", 10)
        row("demo-token-1014", "Token refresh", "lighthouse-api", .code, 10, 14, "14:45", "17:19", 16)
        row("demo-harbor-1014", "harbor-site nav", "harbor-site", .code, 10, 14, "17:30", "18:00", 8)
        row("demo-brief-1015", "Email Brief Daily 15 Oct", "Daily briefs", .scheduled, 10, 15, "09:00", "09:20", 0)
        triage(10, 15, "09:30", "11:04")
        row("demo-harbor-1015", "harbor-site nav", "harbor-site", .code, 10, 15, "11:15", "13:11", 18)
        row("demo-axes-1015", "Chart axes", "tide-tables", .code, 10, 15, "14:00", "15:10", 12)
        row("demo-brief-1016", "Email Brief Daily 16 Oct", "Daily briefs", .scheduled, 10, 16, "09:00", "09:20", 0)
        row("demo-harbor-1016", "harbor-site nav", "harbor-site", .code, 10, 16, "09:30", "10:30", 9)
        row("demo-axes-1016", "Chart axes", "tide-tables", .code, 10, 16, "10:40", "11:55", 7)

        // This week, Mon 19 – Wed 21 Oct.
        row("demo-brief-1019", "Email Brief Daily 19 Oct", "Daily briefs", .scheduled, 10, 19, "09:00", "09:20", 0)
        row("demo-chart-1", "Add chart export", "tide-tables", .code, 10, 19, "09:30", "12:30", 20)
        row("demo-chart-2", "Add chart export", "tide-tables", .code, 10, 19, "13:30", "16:20", 18)
        row("demo-notes-1", "field-notes drafts", "field-notes", .code, 10, 19, "16:30", "17:30", 14)
        row("demo-brief-1020", "Email Brief Daily 20 Oct", "Daily briefs", .scheduled, 10, 20, "09:00", "09:20", 0)
        row("demo-offline-1", "Offline mode", "tide-tables", .code, 10, 20, "09:30", "10:10", 12)
        row("demo-offline-2", "Offline mode", "tide-tables", .code, 10, 20, "10:10", "10:58", 13)
        row("demo-signin-1", "Login loop on SSO", "lighthouse-api", .code, 10, 20, "11:10", "13:00", 10)
        row("demo-signin-2", "Login loop on SSO", "lighthouse-api", .code, 10, 20, "13:00", "15:48", 12)
        row("demo-notes-2", "field-notes drafts", "field-notes", .code, 10, 20, "16:00", "16:50", 7)
        row("demo-notes-3", "field-notes drafts", "field-notes", .code, 10, 20, "16:52", "17:44", 7)
        triage(10, 20, "17:50", "18:47")
        row("demo-brief-1021", "Email Brief Daily 21 Oct", "Daily briefs", .scheduled, 10, 21, "08:00", "08:20", 0)
        row("demo-release-1", "Release notes", "tide-tables", .code, 10, 21, "08:30", "10:00", 6)
        row("demo-release-2", "Release notes", "tide-tables", .code, 10, 21, "10:00", "11:15", 8)
        return out
    }
}

// MARK: - The hand-written parts of the two main weeks

private struct DemoOverlay {
    var brief: String
    var dayNotes: [String]
    var plainReport: [String]
    var report: WeekReport?
}

private let demoOverlays: [String: DemoOverlay] = [
    "2026-10-19": DemoOverlay(
        brief: "Shipped chart export and offline mode for tide-tables, fixed sign-in redirects in lighthouse-api, and started the 2.3 release notes.",
        dayNotes: ["Chart export for tide-tables, with PNG and CSV.", "Offline mode; fixed lighthouse-api sign-in redirects.",
                   "Release notes for tide-tables 2.3.", "", "", "", ""],
        plainReport: ["19h 20m of work across 15 sessions (11 Claude Code, 4 Cowork) and 127 commits in 3 repos.",
                      "Most time on tide-tables (52%), then lighthouse-api (24%) and field-notes (14%).",
                      "Busiest day Tuesday 20 Oct (9h 05m)."],
        report: nil),
    "2026-10-12": {
        let lines = ["Shipped tide-tables 2.3 with chart export and offline mode, the bulk of the week at about 12 hours.",
                     "Fixed the sign-in redirect loop in lighthouse-api and drafted the field-notes release.",
                     "Started harbor-site’s navigation; daily email briefs ran every weekday."]
        let days = ["2026-10-12": "Offline cache for tide-tables; the SSO loop in lighthouse-api.",
                    "2026-10-13": "Released tide-tables 2.3.",
                    "2026-10-14": "field-notes drafts; lighthouse-api token refresh.",
                    "2026-10-15": "harbor-site navigation.",
                    "2026-10-16": "Chart axes for tide-tables."]
        return DemoOverlay(
            brief: lines[0],
            dayNotes: ["Offline cache for tide-tables; the SSO loop in lighthouse-api.", "Released tide-tables 2.3.",
                       "field-notes drafts; lighthouse-api token refresh.", "harbor-site navigation.",
                       "Chart axes for tide-tables.", "", ""],
            plainReport: ["31h 20m of work across 24 sessions (17 Claude Code, 7 Cowork) and 186 commits in 4 repos.",
                          "Most time on tide-tables (38%), then lighthouse-api (22%) and field-notes (16%).",
                          "Busiest day Tuesday 13 Oct (9h 05m); Daily briefs ran all five weekdays."],
            report: WeekReport(weekStart: "2026-10-12", lines: lines, days: days, author: .claudeCode, written: demoDate(10, 19, 9, 2)))
    }(),
]

// MARK: - The store

private final class DemoStore: CalendarStoring, @unchecked Sendable {
    private let sessions: [CalendarSession]
    private let book: NameBook

    init(sessions: [CalendarSession], names: NameBook) {
        self.sessions = sessions
        self.book = names
    }

    private var cal: Calendar { .current }

    private func monday(of date: Date) -> Date {
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start)
        return cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: start) ?? start
    }

    private func addDays(_ n: Int, to date: Date) -> Date { cal.date(byAdding: .day, value: n, to: date) ?? date }

    // MARK: Resolving names

    private struct Resolved {
        var session: CalendarSession
        var raw: String
        var project: String
        var title: String
        var tags: [String]
        var hidden: Bool
    }

    private lazy var resolved: [Resolved] = sessions.map(resolve)

    private func entry(forRaw raw: String) -> NameEntry {
        var e = NameEntry()
        func merge(_ other: NameEntry) {
            if let v = other.name { e.name = v }
            if let v = other.tags { e.tags = v }
            if let v = other.project { e.project = v }
            if let v = other.hideTitles { e.hideTitles = v }
        }
        for (key, value) in book.sessions where key.hasSuffix("*") && raw.hasPrefix(String(key.dropLast())) { merge(value) }
        if let own = book.sessions[raw] { merge(own) }
        return e
    }

    private func resolve(_ s: CalendarSession) -> Resolved {
        let raw = s.title ?? s.root
        let e = entry(forRaw: raw)
        let base = e.project ?? s.root
        let project = book.projects[base]?.project ?? base
        let hidden = book.projects[project]?.hideTitles == true
        return Resolved(session: s, raw: raw, project: project, title: hidden ? project : (e.name ?? raw),
                        tags: e.tags ?? book.projects[project]?.tags ?? [], hidden: hidden)
    }

    // MARK: Spans

    private func union(_ spans: [DateInterval]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: DateInterval?
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let c = current, span.start <= c.end {
                current = DateInterval(start: c.start, end: max(c.end, span.end))
            } else {
                if let c = current { total += c.duration }
                current = span
            }
        }
        return total + (current?.duration ?? 0)
    }

    private func clip(_ blocks: [Block], to range: DateInterval) -> [DateInterval] {
        blocks.compactMap { $0.interval.intersection(with: range) }.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
    }

    // MARK: Week

    private struct Piece {
        var r: Resolved
        var day: Int
        var spans: [DateInterval]
        var commits: [Commit]
    }

    private func pieces(days: [Date]) -> [Piece] {
        var out: [Piece] = []
        for r in resolved {
            for d in 0..<7 {
                let range = DateInterval(start: days[d], end: days[d + 1])
                let spans = clip(r.session.blocks, to: range)
                guard !spans.isEmpty else { continue }
                let commits = r.session.commits.filter { $0.time >= days[d] && $0.time < days[d + 1] }
                out.append(Piece(r: r, day: d, spans: spans, commits: commits))
            }
        }
        return out.sorted { ($0.day, $0.spans[0].start) < ($1.day, $1.spans[0].start) }
    }

    private func week(start: Date, now: Date) -> WeekModel {
        let days = (0...7).map { addDays($0, to: start) }
        let all = pieces(days: days)
        func seconds(_ ps: [Piece]) -> TimeInterval { union(ps.flatMap(\.spans)) }
        func ids(_ ps: [Piece]) -> Int { Set(ps.map(\.r.session.id)).count }

        var projectNames: [String] = []
        for p in all where !projectNames.contains(p.r.project) { projectNames.append(p.r.project) }
        let ranked = projectNames
            .map { name -> (String, TimeInterval) in (name, seconds(all.filter { $0.r.project == name })) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var colour: [String: Int] = [:]
        for (i, row) in ranked.enumerated() { colour[row.0] = min(i, 6) }
        let projects = ranked.map { name, secs -> ProjectTotal in
            let ps = all.filter { $0.r.project == name }
            return ProjectTotal(name: name, seconds: secs, sessions: ids(ps), commits: ps.reduce(0) { $0 + $1.commits.count },
                                colorIndex: colour[name] ?? 6)
        }

        var tagNames: [String] = []
        for p in all { for t in p.r.tags where !tagNames.contains(t) { tagNames.append(t) } }
        let tags = tagNames.map { t -> TagTotal in
            let ps = all.filter { $0.r.tags.contains(t) }
            return TagTotal(tag: t, seconds: seconds(ps), sessions: ids(ps), commits: ps.reduce(0) { $0 + $1.commits.count })
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.tag < $1.tag }

        let items = all.map { p -> WeekItem in
            let s = p.r.session
            return WeekItem(id: "\(s.id)|\(dayString(days[p.day]))", sessionID: s.id, day: p.day, title: p.r.title, project: p.r.project,
                            colorIndex: colour[p.r.project] ?? 6, spans: p.spans, seconds: union(p.spans), commits: p.commits.count,
                            commitSubjects: p.commits.map(\.subject), origin: s.origin, scheduled: s.scheduled,
                            noCommit: s.isGit && p.commits.isEmpty, titlesHidden: p.r.hidden)
        }

        let code = all.filter { $0.r.session.origin == .claudeCode }
        let cowork = all.filter { $0.r.session.origin == .cowork }
        var running: [String] = []
        for p in projects {
            let live = all.contains {
                $0.r.project == p.name && $0.r.session.lastActivity <= now && $0.r.session.lastActivity >= now.addingTimeInterval(-1800)
            }
            if live { running.append(p.name) }
        }

        var model = WeekModel(
            start: start, days: days, total: seconds(all), claudeCodeSeconds: seconds(code), coworkSeconds: seconds(cowork),
            sessions: ids(all), claudeCodeSessions: ids(code), coworkSessions: ids(cowork),
            commits: all.reduce(0) { $0 + $1.commits.count }, repos: Set(all.flatMap { $0.commits.map(\.repo) }).count,
            perDay: (0..<7).map { d in seconds(all.filter { $0.day == d }) },
            commitsPerDay: (0..<7).map { d in all.filter { $0.day == d }.reduce(0) { $0 + $1.commits.count } },
            projects: projects, tags: tags, items: items, running: running)
        if let overlay = demoOverlays[dayString(start)] {
            model.brief = overlay.brief
            model.dayNotes = overlay.dayNotes
            model.plainReport = overlay.plainReport
            model.report = overlay.report
        }
        return model
    }

    func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel {
        week(start: monday(of: day), now: now)
    }

    // MARK: Month

    func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel {
        let first = cal.dateInterval(of: .month, for: day)?.start ?? cal.startOfDay(for: day)
        let next = cal.dateInterval(of: .month, for: day)?.end ?? addDays(30, to: first)
        let gridStart = monday(of: first)

        // Colours rank the month's projects by time.
        var perProject: [String: [DateInterval]] = [:]
        for r in resolved { perProject[r.project, default: []] += clip(r.session.blocks, to: DateInterval(start: first, end: next)) }
        var ranking: [(String, TimeInterval)] = []
        for (name, spans) in perProject {
            let secs = union(spans)
            if secs > 0 { ranking.append((name, secs)) }
        }
        ranking.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.0 < b.0 }
        var colour: [String: Int] = [:]
        for (i, row) in ranking.enumerated() { colour[row.0] = min(i, 6) }

        var weeks: [[MonthDay]] = []
        var weekFirst = gridStart
        repeat {
            weeks.append((0..<7).map { offset in
                let date = addDays(offset, to: weekFirst)
                let range = DateInterval(start: date, end: addDays(1, to: date))
                var spans: [DateInterval] = []
                var titles: [(title: String, project: String, seconds: TimeInterval, first: Date)] = []
                for r in resolved.sorted(by: { ($0.session.blocks.first?.start ?? .distantPast) < ($1.session.blocks.first?.start ?? .distantPast) }) {
                    let s = clip(r.session.blocks, to: range)
                    guard let start = s.first?.start else { continue }
                    spans += s
                    if let i = titles.firstIndex(where: { $0.title == r.title }) {
                        titles[i].seconds += union(s)
                    } else {
                        titles.append((r.title, r.project, union(s), start))
                    }
                }
                let top = titles.enumerated().sorted { $0.element.seconds != $1.element.seconds ? $0.element.seconds > $1.element.seconds : $0.offset < $1.offset }
                    .prefix(2).map { MonthItem(title: $0.element.title, colorIndex: colour[$0.element.project] ?? 6) }
                return MonthDay(date: date, inMonth: date >= first && date < next, isToday: cal.isDate(date, inSameDayAs: now),
                                seconds: union(spans), top: Array(top))
            })
            weekFirst = addDays(7, to: weekFirst)
        } while weekFirst < next
        return MonthModel(month: first, weeks: weeks)
    }

    // MARK: Trends

    func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        let last = monday(of: day)
        let starts = (0..<max(count, 0)).reversed().map { addDays(-7 * $0, to: last) }
        let models = starts.map { week(start: $0, now: now) }
        var names: [String] = []
        func values(_ m: WeekModel) -> [(String, TimeInterval)] {
            grouping == .project ? m.projects.map { ($0.name, $0.seconds) } : m.tags.map { ($0.tag, $0.seconds) }
        }
        for m in models { for (n, _) in values(m) where !names.contains(n) { names.append(n) } }
        let rows = names.map { n -> TrendRow in
            let secs = models.map { m in values(m).first { $0.0 == n }?.1 ?? 0 }
            return TrendRow(name: n, seconds: secs, total: secs.reduce(0, +))
        }.sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        let partial = starts.last.map { $0 <= now && now < addDays(7, to: $0) } ?? false
        return TrendModel(weeks: starts, rows: rows, lastIsPartial: partial)
    }

    // MARK: Names

    func nameRows(_ kind: NameKind, now: Date) -> [NameRow] {
        func total(where match: (Resolved) -> Bool) -> TimeInterval {
            union(resolved.filter(match).flatMap { $0.session.blocks.map(\.interval) })
        }
        func row(_ key: String, _ entry: NameEntry, rule: String? = nil, seconds: TimeInterval, project: String) -> NameRow {
            NameRow(id: "\(kind.rawValue)|\(key)", kind: kind, key: key, entry: entry, ruleKey: rule, seconds: seconds, currentProject: project)
        }
        switch kind {
        case .sessions:
            // The hours on the first three rows are hand-written, as the mockups show them.
            return [
                row("Email Brief Daily 19 Oct", entry(forRaw: "Email Brief Daily 19 Oct"), rule: "Email Brief Daily*", seconds: 26 * 3600, project: "Daily briefs"),
                row("Add chart export", entry(forRaw: "Add chart export"), seconds: 11 * 3600, project: "tide-tables"),
                row("Login loop on SSO", entry(forRaw: "Login loop on SSO"), seconds: 4 * 3600, project: "lighthouse-api"),
                row("Offline mode", entry(forRaw: "Offline mode"), seconds: total { $0.raw == "Offline mode" }, project: "tide-tables"),
                row("Release notes", entry(forRaw: "Release notes"), seconds: total { $0.raw == "Release notes" }, project: "tide-tables"),
            ]
        case .projects:
            let five = ["tide-tables", "lighthouse-api", "field-notes", "Daily briefs", "harbor-site"]
            return five.map { name in row(name, book.projects[name] ?? NameEntry(), seconds: total { r in r.project == name }, project: name) }
                + [row("Side projects", book.projects["Side projects"] ?? NameEntry(), seconds: 6 * 3600, project: "Side projects")]
        case .folders:
            return [
                row("tide-tables", NameEntry(), seconds: total { $0.project == "tide-tables" }, project: "tide-tables"),
                row("Claude", NameEntry(), seconds: total { $0.session.origin == .cowork }, project: "Daily briefs"),
            ]
        }
    }

    var names: NameBook { book }
    @discardableResult func apply(_ change: NameChange) throws -> NameBook { book }
    func replaceNames(_ book: NameBook) throws {}

    // MARK: Week summary

    func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary {
        let start = monday(of: day)
        let w = week(start: start, now: now)
        let previous = addDays(-7, to: start)
        let hasEarlier = sessions.contains { ($0.blocks.first?.start ?? .distantFuture) < start }
        let earlier = (1...12).reversed().map { addDays(-7 * $0, to: start) }.filter { $0 >= demoDate(7, 27) }
            .map { WeekSummary.Total(start: dayString($0), seconds: week(start: $0, now: now).total) }
        let summary = WeekSummary.Week(
            start: dayString(start), end: dayString(w.days[6]), seconds: w.total, sessions: w.sessions, commits: w.commits,
            days: (0..<7).map { WeekSummary.Day(date: dayString(w.days[$0]), seconds: w.perDay[$0], commits: w.commitsPerDay[$0]) },
            projects: w.projects.prefix(6).map { WeekSummary.Project(name: $0.name, seconds: $0.seconds) },
            previousSeconds: hasEarlier ? week(start: previous, now: now).total : nil)
        return WeekSummary(format: AppIdentity.weekSummaryFormat, generated: now, week: summary, weeks: earlier, problems: [], links: nil)
    }

    // MARK: Read-only

    func save(_ report: WeekReport) throws {}
    func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary { RefreshSummary() }
    func findLegacy(in folder: URL) -> LegacyFound? {
        LegacyFound(weeks: 39, first: "2026-01-26", last: "2026-10-19", hasNames: true, hasReports: true)
    }
    func importLegacy(from folder: URL) throws -> ImportResult { ImportResult(weeks: 0, sessionsAdded: 0, sessionsKept: 0, mismatches: []) }
    func deleteAll() throws {}
    func lastCoworkLogEntry(in folder: URL) -> Date? { demoDate(10, 20, 18, 47) }
    var problems: [CalendarProblem] { [] }
}
