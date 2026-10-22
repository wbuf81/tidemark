import Foundation

extension CalendarStore {
    static let noClaudeCode = CalendarProblem(id: "no-claude-code", title: "Claude Code hasn’t run on this Mac yet",
                                              detail: "Your week fills in after your first session.")
    static let noGit = CalendarProblem(id: "no-git", title: "Git isn’t installed",
                                       detail: "Commits are left out. Install the Command Line Tools to add them.")

    /// Reads what changed in Claude Code, Cowork and git since the last refresh and saves it. Runs off the
    /// calling thread, one refresh at a time: a call made while one runs gets that one's result.
    public func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary {
        let task = startOrJoinRefresh {
            Task.detached(priority: .utility) { [self] in
                let summary = self.performRefresh(sources, now: now)
                self.finishRefresh()
                return summary
            }
        }
        return await task.value
    }

    private func performRefresh(_ sources: SourceSwitches, now: Date) -> RefreshSummary {
        let stored = storedSessions
        let generation = currentGeneration
        // Transcripts changed since the last refresh, less a day. A source that was off last time (the switches are kept in
        // format.json, so this holds across relaunches) is read in full, and so is everything when first messages or git come on,
        // and the Cowork log, which is small and has no modification times to go by.
        let previous = switches
        let since = lastRefresh().map { $0.addingTimeInterval(-86_400) }
        let newDetail = (sources.firstMessages && !previous.firstMessages) || (sources.git && !previous.git)
        let claudeSince = previous.claudeCode && !newDetail ? since : nil
        let desktopSince = previous.desktopCowork && !newDetail ? since : nil
        var problems: [CalendarProblem] = []
        var raws: [RawSession] = []
        var read = 0

        // Claude Code
        if sources.claudeCode {
            let projects = ClaudePaths.projectsDir(environment: environment, home: home)
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: projects.path, isDirectory: &isFolder), isFolder.boolValue {
                let own = AppIdentity.supportURL(home: home).appendingPathComponent("report", isDirectory: true)
                for file in TranscriptReader.files(projectsDir: projects, since: claudeSince) {
                    read += 1
                    if let raw = TranscriptReader.read(file, keepFirstMessage: sources.firstMessages, ignoringRunsUnder: own) { raws.append(raw) }
                }
            } else {
                problems.append(Self.noClaudeCode)
            }
        }

        // Cowork
        var logged: [RawSession] = []
        var desktop: [RawSession] = []
        if let path = sources.coworkLogFolder, !path.isEmpty {
            let result = CoworkLogReader.read(folder: URL(fileURLWithPath: path), since: nil, keepFirstMessage: sources.firstMessages)
            logged = result.sessions
            if let problem = result.problem { problems.append(problem) }
        }
        if sources.desktopCowork {
            let root = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
            desktop = DesktopCoworkReader.read(root: root, since: desktopSince, keepFirstMessage: sources.firstMessages)
        }
        read += logged.count + desktop.count
        raws += CoworkMerge.merge(desktop: desktop, log: logged)

        // Git
        let git = sources.git ? GitReader(runner: runner, home: home) : nil
        let useGit = git?.isAvailable ?? false
        if sources.git, !useGit { problems.append(Self.noGit) }
        let locator = GitRepoLocator(runner: runner, home: home)

        var byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var touched = Set<String>()
        var hashes: [String: Set<String>] = [:]
        var times: [String: [Date]] = [:]
        var freshRepos: [String: [Block]] = [:]
        for raw in raws {
            let repo = useGit && raw.origin == .claudeCode ? raw.cwd.flatMap { locator.repo(for: $0) } : nil
            let fresh = SessionBuilder.session(raw, repo: repo)
            let combined = Self.combine(byID[raw.id], fresh)
            byID[raw.id] = combined
            touched.insert(raw.id)
            hashes[raw.id] = raw.hashes
            times[raw.id] = raw.times
            if combined.isGit { freshRepos[combined.root, default: []] += fresh.blocks }
        }

        // First messages off: nothing of them stays.
        if !sources.firstMessages {
            for (id, s) in byID where s.firstMessage != nil || s.command != nil {
                var cleared = s
                cleared.firstMessage = nil
                cleared.command = nil
                byID[id] = cleared
                touched.insert(id)
            }
        }

        // Commits, matched to the sessions that were refreshed (a commit already on a session stays where it is).
        var all = SessionBuilder.sorted(Array(byID.values))
        if let git, useGit {
            var commits: [Commit] = []
            for (repo, blocks) in freshRepos.sorted(by: { $0.key < $1.key }) {
                guard let first = blocks.map(\.start).min(), let last = blocks.map(\.end).max() else { continue }
                commits += git.commits(repo: repo, from: first, to: last.addingTimeInterval(CommitMatcher.grace))
            }
            CommitMatcher.assign(commits, to: &all, hashes: hashes, activity: times)
        }

        let before = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let changed = all.filter { before[$0.id] != $0 }
        // One turn for the save: sessions first, then (only when they all saved) the refresh's time and switches.
        // If Delete all ran meanwhile, nothing of this refresh is kept.
        let saved = commitRefresh(changed, base: before, generation: generation, now: now, sources: sources)
        if saved.dropped { return RefreshSummary(sessionsRead: read, sessionsChanged: 0, problems: []) }
        setRefreshProblems(problems)
        return RefreshSummary(sessionsRead: read, sessionsChanged: changed.count, problems: problems)
    }

    /// A session read again joins what is stored: it never loses time, commits or a title it had.
    /// Blocks are joined when they overlap or lie within the idle gap; the stored commits stay.
    static func combine(_ old: CalendarSession?, _ new: CalendarSession) -> CalendarSession {
        guard let old else { return new }
        var s = new
        s.blocks = joined(old.blocks + new.blocks)
        s.commits = old.commits
        if (s.title ?? "").isEmpty { s.title = old.title }
        if (s.firstMessage ?? "").isEmpty { s.firstMessage = old.firstMessage }
        if (s.command ?? "").isEmpty { s.command = old.command }
        if !new.isGit, old.isGit {
            s.root = old.root
            s.isGit = true
        }
        if s.folders.isEmpty { s.folders = old.folders }
        s.scheduled = old.scheduled || new.scheduled
        s.logged = old.logged || new.logged
        s.lastActivity = max(old.lastActivity, new.lastActivity)
        return s
    }

    static func joined(_ blocks: [Block]) -> [Block] {
        var result: [Block] = []
        for block in blocks.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = result.last, block.start.timeIntervalSince(last.end) <= SessionBuilder.idleGap {
                result[result.count - 1].end = max(last.end, block.end)
            } else {
                result.append(block)
            }
        }
        return result
    }
}
