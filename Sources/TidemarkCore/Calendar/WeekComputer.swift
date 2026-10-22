import Foundation

/// Works out weeks, months and trends from the stored sessions, the names and the saved reports. Pure: it reads nothing
/// from disk and is rebuilt only when what it was given changes.
struct WeekComputer {
    let names: NameBook
    let reports: [WeekReport]
    let calendar: Calendar
    let retentionDays: Int
    let problems: [CalendarProblem]
    let entries: [Entry]
    let commitsByRepo: [String: [Commit]]
    /// names.json couldn't be read: every title and commit subject is hidden and saved report text is left out.
    let namesUnreadable: Bool
    static let namesUnreadableID = "names-unreadable"

    /// A session after the user's moves, with everything that is shown about it worked out once.
    struct Entry {
        var session: CalendarSession
        var project: String           // shown project name
        var calendarProject: String   // the calendar's name for the project it sits in now
        var title: String             // shown title: renamed, masked when hidden or naming a secret
        var label: String             // the key the user names it by
        var tags: [String]
        var hidden: Bool
        var spans: [DateInterval]
        var commitSubjectsAllowed: Bool
        var first: Date
        var last: Date
    }

    /// One session on one day.
    struct Piece {
        var entry: Int
        var day: Int
        var spans: [DateInterval]
        var commits: [Commit]
    }

    init(sessions: [CalendarSession], names: NameBook, reports: [WeekReport], calendar: Calendar, retentionDays: Int, problems: [CalendarProblem],
         namesUnreadable: Bool = false) {
        let calendar = CalendarKeys.gregorian(calendar)
        self.namesUnreadable = namesUnreadable
        self.names = names
        self.reports = reports
        self.calendar = calendar
        self.retentionDays = retentionDays
        self.problems = problems
        let secrets = !names.secretNames().isEmpty
        var made: [Entry] = []
        for a in NameBook.assignProjects(sessions, names: names) {
            let s = a.session
            let spans = s.blocks.map { DateInterval(start: $0.start, end: max($0.end, $0.start)) }
            guard let first = spans.map(\.start).min(), let last = spans.map(\.end).max() else { continue }
            let shown = names.shown(.projects, a.project)
            // A moved project hides its titles when either end asks for it; unreadable names hide everything.
            let hidden = namesUnreadable || names.hidesTitles(project: a.project) || names.hidesTitles(project: names.projectName(root: s.root))
            let label = names.label(s)
            let named = names.entry(.sessions, label).name.flatMap { $0.isEmpty ? nil : $0 } ?? label
            let title = hidden || (secrets && names.mentionsSecret(named)) ? shown : named
            made.append(Entry(session: s, project: shown, calendarProject: a.project, title: title, label: label,
                              tags: names.tags(s, project: a.project), hidden: hidden, spans: spans,
                              commitSubjectsAllowed: !hidden, first: first, last: last))
        }
        entries = made
        var byRepo: [String: [Commit]] = [:]
        for e in made { for c in e.session.commits { byRepo[c.repo, default: []].append(c) } }
        commitsByRepo = byRepo
    }

    // MARK: Pieces and rollups

    /// Each session's time on each day between consecutive `days` (midnights), blocks clipped to the day.
    /// A block across midnight is on both days; a zero-length block is on the day it falls in.
    func pieces(days: [Date]) -> [Piece] {
        guard days.count >= 2 else { return [] }
        let window = DateInterval(start: days[0], end: days[days.count - 1])
        var out: [Piece] = []
        for (i, e) in entries.enumerated() where e.last >= window.start && e.first < window.end {
            for d in 0..<(days.count - 1) {
                let spans = Spans.clip(e.spans, to: DateInterval(start: days[d], end: days[d + 1]))
                if spans.isEmpty { continue }
                let commits = e.session.commits.filter { $0.time >= days[d] && $0.time < days[d + 1] }
                out.append(Piece(entry: i, day: d, spans: spans, commits: commits))
            }
        }
        return out
    }

