import Foundation

/// Gives each commit to the one session that made it (ES §4).
enum CommitMatcher {
    /// A commit just after a block still belongs to it.
    static let grace: TimeInterval = 300
    /// A session counts as running when its last activity is this recent.
    static let running: TimeInterval = 1800

    /// Two shas name the same commit when one is a prefix of the other (an imported one is 7 characters).
    static func sameCommit(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4 else { return a == b }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// Candidates are git sessions in the commit's repo with a block holding the commit time, or ending
    /// at most `grace` before it. A session whose transcript printed the commit's hash (`hashes`, by session id)
    /// wins; else the candidate that was active latest before the commit: by its raw activity times (`activity`, by
    /// session id) when it was just read, else by its blocks (a block holding the commit counts as active at the
    /// commit). Ties go to the earlier session. Commits nobody made are dropped.
    ///
    /// A commit already stored on a session (same repo, one sha a prefix of the other) stays where it is; when the stored
    /// one is a short sha from an import, git's full sha, time, subject and files take its place.
    static func assign(_ commits: [Commit], to sessions: inout [CalendarSession], hashes: [String: Set<String>] = [:],
                       activity: [String: [Date]] = [:]) {
        var stored: [String: [(session: Int, sha: String)]] = [:]
        for (i, s) in sessions.enumerated() { for c in s.commits { stored[c.repo, default: []].append((i, c.sha)) } }
        for commit in commits.sorted(by: { $0.time < $1.time }) {
            if let held = stored[commit.repo]?.first(where: { sameCommit($0.sha, commit.sha) }) {
                if held.sha.count < commit.sha.count, let at = sessions[held.session].commits.firstIndex(where: { $0.sha == held.sha && $0.repo == commit.repo }) {
                    sessions[held.session].commits[at] = commit
                    sessions[held.session].commits.sort { ($0.time, $0.sha) < ($1.time, $1.sha) }
                    if let k = stored[commit.repo]?.firstIndex(where: { $0.session == held.session && $0.sha == held.sha }) {
                        stored[commit.repo]?[k].sha = commit.sha
                    }
                }
                continue
            }
            var best: (index: Int, activity: Date)?
            var made: Int?
            for (i, session) in sessions.enumerated() where session.isGit && session.root == commit.repo {
                guard let blockActivity = session.blocks.compactMap({ block -> Date? in
                    guard block.start <= commit.time, commit.time <= block.end.addingTimeInterval(grace) else { return nil }
                    return min(block.end, commit.time)
                }).max() else { continue }
                let raw = activity[session.id]?.filter { $0 <= commit.time }.max()
                let latest = raw ?? blockActivity
                if made == nil, let printed = hashes[session.id], printed.contains(where: { commit.sha.hasPrefix($0) }) { made = i }
                if best == nil || latest > best!.activity { best = (i, latest) }
            }
            guard let chosen = made ?? best?.index else { continue }
            sessions[chosen].commits.append(commit)
            sessions[chosen].commits.sort { ($0.time, $0.sha) < ($1.time, $1.sha) }
            stored[commit.repo, default: []].append((chosen, commit.sha))
        }
    }

    /// A finished git session with no commit of its own and none just before the week (ES §4).
    static func noCommit(_ s: CalendarSession, weekEnd: Date, now: Date, committedBefore: Bool) -> Bool {
        s.origin == .claudeCode && s.isGit && s.commits.isEmpty && !committedBefore
            && now.timeIntervalSince(s.lastActivity) >= running && s.lastActivity < weekEnd
    }
}
