import Foundation

/// The user's own commits in a repo, read through `git log`. Never runs git on a Mac without developer tools.
struct GitReader {
    private let runner: ProcessRunning
    private let home: URL
    private let git = URL(fileURLWithPath: "/usr/bin/git")
    /// False when the Mac has no developer tools; then `commits` answers nothing and git never starts.
    let isAvailable: Bool

    init(runner: ProcessRunning, home: URL) {
        self.runner = runner
        self.home = home
        self.isAvailable = DeveloperTools.available(runner: runner, home: home)
    }

    /// Commits made between `from` and `to` on any branch by the repo's or the global `user.email` (ES §4).
    /// A failed or timed-out git is no commits.
    func commits(repo: String, from: Date, to: Date) -> [Commit] {
        guard isAvailable else { return [] }
        let emails = Set([email(["-C", repo, "config", "user.email"]), email(["-C", home.path, "config", "--global", "user.email"])].compactMap { $0 })
        guard !emails.isEmpty else { return [] }
        let stamp = ISO8601DateFormatter()
        let args = ["-C", repo, "log", "--all", "--since=\(stamp.string(from: from))", "--until=\(stamp.string(from: to))",
                    "--format=%x1e%H%x1f%cI%x1f%ae%x1f%s", "--name-only"]
        guard let result = runner.run(git, args, cwd: nil, timeout: 30, stdin: nil, home: home), result.status == 0 else { return [] }
        return Self.parse(String(decoding: result.out, as: UTF8.self), repo: repo, emails: emails)
    }

    private func email(_ args: [String]) -> String? {
        guard let result = runner.run(git, args, cwd: nil, timeout: 30, stdin: nil, home: home), result.status == 0 else { return nil }
        let value = String(decoding: result.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    private static func parse(_ output: String, repo: String, emails: Set<String>) -> [Commit] {
        var seen = Set<String>()
        var commits: [Commit] = []
        for chunk in output.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
            guard let head = lines.first else { continue }
            let fields = head.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, let time = CalendarDates.parse(String(fields[1])) else { continue }
            let sha = String(fields[0])
            guard emails.contains(fields[2].trimmingCharacters(in: .whitespaces).lowercased()), seen.insert(sha).inserted else { continue }
            let files = lines.dropFirst().map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            commits.append(Commit(sha: sha, time: time, repo: repo, subject: String(fields[3]), files: files))
        }
        return commits
    }
}
