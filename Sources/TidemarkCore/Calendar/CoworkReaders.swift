import Foundation

/// Folder names that are Cowork's own mounts, not the user's work; plus the shared `Claude` folder.
private let coworkIgnoredFolders: Set<String> = ["outputs", "uploads", "user-data", "skills", ".claude", ".skills", "Claude"]

private func coworkFolders(_ names: [String]) -> [String] {
    var seen: [String] = []
    for raw in names {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.count > 1, name.hasSuffix("/") { name.removeLast() }
        if name.isEmpty || coworkIgnoredFolders.contains(name) || seen.contains(name) { continue }
        seen.append(name)
        if seen.count == 3 { break }
    }
    return seen
}

/// Cowork tasks that logged themselves: one JSON file per entry (`<id>__<stamp>.json`), or one entry per line of
/// `tidemark-log.jsonl`. Both are read from the same folder.
enum CoworkLogReader {
    static let jsonLinesName = "tidemark-log.jsonl"
    static let longestTask: TimeInterval = 12 * 3600
    static let step: TimeInterval = 600

    private struct Turn {
        var id: String
        var start: Date
        var end: Date
        var title: String
        var ask: String
        var folders: [String]
        var scheduled: Bool
    }

    /// The older per-entry files: `<id>__<stamp>.json`. No other file in the folder is opened.
    static func isEntryFile(_ name: String) -> Bool {
        guard name.hasSuffix(".json"), let marker = name.range(of: "__") else { return false }
        return marker.lowerBound > name.startIndex
    }

    static func read(folder: URL, since: Date?, keepFirstMessage: Bool = true) -> (sessions: [RawSession], problem: CalendarProblem?, skipped: Int) {
        let fm = FileManager.default
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: folder.path).sorted() }
        catch {
            let problem = CalendarProblem(id: "cowork-log", title: "Tidemark can’t read the Cowork log folder",
                                          detail: "Choose it again in Settings → Week.")
            return ([], problem, 0)
        }
        var skipped = 0
        var turns: [Turn] = []
        func take(_ object: Any?, fileStem: String?) {
            guard let turn = turn(from: object, fileStem: fileStem) else { skipped += 1; return }
            if let since, turn.end < since { return }
            turns.append(turn)
        }
        for name in names where isEntryFile(name) {
            let stem = String(name.dropLast(5))
            let object = (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { try? JSONSerialization.jsonObject(with: $0) }
            take(object, fileStem: stem)
        }
        if names.contains(jsonLinesName), let data = try? Data(contentsOf: folder.appendingPathComponent(jsonLinesName)) {
            for line in data.split(separator: UInt8(ascii: "\n")) where !line.allSatisfy({ $0 == 32 || $0 == 13 || $0 == 9 }) {
                take(try? JSONSerialization.jsonObject(with: Data(line)), fileStem: nil)
            }
        }
        return (group(turns, keepFirstMessage: keepFirstMessage), nil, skipped)
    }

    private static let idStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()

    private static func turn(from object: Any?, fileStem: String?) -> Turn? {
        guard let e = object as? [String: Any],
              let s = e["start"] as? String, let start = CalendarDates.parse(s),
              let t = e["end"] as? String, let end = CalendarDates.parse(t),
              end >= start, end.timeIntervalSince(start) <= longestTask else { return nil }
        var id = (e["id"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if id.isEmpty, let stem = fileStem, let r = stem.range(of: "__"), r.lowerBound > stem.startIndex {
            id = String(stem[..<r.lowerBound])
        }
        if id.isEmpty { id = "cowork-" + idStamp.string(from: start) }
        return Turn(id: id, start: start, end: end,
                    title: CalendarText.collapse(e["title"] as? String ?? ""),
                    ask: CalendarText.clean(e["ask"] as? String ?? ""),
                    folders: (e["folders"] as? [Any])?.compactMap { $0 as? String } ?? [],
                    scheduled: (e["scheduled"] as? Bool) == true)
    }

    private static func group(_ turns: [Turn], keepFirstMessage: Bool) -> [RawSession] {
        var order: [String] = []
        var groups: [String: [Turn]] = [:]
        for turn in turns.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
            let key = turn.id.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(turn)
        }
        return order.map { key in
            let list = groups[key]!
            var times: [Date] = []
            for turn in list {
                var t = turn.start
                while t < turn.end { times.append(t); t = t.addingTimeInterval(step) }
                times.append(turn.end)
            }
            var raw = RawSession(id: list[0].id, origin: .cowork, times: Array(Set(times)).sorted())
            raw.title = list.reversed().first { !$0.title.isEmpty }?.title
            raw.firstMessage = keepFirstMessage ? list.first { !$0.ask.isEmpty }?.ask : nil
            raw.scheduled = list.contains { $0.scheduled }
            raw.logged = true
            raw.folders = coworkFolders(list.flatMap(\.folders))
            return raw
        }
    }
}

