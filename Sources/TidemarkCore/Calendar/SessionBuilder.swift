import Foundation

/// Turns raw activity into stored sessions: the 30-minute idle rule makes blocks.
enum SessionBuilder {
    /// A new block starts when the gap is strictly longer than this.
    static let idleGap: TimeInterval = 1800

    /// Blocks from activity times. A lone time is a zero-length block.
    static func blocks(_ times: [Date]) -> [Block] {
        var result: [Block] = []
        var previous: Date?
        for time in times.sorted() {
            if let last = previous, time.timeIntervalSince(last) <= idleGap {
                result[result.count - 1].end = time
            } else {
                result.append(Block(start: time, end: time))
            }
            previous = time
        }
        return result
    }

    /// The stored session for a raw one. `repo` is the main checkout the working folder belongs to, if any.
    static func session(_ raw: RawSession, repo: String?) -> CalendarSession {
        let isCowork = raw.origin == .cowork
        let root: String
        if isCowork {
            root = "Cowork"
        } else if let repo {
            root = stripped(repo)
        } else if let cwd = raw.cwd, !cwd.isEmpty {
            root = stripped(cwd)
        } else {
            root = "unknown folder"
        }
        return CalendarSession(
            id: raw.id, origin: raw.origin, title: raw.title, firstMessage: raw.firstMessage, command: raw.command,
            root: root, folders: raw.folders, isGit: !isCowork && repo != nil, scheduled: raw.scheduled, logged: raw.logged,
            blocks: blocks(raw.times), commits: [], lastActivity: raw.times.max() ?? .distantPast)
    }

    /// First block start, then id: the same order every time (ES §9.2).
    static func sorted(_ sessions: [CalendarSession]) -> [CalendarSession] {
        sessions.sorted { a, b in
            let x = a.blocks.first?.start ?? .distantFuture, y = b.blocks.first?.start ?? .distantFuture
            return x != y ? x < y : a.id < b.id
        }
    }

    private static func stripped(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
