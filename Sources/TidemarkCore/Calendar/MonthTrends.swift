import Foundation

extension WeekComputer {
    // MARK: Month

    func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel {
        let first = calendar.dateInterval(of: .month, for: day)?.start ?? calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .month, value: 1, to: first) ?? first
        let gridStart = WeekDays.midnights(containing: first, weekStart: weekStart, calendar: calendar)[0]
        var rows = 0
        while let rowStart = calendar.date(byAdding: .day, value: 7 * rows, to: gridStart), rowStart < next { rows += 1 }
        let boundaries = (0...(rows * 7)).map { calendar.date(byAdding: .day, value: $0, to: gridStart) ?? gridStart }
        let all = pieces(days: boundaries)

        // Colours rank the month's projects by their time in the month.
        let inMonth = all.filter { boundaries[$0.day] >= first && boundaries[$0.day] < next }
        let colour = core(inMonth, from: first, to: next).colour

        var weeks: [[MonthDay]] = []
        for r in 0..<rows {
            weeks.append((0..<7).map { c in
                let index = r * 7 + c
                let date = boundaries[index]
                let ps = all.filter { $0.day == index }
                let titles = Self.longest(ps.map { (entries[$0.entry].title, Spans.union($0.spans)) }, limit: 2)
                let top = titles.map { title -> MonthItem in
                    let project = ps.first { entries[$0.entry].title == title }.map { entries[$0.entry].project } ?? ""
                    return MonthItem(title: title, colorIndex: colour[project] ?? 6)
                }
                return MonthDay(date: date, inMonth: date >= first && date < next, isToday: calendar.isDate(date, inSameDayAs: now),
                                seconds: union(ps), top: top)
            })
        }
        return MonthModel(month: first, weeks: weeks)
    }

    private func union(_ pieces: [Piece]) -> TimeInterval { Spans.union(pieces.flatMap(\.spans)) }

    // MARK: Trends

    func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        let last = WeekDays.midnights(containing: day, weekStart: weekStart, calendar: calendar)[0]
        let starts = (0..<max(count, 0)).reversed().map { calendar.date(byAdding: .day, value: -7 * $0, to: last) ?? last }
        var rows: [String: [TimeInterval]] = [:]
        for (i, start) in starts.enumerated() {
            let days = WeekDays.midnights(containing: start, weekStart: weekStart, calendar: calendar)
            let c = core(pieces(days: days), from: days[0], to: days[7])
            let parts: [(String, TimeInterval)] = grouping == .project ? c.projects.map { ($0.name, $0.seconds) } : c.tags.map { ($0.tag, $0.seconds) }
            for (name, seconds) in parts {
                rows[name, default: Array(repeating: 0, count: starts.count)][i] = seconds
            }
        }
        let list = rows.map { TrendRow(name: $0.key, seconds: $0.value, total: $0.value.reduce(0, +)) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        let lastDays = WeekDays.midnights(containing: last, weekStart: weekStart, calendar: calendar)
        return TrendModel(weeks: starts, rows: list, lastIsPartial: now >= lastDays[0] && now < lastDays[7])
    }

    // MARK: Names & tags

    /// Every session title, project and Cowork folder with time in the last 26 weeks (the keys the user names things by),
    /// with the hours it has and the `…*` rule that covers it. Keys are the real names, so they can be edited.
    func nameRows(_ kind: NameKind, now: Date) -> [NameRow] {
        let since = calendar.date(byAdding: .day, value: -26 * 7, to: calendar.startOfDay(for: now)) ?? now
        let window = DateInterval(start: since, end: .distantFuture)
        var order: [String] = []
        var spans: [String: [DateInterval]] = [:]
        var best: [String: (seconds: TimeInterval, project: String)] = [:]
        for e in entries {
            let clipped = Spans.clip(e.spans, to: window)
            if clipped.isEmpty { continue }
            let keys: [String]
            switch kind {
            case .sessions: keys = namesUnreadable ? [] : [e.label]
            case .projects:
                // The project it came from, and the one it sits in now when the user moved it.
                let origin = names.projectName(root: e.session.root)
                keys = e.calendarProject == origin ? [origin] : [origin, e.calendarProject]
            case .folders: keys = e.session.folders
            }
            for key in keys {
                if spans[key] == nil { order.append(key) }
                spans[key, default: []] += clipped
                let own = Spans.union(clipped)
                if best[key] == nil || own > best[key]!.seconds { best[key] = (own, e.project) }
            }
        }
        let table: [String: NameEntry]
        switch kind {
        case .sessions: table = names.sessions
        case .projects: table = names.projects
        case .folders: table = names.folders
        }
        return order.map { key in
            NameRow(id: key, kind: kind, key: key, entry: names.entry(kind, key), ruleKey: Self.ruleKey(table, for: key),
                    seconds: Spans.union(spans[key] ?? []), currentProject: best[key]?.project ?? "")
        }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.key < $1.key }
    }

    /// The longest `…*` rule that covers `key` (not the key itself), the way `NameBook.entry` picks it.
    static func ruleKey(_ table: [String: NameEntry], for key: String) -> String? {
        table.keys.filter { $0 != key && $0.hasSuffix("*") && $0 != "*" && key.hasPrefix($0.dropLast()) }
            .sorted { ($0.count, $1) > ($1.count, $0) }.first
    }

    // MARK: Week in brief

    func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary {
        let model = week(containing: day, weekStart: weekStart, now: now)
        let days = model.days
        func rounded(_ s: TimeInterval) -> Double { s.rounded(.toNearestOrEven) }
        let earliest = entries.map(\.first).min()
        let before = days[0]
        let previous: Double? = earliest.map { $0 < before } == true
            ? rounded(week(containing: calendar.date(byAdding: .day, value: -7, to: days[0]) ?? days[0], weekStart: weekStart, now: now).total)
            : nil
        let summaryDays = (0..<7).map {
            WeekSummary.Day(date: dayString(days[$0], calendar: calendar), seconds: rounded(model.perDay[$0]), commits: model.commitsPerDay[$0])
        }
        let week = WeekSummary.Week(
            start: dayString(days[0], calendar: calendar), end: dayString(days[6], calendar: calendar), seconds: rounded(model.total),
            sessions: model.sessions, commits: model.commits, days: summaryDays,
            projects: model.projects.prefix(6).map { WeekSummary.Project(name: $0.name, seconds: rounded($0.seconds)) },
            previousSeconds: previous)
        var totals: [WeekSummary.Total] = []
        if let earliest {
            for back in (0..<8).reversed() {
                let d = calendar.date(byAdding: .day, value: -7 * back, to: days[0]) ?? days[0]
                let m = WeekDays.midnights(containing: d, weekStart: weekStart, calendar: calendar)
                if m[7] <= earliest { continue }
                let c = core(pieces(days: m), from: m[0], to: m[7])
                totals.append(WeekSummary.Total(start: dayString(m[0], calendar: calendar), seconds: rounded(c.total)))
            }
        }
        return WeekSummary(format: AppIdentity.weekSummaryFormat, generated: now, week: week, weeks: totals,
                           problems: problems.map { WeekSummary.Problem(title: $0.title, detail: $0.detail) }, links: nil)
    }
}
