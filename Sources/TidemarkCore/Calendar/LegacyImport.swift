import Foundation

/// Why an old week calendar couldn't be imported.
public enum LegacyImportError: LocalizedError, Equatable, Sendable {
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notFound: "That folder doesn’t hold an old week calendar."
        }
    }
}

/// Reads the old Python week calendar's `data/` folder (ES §6.1): week files, names, folder names, labels and reports.
/// It only reads; the store copies the files into `legacy/` and merges what is read.
enum LegacyImport {
    /// `data/` itself, or the folder that holds it; nil when there are no week files.
    static func dataFolder(in folder: URL) -> URL? {
        for candidate in [folder.appendingPathComponent("data", isDirectory: true), folder] {
            if !weekFiles(candidate).isEmpty { return candidate }
        }
        return nil
    }

    static func weekFiles(_ data: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: data.appendingPathComponent("weeks").path)) ?? []
        return names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted().map { data.appendingPathComponent("weeks/\($0)") }
    }

    /// Every file an import keeps verbatim, relative to `data/`.
    static func sourceFiles(_ data: URL) -> [String] {
        weekFiles(data).map { "weeks/" + $0.lastPathComponent }
            + ["names.js", "projects.json", "labels.json", "reports.json"].filter { FileManager.default.fileExists(atPath: data.appendingPathComponent($0).path) }
    }

    static func weekStart(_ file: URL) -> String {
        if let object = json(file) as? [String: Any], let start = object["start"] as? String { return start }
        return file.deletingPathExtension().lastPathComponent
    }

    private static func json(_ file: URL) -> Any? {
        (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    // MARK: names.js

    /// The names table: JSON after the first `=` of the first line that isn't a `//` comment, trailing `;` removed.
    /// nil when it doesn't read.
    static func parseNames(_ text: String) -> NameBook? {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        guard let equals = code.firstIndex(of: "=") else { return nil }
        var body = code[code.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix(";") { body.removeLast(); body = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] else { return nil }
        func table(_ key: String) -> [String: NameEntry] {
            var out: [String: NameEntry] = [:]
            for (name, value) in (object[key] as? [String: Any]) ?? [:] where name != "*" {
                guard let e = value as? [String: Any] else { continue }
                var entry = NameEntry()
                if let v = e["name"] as? String, !v.isEmpty { entry.name = v }
                if let v = e["tags"] as? [String], !v.isEmpty { entry.tags = v }
                if let v = e["project"] as? String, !v.isEmpty { entry.project = v }
                if let v = e["hide_titles"] as? Bool, v { entry.hideTitles = true }
                if entry != NameEntry() { out[name] = entry }
            }
            return out
        }
        var book = NameBook()
        book.sessions = table("sessions")
        book.projects = table("projects")
        book.folders = table("folders")
        return book
    }

    // MARK: Weeks

    struct Week {
        var start: String
        var window: DateInterval
        var total: TimeInterval?
    }

    /// The sessions of every week file, one session per id with its blocks joined across week boundaries, and each week's window and total.
    static func parseWeeks(_ data: URL, firstMessages: Bool, calendar: Calendar) -> (sessions: [CalendarSession], weeks: [Week]) {
        let labels = (json(data.appendingPathComponent("labels.json")) as? [String: [String: Any]]) ?? [:]
        var order: [String] = []
        var byID: [String: CalendarSession] = [:]
        var weeks: [Week] = []
        for file in weekFiles(data) {
            guard let object = json(file) as? [String: Any] else { continue }
            let start = (object["start"] as? String) ?? file.deletingPathExtension().lastPathComponent
            let days = ((object["week"] as? [String: Any])?["days"] as? [String])?.compactMap(CalendarDates.parse) ?? []
            let startDate = days.first ?? SourceDay.date(start, calendar: calendar)
            let endDate = days.count == 8 ? days[7] : calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate
            // A commit's time is its block's end, kept inside this file's own week (a block cut at midnight ends there).
            let lastMoment = max(endDate, startDate).addingTimeInterval(-1)
            weeks.append(Week(start: start, window: DateInterval(start: startDate, end: max(endDate, startDate)), total: (object["total"] as? NSNumber)?.doubleValue))

            let list = (object["sessions"] as? [[String: Any]]) ?? []
            var made: [CalendarSession?] = list.map { s in
                guard let id = s["id"] as? String, !id.isEmpty else { return nil }
                let isCowork = (s["source"] as? String) == "Cowork"
                let rawRoot = ((s["origin"] as? String).flatMap { $0.isEmpty ? nil : $0 }) ?? (s["root"] as? String) ?? ""
                var title = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if title == nil { title = (labels[id]?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
                let first = firstMessages ? (s["first"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
                return CalendarSession(
                    id: id, origin: isCowork ? .cowork : .claudeCode, title: title, firstMessage: first,
                    root: isCowork ? "Cowork" : (rawRoot.isEmpty ? "unknown folder" : rawRoot),
                    folders: (s["folders"] as? [String]) ?? [], isGit: !isCowork && (s["git"] as? Bool) == true,
                    scheduled: (s["scheduled"] as? Bool) == true, logged: (s["logged"] as? Bool) == true, blocks: [], commits: [],
                    lastActivity: .distantPast)
            }
            for b in (object["blocks"] as? [[String: Any]]) ?? [] {
                guard let index = (b["s"] as? NSNumber)?.intValue, made.indices.contains(index), var session = made[index],
                      let from = (b["start"] as? String).flatMap(CalendarDates.parse), let to = (b["end"] as? String).flatMap(CalendarDates.parse) else { continue }
                session.blocks.append(Block(start: from, end: max(from, to)))
                for c in (b["commits"] as? [[String: Any]]) ?? [] {
                    guard let sha = c["h"] as? String, !sha.isEmpty, !session.commits.contains(where: { $0.sha == sha }) else { continue }
                    session.commits.append(Commit(sha: sha, time: min(to, max(lastMoment, from)), repo: session.root, subject: (c["subject"] as? String) ?? "",
                                                  files: (c["files"] as? [String]) ?? []))
                }
                made[index] = session
            }
            for case let session? in made {
                if var known = byID[session.id] {
                    known.blocks += session.blocks
                    for c in session.commits where !known.commits.contains(where: { $0.sha == c.sha }) { known.commits.append(c) }
                    if (known.title ?? "").isEmpty { known.title = session.title }
                    if (known.firstMessage ?? "").isEmpty { known.firstMessage = session.firstMessage }
                    byID[session.id] = known
                } else {
                    order.append(session.id)
                    byID[session.id] = session
                }
            }
        }
        let sessions: [CalendarSession] = order.compactMap { id in
            guard var s = byID[id], !s.blocks.isEmpty else { return nil }
            s.blocks = join(s.blocks)
            s.commits.sort { ($0.time, $0.sha) < ($1.time, $1.sha) }
            s.lastActivity = s.blocks.map(\.end).max() ?? .distantPast
            return s
        }
        return (sessions, weeks)
    }

    /// Blocks that touch or overlap are one (a block cut at a week's end continues in the next week's file).
    static func join(_ blocks: [Block]) -> [Block] {
        var out: [Block] = []
        for b in blocks.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = out.last, b.start <= last.end {
                out[out.count - 1].end = max(last.end, b.end)
            } else {
                out.append(b)
            }
        }
        return out
    }

    // MARK: The rest

    static func projectFolders(_ data: URL) -> [String: String] {
        ((json(data.appendingPathComponent("projects.json")) as? [String: Any]) ?? [:]).compactMapValues { $0 as? String }
    }

    /// `reports.json`: `{"<week start>": {week, done, most_time, next, days}}`; the lines are the non-empty ones in that order.
    static func reports(_ data: URL, written: Date) -> [WeekReport] {
        let object = (json(data.appendingPathComponent("reports.json")) as? [String: Any]) ?? [:]
        return object.keys.sorted().compactMap { key in
            guard let r = object[key] as? [String: Any] else { return nil }
            let lines = ["week", "done", "most_time", "next"].compactMap { (r[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let days = ((r["days"] as? [String: Any]) ?? [:]).compactMapValues { $0 as? String }
            guard !lines.isEmpty || !days.isEmpty else { return nil }
            return WeekReport(weekStart: key, lines: lines, days: days, author: .imported, written: written)
        }
    }
}

private enum SourceDay {
    /// A "yyyy-MM-dd" as local midnight.
    static func date(_ text: String, calendar: Calendar) -> Date {
        let p = text.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? .distantPast
    }
}

extension CalendarStore {
    public func findLegacy(in folder: URL) -> LegacyFound? {
        guard let data = LegacyImport.dataFolder(in: folder) else { return nil }
        let starts = LegacyImport.weekFiles(data).map(LegacyImport.weekStart).sorted()
        guard let first = starts.first, let last = starts.last else { return nil }
        let fm = FileManager.default
        return LegacyFound(weeks: starts.count, first: first, last: last,
                           hasNames: fm.fileExists(atPath: data.appendingPathComponent("names.js").path),
                           hasReports: fm.fileExists(atPath: data.appendingPathComponent("reports.json").path))
    }

    /// Brings the old calendar's weeks, names and reports in. Copies every source file into `legacy/` first (never
    /// overwriting one), never writes to the source, and lets what the store already has win. Each week's total is
    /// recomputed from the imported sessions and listed in `mismatches` when it is more than a minute off the file's.
    public func importLegacy(from folder: URL) throws -> ImportResult {
        try importLegacy(from: folder, sources: switches)
    }

    public func importLegacy(from folder: URL, sources: SourceSwitches) throws -> ImportResult {
        guard let data = LegacyImport.dataFolder(in: folder) else { throw LegacyImportError.notFound }
        // The whole import is one writer's turn: nothing else writes between its steps.
        return try serialized {
            // Nothing is copied or written while the calendar is read-only.
            if let reason = currentFiles.readOnlyReason { throw CalendarFilesError.readOnly(reason) }
            let fm = FileManager.default
            let legacy = self.folder.appendingPathComponent("legacy", isDirectory: true)
            for name in LegacyImport.sourceFiles(data) {
                let destination = legacy.appendingPathComponent(name)
                if fm.fileExists(atPath: destination.path) { continue }
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: data.appendingPathComponent(name), to: destination)
            }

            let parsed = LegacyImport.parseWeeks(data, firstMessages: sources.firstMessages, calendar: calendar)
            let existing = Set(storedSessions.map(\.id))
            let added = parsed.sessions.filter { !existing.contains($0.id) }
            if let error = absorbLocked(added, generation: nil, base: nil).error { throw error }

            // Names and reports: the user's own come first, the old ones fill in what is missing.
            var book = names
            if let old = LegacyImport.parseNames((try? String(contentsOf: data.appendingPathComponent("names.js"), encoding: .utf8)) ?? "") {
                book.sessions.merge(old.sessions) { mine, _ in mine }
                book.projects.merge(old.projects) { mine, _ in mine }
                book.folders.merge(old.folders) { mine, _ in mine }
            }
            book.projectFolders.merge(LegacyImport.projectFolders(data)) { mine, _ in mine }
            if book != names { try setNamesLocked(book) }

            let have = Set(savedReports.map(\.weekStart))
            let newReports = LegacyImport.reports(data, written: Date()).filter { !have.contains($0.weekStart) }
            if !newReports.isEmpty { try saveReportsLocked(savedReports + newReports) }

            // Each week's total is checked against what the store now holds for these sessions (where an existing session won, too).
            let ids = Set(parsed.sessions.map(\.id))
            let now = storedSessions.filter { ids.contains($0.id) }
            var mismatches: [String] = []
            for week in parsed.weeks {
                guard let total = week.total else { continue }
                let spans = Spans.clip(now.flatMap { $0.blocks.map { DateInterval(start: $0.start, end: $0.end) } }, to: week.window)
                if abs(Spans.union(spans) - total) > 60 { mismatches.append(week.start) }
            }
            return ImportResult(weeks: parsed.weeks.count, sessionsAdded: added.count, sessionsKept: parsed.sessions.count - added.count, mismatches: mismatches)
        }
    }
}
