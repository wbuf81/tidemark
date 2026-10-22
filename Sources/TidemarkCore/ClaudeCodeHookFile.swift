import Foundation

public enum HookFileError: Error, Equatable {
    /// Claude Code's settings file isn't plain JSON (comments, trailing commas…): we leave it alone.
    case unreadable(String)
}

/// Connects and disconnects Tidemark's hooks in `~/.claude/settings.json`. Before the first
/// change it keeps a backup, and remembers exactly what it wrote: disconnecting before anyone
/// else changed the file puts the original bytes back.
public struct ClaudeCodeHookFile: Sendable {
    var settings: URL
    var support: URL

    public static let defaultSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    public static let defaultSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/\(AppIdentity.supportFolderName)")

    public init(settings: URL = defaultSettings, support: URL = defaultSupport) {
        self.settings = settings
        self.support = support
    }

    /// The real file: a symlinked settings.json is followed, so writes keep the link.
    private var target: URL { settings.resolvingSymlinksInPath() }
    private var backup: URL { support.appendingPathComponent("settings-before-connect.json") }
    private var written: URL { support.appendingPathComponent("settings-after-connect.json") }
    /// Present when settings.json didn't exist before we connected, so disconnecting deletes it again.
    private var wasMissing: URL { support.appendingPathComponent("settings-was-missing") }

    public func isConnected() -> Bool {
        guard let data = try? read(), let parsed = try? parse(data) else { return false }
        return ClaudeCodeHooks.isInstalled(parsed)
    }

    /// The settings bytes, or nil when there is no file. Any other failure (permissions…)
    /// throws: an unreadable file is not a missing one, and must never be written over.
    private func read() throws -> Data? {
        do {
            return try Data(contentsOf: target)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw HookFileError.unreadable("\(settings.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) can't be read, so Tidemark left it alone.")
        }
    }

    public func connect() throws {
        let before = try read()
        let parsed = try parse(before)
        guard !ClaudeCodeHooks.isInstalled(parsed) else { return }
        // The user's file keeps every byte that isn't one of our groups; only a missing or blank
        // file is written from scratch.
        let after: Data
        if let before, !isBlank(before) {
            after = try HooksText.edit(before, adding: true, unreadable: cantChange)
        } else {
            after = try encode(ClaudeCodeHooks.install(into: parsed))
        }
        let fm = FileManager.default
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try (before ?? Data()).write(to: backup, options: .atomic)
        try after.write(to: written, options: .atomic)
        if before == nil { try Data().write(to: wasMissing, options: .atomic) } else { try? fm.removeItem(at: wasMissing) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try after.write(to: target, options: .atomic)
    }

    public func disconnect() throws {
        let fm = FileManager.default
        let current = try read()
        if let current, let mine = try? Data(contentsOf: written), mine == current {
            if fm.fileExists(atPath: wasMissing.path) {
                try fm.removeItem(at: target)
            } else if let original = try? Data(contentsOf: backup) {
                try original.write(to: target, options: .atomic)
            } else {
                try removeOurs(from: current)
            }
        } else {
            let parsed = try parse(current)
            if ClaudeCodeHooks.isInstalled(parsed), let current {
                try removeOurs(from: current)
            }
        }
        for url in [written, backup, wasMissing] { try? fm.removeItem(at: url) }
    }

    private var cantChange: String { "\(settings.lastPathComponent) can't be changed safely, so Tidemark left it alone." }

    private func isBlank(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Takes our groups out of the settings text, leaving everything else as it was.
    private func removeOurs(from current: Data) throws {
        guard !isBlank(current) else { return }
        try HooksText.edit(current, adding: false, unreadable: cantChange).write(to: target, options: .atomic)
    }

    /// Whether the file's hooks are absent, today's, or ours but older. An unreadable file is not connected.
    func currentState() -> HookState {
        guard let data = try? read(), let parsed = try? parse(data) else { return .notConnected }
        return ClaudeCodeHooks.state(parsed)
    }

    /// Swaps every hook group of ours (old markers too) for today's eight, in one write, keeping
    /// everything else in the file exactly as it was. The file as it was is kept first in
    /// `settings-before-update-<stamp>.json`. A file that can't be read is never touched.
    func performUpdate(now: Date = Date()) throws {
        let before = try read()
        let parsed = try parse(before)
        switch ClaudeCodeHooks.state(parsed) {
        case .connected: return
        case .notConnected: try connect(); return
        case .outdated: break
        }
        guard let before else { return }
        let after = try HooksText.edit(before, adding: true, unreadable: cantChange)
        let fm = FileManager.default
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try before.write(to: backupURL(now: now), options: .atomic)
        try after.write(to: target, options: .atomic)
    }

    private func backupURL(now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        var url = support.appendingPathComponent("settings-before-update-\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = support.appendingPathComponent("settings-before-update-\(stamp)-\(n).json")
            n += 1
        }
        return url
    }

    /// The settings as a dictionary; a missing or empty file is an empty one.
    private func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
            throw HookFileError.unreadable("\(settings.lastPathComponent) isn't plain JSON, so Tidemark left it alone.")
        }
        return dictionary
    }