    struct Core {
        var projects: [ProjectTotal]
        var tags: [TagTotal]
        var colour: [String: Int]
        var total: TimeInterval
    }

    private func union(_ pieces: [Piece]) -> TimeInterval { Spans.union(pieces.flatMap(\.spans)) }

    private func sessionCount(_ pieces: [Piece]) -> Int { Set(pieces.map(\.entry)).count }

    /// Commits of these pieces' sessions made inside the window, each counted once.
    private func commits(of pieceList: [Piece], from: Date, to: Date) -> [Commit] {
        var seen = Set<Int>()
        var out: [Commit] = []
        for p in pieceList where seen.insert(p.entry).inserted {
            out += entries[p.entry].session.commits.filter { $0.time >= from && $0.time < to }
        }
        return out
    }

    func core(_ pieces: [Piece], from: Date, to: Date) -> Core {
        var byProject: [String: [Piece]] = [:]
        var order: [String] = []
        for p in pieces {
            let name = entries[p.entry].project
            if byProject[name] == nil { order.append(name) }
            byProject[name, default: []].append(p)
        }
        let ranked = order.map { (name: $0, seconds: union(byProject[$0]!)) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
        var colour: [String: Int] = [:]
        for (rank, row) in ranked.enumerated() { colour[row.name] = min(rank, 6) }
        let projects = ranked.map { row -> ProjectTotal in
            let ps = byProject[row.name]!
            return ProjectTotal(name: row.name, seconds: row.seconds, sessions: sessionCount(ps),
                                commits: commits(of: ps, from: from, to: to).count, colorIndex: colour[row.name] ?? 6)
        }
        var byTag: [String: [Piece]] = [:]
        for p in pieces { for t in entries[p.entry].tags { byTag[t, default: []].append(p) } }
        let tags = byTag.map { tag, ps in
            TagTotal(tag: tag, seconds: union(ps), sessions: sessionCount(ps), commits: commits(of: ps, from: from, to: to).count)
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.tag < $1.tag }
        return Core(projects: projects, tags: tags, colour: colour, total: union(pieces))
    }

    // MARK: Week

    func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel {
        let days = WeekDays.midnights(containing: day, weekStart: weekStart, calendar: calendar)
        let start = days[0], end = days[7]
        let all = pieces(days: days)
        let core = core(all, from: start, to: end)
        let code = all.filter { entries[$0.entry].session.origin == .claudeCode }
        let cowork = all.filter { entries[$0.entry].session.origin == .cowork }

        var items: [WeekItem] = []
        for p in all {
            let e = entries[p.entry]
            let subjects = e.commitSubjectsAllowed ? p.commits.map(\.subject).filter { !names.mentionsSecret($0) } : []
            items.append(WeekItem(
                id: "\(e.session.id)|\(dayString(days[p.day], calendar: calendar))", sessionID: e.session.id, day: p.day,
                title: e.title, project: e.project, colorIndex: core.colour[e.project] ?? 6, spans: p.spans,
                seconds: Spans.union(p.spans), commits: p.commits.count, commitSubjects: subjects, origin: e.session.origin,
                scheduled: e.session.scheduled, noCommit: noCommit(e, weekStart: start, weekEnd: end, now: now), titlesHidden: e.hidden))
        }
        items.sort { a, b in
            if a.day != b.day { return a.day < b.day }
            let x = a.spans.first?.start ?? .distantPast, y = b.spans.first?.start ?? .distantPast
            return x != y ? x < y : a.id < b.id
        }

        let weekCommits = commits(of: all, from: start, to: end)
        let perDay = (0..<7).map { d in union(all.filter { $0.day == d }) }
        let commitsPerDay = (0..<7).map { d in weekCommits.filter { $0.time >= days[d] && $0.time < days[d + 1] }.count }

        var running: [String] = []
        for p in core.projects {
            let live = all.contains {
                let e = entries[$0.entry]
                let age = now.timeIntervalSince(e.session.lastActivity)
                return e.project == p.name && age >= 0 && age < CommitMatcher.running
            }
            if live { running.append(p.name) }
        }

        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        let saved = reports.first { $0.weekStart == dayString(start, calendar: calendar) }
        let report = saved.map(safeText)
        var model = WeekModel(
            start: start, days: days, total: core.total, claudeCodeSeconds: union(code), coworkSeconds: union(cowork),
            sessions: sessionCount(all), claudeCodeSessions: sessionCount(code), coworkSessions: sessionCount(cowork),
            commits: weekCommits.count, repos: Set(weekCommits.map(\.repo)).count, perDay: perDay, commitsPerDay: commitsPerDay,
            projects: core.projects, tags: core.tags, items: items, report: report, running: running,
            isPartial: start < cutoff, problems: problems)
        model.dayNotes = (0..<7).map { dayNote($0, days: days, items: items, report: report) }
        model.plainReport = PlainReport.lines(model, calendar: calendar)
        // Saved lines that name a secret project are replaced by the plain line in their place.
        if var shown = report {
            var lines: [String] = []
            for (i, line) in (saved?.lines ?? []).enumerated() {
                if isSafe(line) {
                    lines.append(line)
                } else if i < model.plainReport.count, !model.plainReport[i].isEmpty {
                    lines.append(model.plainReport[i])
                }
            }
            shown.lines = lines
            model.report = shown
        }
        let lede = model.report?.lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        model.brief = lede ?? model.plainReport.first ?? ""
        return model
    }

    /// Saved report text may be shown and sent on only when it names no secret project, and only when the names could be read.
    private func isSafe(_ text: String) -> Bool { !namesUnreadable && !names.mentionsSecret(text) }

    /// The report with its unsafe day texts removed (the day's generated note stands in); the caller fixes the lines,
    /// because only it knows the plain ones.
    private func safeText(_ report: WeekReport) -> WeekReport {
        var out = report
        out.days = report.days.filter { isSafe($0.value) }
        return out
    }

    /// The saved note for the day, else the day's two longest titles.
    private func dayNote(_ d: Int, days: [Date], items: [WeekItem], report: WeekReport?) -> String {
        if let saved = report?.days[dayString(days[d], calendar: calendar)]?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty, isSafe(saved) {
            return saved
        }
        let titles = Self.longest(items.filter { $0.day == d }.map { ($0.title, $0.seconds) }, limit: 2)
        return titles.isEmpty ? "" : titles.joined(separator: "; ") + "."
    }

    /// Titles by total time, longest first, the same title counted once; ties keep their order of appearance.
    static func longest(_ list: [(String, TimeInterval)], limit: Int) -> [String] {
        var order: [String] = []
        var seconds: [String: TimeInterval] = [:]
        for (title, s) in list {
            if seconds[title] == nil { order.append(title) }
            seconds[title, default: 0] += s
        }
        let ranked = order.enumerated().sorted { a, b in
            let x = seconds[a.element] ?? 0, y = seconds[b.element] ?? 0
            return x != y ? x > y : a.offset < b.offset
        }
        return ranked.prefix(limit).map(\.element)
    }

    /// A finished git session with no commit in this week and none just before it (ES §4), judged from what is stored.
    private func noCommit(_ e: Entry, weekStart: Date, weekEnd: Date, now: Date) -> Bool {
        let s = e.session
        guard s.origin == .claudeCode, s.isGit else { return false }
        var inWeek = s
        inWeek.commits = s.commits.filter { $0.time >= weekStart && $0.time < weekEnd }
        let first = s.blocks.map(\.start).min() ?? weekStart
        let before = (commitsByRepo[s.root] ?? []).contains { c in
            c.time >= first && c.time < weekStart
                && s.blocks.contains { $0.start < weekStart && c.time >= $0.start && c.time <= $0.end.addingTimeInterval(CommitMatcher.grace) }
        }
        return CommitMatcher.noCommit(inWeek, weekEnd: weekEnd, now: now, committedBefore: before)
    }
}
