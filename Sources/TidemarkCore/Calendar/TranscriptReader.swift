import Foundation

/// A session as read from a source, before blocks, repo and commits are worked out.
struct RawSession: Equatable, Sendable {
    var id: String
    var origin: SessionOrigin
    var cwd: String?
    var times: [Date]
    var title: String?
    var firstMessage: String?
    var command: String?
    /// Commit hashes the transcript printed (git's "[main 9eba146] …" lines).
    var hashes: Set<String>
    var folders: [String]
    var scheduled: Bool
    var logged: Bool

    init(id: String, origin: SessionOrigin, cwd: String? = nil, times: [Date] = [], title: String? = nil,
         firstMessage: String? = nil, command: String? = nil, hashes: Set<String> = [], folders: [String] = [],
         scheduled: Bool = false, logged: Bool = false) {
        self.id = id
        self.origin = origin
        self.cwd = cwd
        self.times = times
        self.title = title
        self.firstMessage = firstMessage
        self.command = command
        self.hashes = hashes
        self.folders = folders
        self.scheduled = scheduled
        self.logged = logged
    }
}

/// Timestamps the way the sources write them (ES: every timestamp is read, then shown local).
enum CalendarDates {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let noZone: [DateFormatter] = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = $0
        return f
    }

    /// ISO 8601 with or without fractions; a string with no offset is read as the Mac's local time.
    static func parse(_ text: String) -> Date? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let d = plain.date(from: s) ?? fractional.date(from: s) { return d }
        for f in noZone { if let d = f.date(from: s) { return d } }
        return nil
    }
}

/// Text cleaning shared by the readers.
enum CalendarText {
    private static let pasted = try! NSRegularExpression(pattern: "</?pasted_content[^>]*>")
    private static let image = try! NSRegularExpression(pattern: "\\[Image #\\d+\\]")

    /// Drops paste and image markers, collapses whitespace, cuts to `limit` characters.
    static func clean(_ text: String, limit: Int = 600) -> String {
        var s = text
        for regex in [pasted, image] {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        return String(collapse(s).prefix(limit))
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Reads Claude Code's transcripts (`projects/<folder>/<session>.jsonl`).
enum TranscriptReader {
    private static let commitLine = try! NSRegularExpression(pattern: "^\\[[^\\]\\n]*? ([0-9a-f]{7,40})\\] ", options: .anchorsMatchLines)
    private static let commandName = try! NSRegularExpression(pattern: "<command-name>(.*?)</command-name>", options: .dotMatchesLineSeparators)
    private static let commandArgs = try! NSRegularExpression(pattern: "<command-args>(.*?)</command-args>", options: .dotMatchesLineSeparators)

    /// Top-level `*/*.jsonl` under the projects folder, oldest modification first, changed at or after `since`.
    /// Subagent transcripts live deeper and are not read.
    static func files(projectsDir: URL, since: Date?) -> [URL] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var found: [(url: URL, modified: Date)] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let inside = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])
            else { continue }
            for url in inside where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if values?.isDirectory == true { continue }
                let modified = values?.contentModificationDate ?? .distantPast
                if let since, modified < since { continue }
                found.append((url, modified))
            }
        }
        return found.sorted { ($0.modified, $0.url.path) < ($1.modified, $1.url.path) }.map(\.url)
    }

    /// One transcript as a raw session; nil when it has no timed records, or when it is one of Tidemark's
    /// own report runs (its working folder is inside `ownFolder`).
    static func read(_ file: URL, keepFirstMessage: Bool, ignoringRunsUnder ownFolder: URL? = nil) -> RawSession? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        var raw = RawSession(id: file.deletingPathExtension().lastPathComponent, origin: .claudeCode)
        var customTitle: String?
        var aiTitle: String?
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "custom-title":
                if let t = object["customTitle"] as? String, !t.isEmpty { customTitle = t }
            case "ai-title":
                if let t = object["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
            case "user", "assistant":
                guard (object["isSidechain"] as? Bool) != true,
                      let stamp = object["timestamp"] as? String, let time = CalendarDates.parse(stamp) else { continue }
                raw.times.append(time)
                if raw.cwd == nil, let cwd = object["cwd"] as? String, !cwd.isEmpty { raw.cwd = cwd }
                if type == "user" { readUser(object, into: &raw) }
            default:
                continue
            }
        }
        guard !raw.times.isEmpty else { return nil }
        if let ownFolder, let cwd = raw.cwd, isInside(cwd, ownFolder.path) { return nil }
        raw.times.sort()
        raw.title = customTitle ?? aiTitle
        if !keepFirstMessage {
            raw.firstMessage = nil
            raw.command = nil
        }
        return raw
    }

    private static func isInside(_ path: String, _ folder: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        let f = URL(fileURLWithPath: folder).standardizedFileURL.path
        return p == f || p.hasPrefix(f + "/")
    }

    private static func readUser(_ object: [String: Any], into raw: inout RawSession) {
        let message = object["message"] as? [String: Any]
        let content = message?["content"]
        let origin = object["origin"] as? [String: Any]
        let human = (origin?["kind"] as? String) == "human" && (object["isMeta"] as? Bool) != true
        if human {
            let text = textOf(content)
            if text.contains("<command-name>") {
                if raw.command == nil, let name = firstGroup(commandName, in: text) {
                    let args = firstGroup(commandArgs, in: text) ?? ""
                    raw.command = CalendarText.clean("\(name) \(args)")
                }
            } else if raw.firstMessage == nil {
                let cleaned = CalendarText.clean(text)
                if !cleaned.isEmpty { raw.firstMessage = cleaned }
            }
        } else if (origin?["kind"] as? String) != "human", let parts = content as? [[String: Any]] {
            for part in parts where (part["type"] as? String) == "tool_result" {
                let text = textOf(part["content"])
                let range = NSRange(text.startIndex..., in: text)
                for match in commitLine.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) { raw.hashes.insert(String(text[r])) }
                }
            }
        }
    }

    private static func textOf(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
        }
        return ""
    }

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