    private func encode(_ dictionary: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

/// Edits the settings text itself, not a parsed copy, so every part that isn't one of our hook
/// groups stays byte for byte as it was: key order, spacing, other apps' hooks.
enum HooksText {
    private typealias Bytes = [UInt8]
    private struct Member { var keyRaw: String; var key: String; var keyStart: Int; var value: Range<Int> }
    private struct Event { var keyRaw: String; var key: String; var groups: [String]; var opaque: String?; var removed = 0 }

    /// `data` with our groups replaced by today's (`adding`), or just taken out. Throws
    /// `HookFileError.unreadable` when the text isn't shaped as expected.
    static func edit(_ data: Data, adding: Bool, unreadable message: String) throws -> Data {
        let bad = HookFileError.unreadable(message)
        let b = Bytes(data)
        let i = skipSpace(b, 0)
        guard i < b.count, b[i] == UInt8(ascii: "{") else { throw bad }
        let topRange = i..<skipValue(b, i)
        let top = try members(b, topRange)
        let hooksMember = top.first { $0.key == "hooks" }
        if !adding && hooksMember == nil { return data }

        // The base indent: that of the line the "hooks" key (or the last key) sits on.
        let reference = hooksMember?.keyStart ?? top.last?.keyStart
        let base = reference.flatMap { lineIndent(b, before: $0) } ?? "  "
        let unit = base.isEmpty ? "  " : base

        let ind2 = base + unit, ind3 = base + unit + unit
        var events: [Event] = []
        if let hooksMember {
            guard b[hooksMember.value.lowerBound] == UInt8(ascii: "{") else { throw bad }
            for m in try members(b, hooksMember.value) {
                if b[m.value.lowerBound] == UInt8(ascii: "[") {
                    var event = Event(keyRaw: m.keyRaw, key: m.key, groups: [])
                    for range in try elements(b, m.value) {
                        let raw = string(b, range)
                        let group = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
                        if let group, ClaudeCodeHooks.isOurs(group) { event.removed += 1 } else { event.groups.append(raw) }
                    }
                    events.append(event)
                } else {
                    events.append(Event(keyRaw: m.keyRaw, key: m.key, groups: [], opaque: string(b, m.value)))
                }
            }
        }
        for entry in ClaudeCodeHooks.events where adding {
            // Later lines of a new group are indented to match; kept groups stay exactly as found.
            let new = pretty(ClaudeCodeHooks.group(for: entry)).split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated().map { $0.offset == 0 ? String($0.element) : "\(ind3)\($0.element)" }.joined(separator: "\n")
            if let n = events.firstIndex(where: { $0.key == entry.event }) {
                guard events[n].opaque == nil else { throw bad }
                events[n].groups.append(new)
            } else {
                events.append(Event(keyRaw: quoted(entry.event), key: entry.event, groups: [new]))
            }
        }
        let body = events.compactMap { event -> String? in
            if let opaque = event.opaque { return "\(ind2)\(event.keyRaw): \(opaque)" }
            if event.groups.isEmpty { return event.removed > 0 ? nil : "\(ind2)\(event.keyRaw): []" }
            let groups = event.groups
            return "\(ind2)\(event.keyRaw): [\n\(ind3)\(groups.joined(separator: ",\n\(ind3)"))\n\(ind2)]"
        }.joined(separator: ",\n")
        let object = body.isEmpty ? "{}" : "{\n\(body)\n\(base)}"

        var out = Bytes()
        if let hooksMember {
            out = Bytes(b[..<hooksMember.value.lowerBound]) + Bytes(object.utf8) + Bytes(b[hooksMember.value.upperBound...])
        } else if let last = top.last {
            out = Bytes(b[..<last.value.upperBound]) + Bytes(",\n\(base)\"hooks\": \(object)".utf8) + Bytes(b[last.value.upperBound...])
        } else {
            out = Bytes(b[..<topRange.lowerBound]) + Bytes("{\n\(base)\"hooks\": \(object)\n}".utf8) + Bytes(b[topRange.upperBound...])
        }
        let result = Data(out)
        // Never hand back something that doesn't parse as exactly today's hooks (or as free of ours).
        guard let parsed = (try? JSONSerialization.jsonObject(with: result)) as? [String: Any],
              adding ? ClaudeCodeHooks.state(parsed) == .connected : !ClaudeCodeHooks.isInstalled(parsed) else { throw bad }
        return result
    }

    // MARK: Scanning (the text has already parsed as JSON, so this only finds where things are)

    private static func skipSpace(_ b: Bytes, _ start: Int) -> Int {
        var i = start
        while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 }
        return i
    }

    /// The index just past the value starting at `start`.
    private static func skipValue(_ b: Bytes, _ start: Int) -> Int {
        var i = start
        switch b[i] {
        case UInt8(ascii: "\""):
            i += 1
            while i < b.count, b[i] != UInt8(ascii: "\"") { i += b[i] == UInt8(ascii: "\\") ? 2 : 1 }
            return min(i + 1, b.count)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while i < b.count {
                switch b[i] {
                case UInt8(ascii: "\""): i = skipValue(b, i); continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return i
        default:
            while i < b.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x0A, 0x0D, 0x09].contains(b[i]) { i += 1 }
            return i
        }
    }

    private static func members(_ b: Bytes, _ range: Range<Int>) throws -> [Member] {
        var result: [Member] = []
        var i = range.lowerBound + 1
        while true {
            i = skipSpace(b, i)
            guard i < range.upperBound, b[i] != UInt8(ascii: "}") else { return result }
            guard b[i] == UInt8(ascii: "\"") else { throw HookFileError.unreadable("not an object") }
            let keyEnd = skipValue(b, i)
            let keyRaw = string(b, i..<keyEnd)
            let key = (try? JSONSerialization.jsonObject(with: Data(keyRaw.utf8), options: .fragmentsAllowed)) as? String ?? keyRaw
            let colon = skipSpace(b, keyEnd)
            let valueStart = skipSpace(b, colon + 1)
            let valueEnd = skipValue(b, valueStart)
            result.append(Member(keyRaw: keyRaw, key: key, keyStart: i, value: valueStart..<valueEnd))
            i = skipSpace(b, valueEnd)
            if i < b.count, b[i] == UInt8(ascii: ",") { i += 1 }
        }
    }

    private static func elements(_ b: Bytes, _ range: Range<Int>) throws -> [Range<Int>] {
        var result: [Range<Int>] = []
        var i = range.lowerBound + 1
        while true {
            i = skipSpace(b, i)
            guard i < range.upperBound, b[i] != UInt8(ascii: "]") else { return result }
            let end = skipValue(b, i)
            result.append(i..<end)
            i = skipSpace(b, end)
            if i < b.count, b[i] == UInt8(ascii: ",") { i += 1 }
        }
    }

    /// The whitespace from the start of the line to `index`, when only whitespace precedes it there.
    private static func lineIndent(_ b: Bytes, before index: Int) -> String? {
        var i = index
        while i > 0, b[i - 1] == 0x20 || b[i - 1] == 0x09 { i -= 1 }
        guard i > 0, b[i - 1] == 0x0A else { return nil }
        return string(b, i..<index)
    }

    private static func string(_ b: Bytes, _ range: Range<Int>) -> String { String(decoding: b[range], as: UTF8.self) }

    private static func quoted(_ text: String) -> String {
        (try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\(text)\""
    }

    private static func pretty(_ group: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: group, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
