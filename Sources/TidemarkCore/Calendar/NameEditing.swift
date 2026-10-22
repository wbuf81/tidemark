import Foundation

// Changing the name book: the same merge the old server did (ES §5.3).

extension NameBook {
    /// The book with one change applied. Only the fields sent change; text is kept to one line, names to 200
    /// characters, tags tidied; a name equal to its key clears; an entry left empty is removed.
    /// Folders take only a project. Throws `badKey` for an empty key, `*` alone, or one over 500 characters.
    public func apply(_ change: NameChange) throws -> NameBook {
        let key = change.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "*", key.count <= 500 else { throw NameBookError.badKey }

        var table: [String: NameEntry]
        switch change.kind {
        case .sessions: table = sessions
        case .projects: table = projects
        case .folders: table = folders
        }
        var e = table[key] ?? NameEntry()
        let canName = change.kind != .folders
        let canHide = change.kind == .projects

        if canName, let n = change.name { e.name = n.map(Self.oneLine(_:)) }
        if canName, let t = change.tags { e.tags = Self.tidy(t) }
        if let p = change.project { e.project = p.map(Self.oneLine(_:)) }
        if canHide, let h = change.hideTitles { e.hideTitles = h }

        if e.name == key { e.name = nil }
        if e.name?.isEmpty == true { e.name = nil }
        if e.tags?.isEmpty == true { e.tags = nil }
        if e.project?.isEmpty == true { e.project = nil }
        if e.hideTitles == false { e.hideTitles = nil }
        if !canName { e.name = nil; e.tags = nil }
        if !canHide { e.hideTitles = nil }

        if e == NameEntry() { table[key] = nil } else { table[key] = e }
        var out = self
        switch change.kind {
        case .sessions: out.sessions = table
        case .projects: out.projects = table
        case .folders: out.folders = table
        }
        return out
    }

    private static func oneLine(_ s: String) -> String {
        String(s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(200))
    }

    /// Each tag on one line, at most 40 characters, no empties, no repeats ignoring case (the first spelling stays), at most 20.
    private static func tidy(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let tag = String(t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(40))
            if tag.isEmpty || !seen.insert(tag.lowercased()).inserted { continue }
            out.append(tag)
            if out.count == 20 { break }
        }
        return out
    }
}