/// Claude Desktop's own Cowork sessions: `<a>/<b>/local_<id>.json` beside an `audit.jsonl`.
enum DesktopCoworkReader {
    static func read(root: URL, since: Date?, keepFirstMessage: Bool) -> [RawSession] {
        let fm = FileManager.default
        func dirs(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { $0.path < $1.path }
        }
        var result: [RawSession] = []
        for a in dirs(root) {
            for b in dirs(a) {
                let items = ((try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }
                for meta in items where meta.lastPathComponent.hasPrefix("local_") && meta.pathExtension == "json" {
                    let uuid = String(meta.deletingPathExtension().lastPathComponent.dropFirst(6))
                    let audit = [b.appendingPathComponent("local_\(uuid)/audit.jsonl"), b.appendingPathComponent("\(uuid.prefix(8))/audit.jsonl")]
                        .first { fm.fileExists(atPath: $0.path) }
                    guard let audit else { continue }
                    if let since, let m = (try? audit.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m < since { continue }
                    if let raw = session(meta: meta, uuid: uuid, audit: audit, keepFirstMessage: keepFirstMessage) { result.append(raw) }
                }
            }
        }
        return result
    }

    private static func session(meta: URL, uuid: String, audit: URL, keepFirstMessage: Bool) -> RawSession? {
        guard let data = try? Data(contentsOf: meta), let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let auditData = try? Data(contentsOf: audit) else { return nil }
        var raw = RawSession(id: (m["sessionId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? uuid, origin: .cowork)
        if let t = m["title"] as? String, !CalendarText.collapse(t).isEmpty { raw.title = CalendarText.collapse(t) }
        let initial = (m["initialMessage"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        raw.scheduled = initial.hasPrefix("<scheduled-task")
        if keepFirstMessage, !initial.isEmpty, !initial.hasPrefix("<") {
            let cleaned = CalendarText.clean(initial)
            if !cleaned.isEmpty { raw.firstMessage = cleaned }
        }
        raw.folders = coworkFolders(((m["userSelectedFolders"] as? [Any]) ?? []).compactMap { ($0 as? String).map { URL(fileURLWithPath: $0).lastPathComponent } })
        for line in auditData.split(separator: UInt8(ascii: "\n")) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = o["type"] as? String, type == "user" || type == "assistant" else { continue }
            let stamp = (o["timestamp"] as? String) ?? (o["_audit_timestamp"] as? String)
            guard let stamp, let time = CalendarDates.parse(stamp) else { continue }
            raw.times.append(time)
            if keepFirstMessage, raw.firstMessage == nil, type == "user", ((o["origin"] as? [String: Any])?["kind"] as? String) == "human",
               let content = (o["message"] as? [String: Any])?["content"] {
                let text: String
                if let s = content as? String { text = s }
                else if let parts = content as? [[String: Any]] { text = parts.compactMap { $0["text"] as? String }.joined(separator: " ") }
                else { text = "" }
                let cleaned = CalendarText.clean(text)
                if !cleaned.isEmpty, !cleaned.hasPrefix("<") { raw.firstMessage = cleaned }
            }
        }
        guard !raw.times.isEmpty else { return nil }
        raw.times.sort()
        return raw
    }
}

/// Merges the same Cowork task seen by both readers (ids compared lower-cased, ES §1.3).
enum CoworkMerge {
    /// The desktop session's own values win when it has them; times are joined, `scheduled` is OR-ed and
    /// `logged` is true when the log knew the task.
    static func merge(desktop: [RawSession], log: [RawSession]) -> [RawSession] {
        var result = desktop
        var index: [String: Int] = [:]
        for (i, s) in result.enumerated() { index[s.id.lowercased()] = i }
        for entry in log {
            guard let i = index[entry.id.lowercased()] else {
                index[entry.id.lowercased()] = result.count
                result.append(entry)
                continue
            }
            var s = result[i]
            s.times = Array(Set(s.times + entry.times)).sorted()
            if (s.title ?? "").isEmpty { s.title = entry.title }
            if (s.firstMessage ?? "").isEmpty { s.firstMessage = entry.firstMessage }
            if s.folders.isEmpty { s.folders = entry.folders }
            s.scheduled = s.scheduled || entry.scheduled
            s.logged = s.logged || entry.logged
            result[i] = s
        }
        return result.filter { !$0.times.isEmpty }
    }
}
