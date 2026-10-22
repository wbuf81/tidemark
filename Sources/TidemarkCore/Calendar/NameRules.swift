import Foundation

// How names, tags and projects are looked up and applied (ES §5.2).

/// A session after the user's moves: its project root and the shown-by-the-calendar project name.
/// `session.root` is untouched, so a reassignment can always be undone.
public struct AssignedSession: Equatable, Sendable {
    public var session: CalendarSession
    /// Where the session sits now: its own root, a project's root, or `project:<name>` for a new project.
    public var root: String
    /// The calendar's name for that root (before `shown(.projects, …)`).
    public var project: String
}

extension NameBook {
    private func table(_ kind: NameKind) -> [String: NameEntry] {
        switch kind {
        case .sessions: sessions
        case .projects: projects
        case .folders: folders
        }
    }

    /// The matching `*` rule (the longest one wins; a tie goes to the first by name) with the key's own entry on top, field by field.
    public func entry(_ kind: NameKind, _ key: String) -> NameEntry {
        let t = table(kind)
        var result = NameEntry()
        if !key.isEmpty {
            let rules = t.keys.filter { $0.hasSuffix("*") && $0 != "*" && key.hasPrefix($0.dropLast()) }
                .sorted { ($0.count, $1) > ($1.count, $0) }
            if let rule = rules.first, let e = t[rule] { result = e }
        }
        if let own = t[key] {
            if let v = own.name, !v.isEmpty { result.name = v }
            if let v = own.tags, !v.isEmpty { result.tags = v }
            if let v = own.project, !v.isEmpty { result.project = v }
            if let v = own.hideTitles { result.hideTitles = v }
        }
        return result
    }

    /// What the user calls it, else its own name.
    public func shown(_ kind: NameKind, _ key: String) -> String {
        if let n = entry(kind, key).name, !n.isEmpty { return n }
        return key
    }

    /// The session's title, else the first five words of its first message (or command) and "…", else "Untitled session".
    public func label(_ s: CalendarSession) -> String {
        if let t = s.title, !t.isEmpty { return t }
        let text = [s.firstMessage, s.command].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let text {
            let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(5)
            return words.joined(separator: " ") + "…"
        }
        return "Untitled session"
    }

    /// The calendar's name for a project root: `project:<n>` is `n`; a folder goes through `projectFolders`.
    public func projectName(root: String) -> String {
        if root.hasPrefix("project:") { return String(root.dropFirst("project:".count)) }
        var trimmed = root
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        let base = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return projectFolders[base] ?? base
    }

    /// The session's tags, then its project's, without repeats. `project` is the name after the user's moves.
    public func tags(_ s: CalendarSession, project: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in (entry(.sessions, label(s)).tags ?? []) + (entry(.projects, project).tags ?? []) where seen.insert(t).inserted {
            out.append(t)
        }
        return out
    }

    /// Where the user moved this session, if they did: its own name first, then a folder (never the shared `Claude` one), then its project.
    public func assignedProject(_ s: CalendarSession) -> String? {
        if let p = entry(.sessions, label(s)).project, !p.isEmpty { return p }
        for f in s.folders where f != "Claude" {
            if let p = entry(.folders, f).project, !p.isEmpty { return p }
        }
        if let p = entry(.projects, projectName(root: s.root)).project, !p.isEmpty { return p }
        return nil
    }

    /// Whether this project's session titles, commits and first messages stay out of everything shown.
    public func hidesTitles(project: String) -> Bool {
        entry(.projects, project).hideTitles == true
    }

    /// Names that must not appear in text about other projects: every project moved into a hidden-titles
    /// project, and the folder names that map to it.
    public func secretNames() -> [String] {
        var out: [String] = []
        for (name, e) in projects {
            guard let target = e.project, !target.isEmpty, hidesTitles(project: target) else { continue }
            if !out.contains(name) { out.append(name) }
            for (folder, mapped) in projectFolders where mapped == name && !out.contains(folder) { out.append(folder) }
        }
        return out.sorted()
    }

    /// Whether `text` names a secret project as a whole word (case-insensitive). Used on every text Tidemark shows
    /// or hands to Claude Code. "tide" matches "fix tide charts" and "tide-web", not "tidemark".
    public func mentionsSecret(_ text: String) -> Bool {
        for name in secretNames() {
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
        }
        return false
    }

    /// Applies the user's moves to every session, in order (ES §5.2 `assign`). A session moved into a project that
    /// is itself moved doesn't follow it on (not transitive). The target is looked up by the calendar's name for a
    /// folder or by the name the user gave it; an unknown target becomes a new project `project:<name>`.
    /// The later weeks code uses this to group sessions.
    public static func assignProjects(_ sessions: [CalendarSession], names: NameBook) -> [AssignedSession] {
        var known: [String: String] = [:]
        for s in sessions {
            let p = names.projectName(root: s.root)
            if known[p] == nil { known[p] = s.root }
            let shown = names.shown(.projects, p)
            if known[shown] == nil { known[shown] = s.root }
        }
        return sessions.map { s in
            guard let p = names.assignedProject(s) else {
                return AssignedSession(session: s, root: s.root, project: names.projectName(root: s.root))
            }
            let root = known[p] ?? "project:" + p
            return AssignedSession(session: s, root: root, project: names.projectName(root: root))
        }
    }
}
