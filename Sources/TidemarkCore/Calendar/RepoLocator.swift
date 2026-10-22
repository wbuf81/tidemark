import Foundation

/// Finds the main checkout a working folder belongs to.
protocol RepoLocating {
    func repo(for cwd: String) -> String?
}

/// Asks git: from the first folder that still exists, `rev-parse --git-common-dir`, whose parent is the repo,
/// so a worktree reports its main checkout (ES §2). Answers are cached per working folder.
final class GitRepoLocator: RepoLocating, @unchecked Sendable {
    private let runner: ProcessRunning
    private let home: URL
    private let lock = NSLock()
    private var cache: [String: String?] = [:]
    private var tools: Bool?

    init(runner: ProcessRunning, home: URL) {
        self.runner = runner
        self.home = home
    }

    func repo(for cwd: String) -> String? {
        lock.lock()
        if let known = cache[cwd] { lock.unlock(); return known }
        lock.unlock()
        let found = locate(cwd)
        lock.lock()
        cache[cwd] = .some(found)
        lock.unlock()
        return found
    }

    private func locate(_ cwd: String) -> String? {
        guard developerTools(), let folder = firstExistingFolder(cwd) else { return nil }
        guard let result = runner.run(URL(fileURLWithPath: "/usr/bin/git"),
                                      ["-C", folder, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                      cwd: nil, timeout: 30, stdin: nil, home: home),
              result.status == 0 else { return nil }
        let common = String(decoding: result.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard common.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: common).deletingLastPathComponent().path
    }

    private func developerTools() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let tools { return tools }
        let ok = DeveloperTools.available(runner: runner, home: home)
        tools = ok
        return ok
    }

    private func firstExistingFolder(_ cwd: String) -> String? {
        var url = URL(fileURLWithPath: cwd)
        var isDirectory: ObjCBool = false
        while !(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return url.path
    }
}
