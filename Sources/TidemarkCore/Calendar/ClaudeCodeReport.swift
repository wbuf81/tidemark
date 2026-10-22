import Foundation

/// Asks the user's own Claude Code for three sentences about the week. It runs with no tools, no MCP servers and
/// no user settings or hooks, in an empty folder, and is handed only the week's numbers and masked titles.
public struct ClaudeCodeReport: Sendable {
    /// Words that can't match a user's own "weekly report" rules.
    static let instruction = "Summarise the work log below in exactly three plain sentences. Sentence 1: what was shipped or finished. Sentence 2: what took most of the time. Sentence 3: what is next or still open. No bullets, no headings, no names of people, no tools. Reply with the three sentences only, one per line."

    static let disallowedTools = "Agent Task Bash BashOutput KillShell Edit MultiEdit Write Read Glob Grep LS WebFetch WebSearch NotebookEdit NotebookRead TodoWrite Skill SlashCommand ExitPlanMode Monitor EnterWorktree ExitWorktree ToolSearch TaskStop LSP"

    /// The arguments are locked: no user settings, no tools, no MCP servers. `--permission-mode default` keeps a user's
    /// "accept everything" setting out of the run, so anything that isn't denied above still has to ask (and `-p` can't ask).
    static let arguments = ["-p", "--output-format", "text", "--setting-sources", "project", "--permission-mode", "default",
                            "--disallowedTools", disallowedTools,
                            "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]

    private let runner: ProcessRunning
    private let home: URL
    private let candidates: [URL]
    private let timeout: TimeInterval
    private let calendar: Calendar

    /// `candidates` are the places to look for `claude`, in order. The app passes `systemCandidates`; tests pass their own.
    /// `environment` is Claude Code's, as the app sees it. The child process only gets `HOME` and a fixed `PATH`.
    public init(runner: ProcessRunning, home: URL, environment: [String: String], candidates: [URL],
                timeout: TimeInterval = 120, calendar: Calendar = .current) {
        self.runner = runner
        self.home = home
        self.candidates = candidates
        self.timeout = timeout
        self.calendar = CalendarKeys.gregorian(calendar)
    }

    /// Where Claude Code usually lives. Never a login shell.
    public static func systemCandidates(home: URL) -> [URL] {
        [home.appendingPathComponent(".claude/local/claude"), home.appendingPathComponent(".local/bin/claude"),
         URL(fileURLWithPath: "/opt/homebrew/bin/claude"), URL(fileURLWithPath: "/usr/local/bin/claude")]
    }

    /// The first candidate that exists and can be run.
    public var executable: URL? {
        candidates.first { url in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && !isFolder.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// What Claude Code is told about the week, as JSON: totals, projects with hours, and each day's note and work.
    /// Titles and commit subjects are the ones the week shows, already masked for hidden projects and secret names.
    /// No first message is ever included: the week doesn't carry them.
    public static func summary(_ w: WeekModel, calendar: Calendar = .current) -> String {
        let calendar = CalendarKeys.gregorian(calendar)
        func day(_ i: Int) -> [String: Any] {
            let items = w.items.filter { $0.day == i }
            return ["date": dayString(w.days[i], calendar: calendar), "hours": HoursText.format(w.perDay[i]),
                    "commits": w.commitsPerDay[i], "note": w.dayNotes[i],
                    "work": items.map { item -> [String: Any] in
                        ["project": item.project, "title": item.title, "hours": HoursText.format(item.seconds),
                         "commits": Array(item.commitSubjects.prefix(6))]
                    }]
        }
        let object: [String: Any] = [
            "week": ["start": dayString(w.days[0], calendar: calendar), "end": dayString(w.days[6], calendar: calendar)],
            "hours": HoursText.format(w.total),
            "sessions": ["total": w.sessions, "claudeCode": w.claudeCodeSessions, "cowork": w.coworkSessions],
            "commits": w.commits, "repos": w.repos,
            "projects": w.projects.map { ["name": $0.name, "hours": HoursText.format($0.seconds), "sessions": $0.sessions, "commits": $0.commits] as [String: Any] },
            "days": (0..<7).map(day),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs Claude Code (off the calling thread) and turns its first three non-empty lines into the week's report.
    public func write(_ w: WeekModel, now: Date) async -> Result<WeekReport, ReportFailure> {
        guard let executable else { return .failure(.notInstalled) }
        // Titles can't be masked while names.json can't be read, so nothing goes to Claude Code.
        if w.problems.contains(where: { $0.id == WeekComputer.namesUnreadableID }) {
            return .failure(.failed("Names & tags couldn’t be read, so nothing is sent to Claude Code."))
        }
        let input = Data((Self.instruction + "\n\n" + Self.summary(w, calendar: calendar)).utf8)
        let folder = AppIdentity.supportURL(home: home).appendingPathComponent("report", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let weekStart = dayString(w.days[0], calendar: calendar)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let started = Date()
                guard let result = runner.run(executable, Self.arguments, cwd: folder, timeout: timeout, stdin: input, home: home) else {
                    let waited = Date().timeIntervalSince(started)
                    continuation.resume(returning: .failure(waited >= timeout - 0.5 ? .timedOut : .failed("Claude Code couldn’t start.")))
                    return
                }
                guard result.status == 0 else {
                    let message = String(decoding: result.err, as: UTF8.self).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                        .first { !$0.isEmpty }
                    continuation.resume(returning: .failure(.failed(String((message ?? "Claude Code stopped with status \(result.status).").prefix(200)))))
                    return
                }
                let lines = Self.threeLines(String(decoding: result.out, as: UTF8.self))
                guard lines.count == 3 else { continuation.resume(returning: .failure(.unreadable)); return }
                continuation.resume(returning: .success(WeekReport(weekStart: weekStart, lines: lines, days: [:], author: .claudeCode, written: now)))
            }
        }
    }

    private static let marker = try! NSRegularExpression(pattern: #"^\s*(?:\d+[.)]|[-*•])\s+"#)

    /// The first three non-empty lines, each without a list marker.
    static func threeLines(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = String(raw)
            line = marker.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            out.append(line)
            if out.count == 3 { break }
        }
        return out
    }
}
