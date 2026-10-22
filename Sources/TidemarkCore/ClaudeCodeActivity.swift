import CoreServices
import Foundation

/// Notices Claude Code working: while it runs it appends to its transcripts in
/// `~/.claude/projects` every few seconds. Watches that folder with FSEvents and reports only
/// *that* a transcript changed, and when. It never opens the files.
public final class ClaudeCodeActivity: @unchecked Sendable {
    let folder: URL
    private let onActivity: @Sendable (Date) -> Void
    private let recheckInterval: TimeInterval
    private let queue = DispatchQueue(label: "\(AppIdentity.name).ClaudeCodeActivity")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private var started = false

    /// `~/.claude/projects`, or where `$CLAUDE_CONFIG_DIR` puts it. `recheckInterval` is how often a
    /// folder that doesn't exist yet is looked for.
    public init(folder: URL = ClaudePaths.projectsDir(environment: ProcessInfo.processInfo.environment,
                                                     home: FileManager.default.homeDirectoryForCurrentUser),
                recheckInterval: TimeInterval = 30,
                onActivity: @escaping @Sendable (Date) -> Void) {
        self.folder = folder
        self.recheckInterval = recheckInterval
        self.onActivity = onActivity
    }

    deinit { stop() }

    /// Starts watching. A folder that doesn't exist yet (Claude Code never ran) reports nothing
    /// until it appears; Tidemark looks again every `recheckInterval` seconds and starts then.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        if !arm() { startTimer() }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + recheckInterval, repeating: recheckInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.started, self.stream == nil else { return }
            if self.arm() { self.timer?.cancel(); self.timer = nil }
        }
        self.timer = timer
        timer.resume()
    }

    /// Opens the FSEvents stream when the folder exists. Call with the lock held.
    private func arm() -> Bool {
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeActivity>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if changed.contains(where: { $0.hasSuffix(".jsonl") }) { watcher.onActivity(Date()) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        // Up to a second's latency: FSEvents batches a busy second's writes into one report.
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        return true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        started = false
        timer?.cancel()
        timer = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
