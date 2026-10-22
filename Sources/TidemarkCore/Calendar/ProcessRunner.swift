import Foundation

/// Runs a program and returns what it printed; nil when it couldn't start or ran out of time.
/// Tests use fakes: no test starts a real program through this beyond harmless system tools.
public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL)
        -> (status: Int32, out: Data, err: Data)?
}

/// The real thing. The child gets `HOME=<home>`, a fixed `PATH` and, when the given `environment` sets it,
/// `CLAUDE_CONFIG_DIR` (so Claude Code finds the same config folder the app does). Nothing else from the user's environment.
public struct SystemProcessRunner: ProcessRunning {
    static let path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

    private let environment: [String: String]

    public init(environment: [String: String] = [:]) {
        self.environment = environment
    }

    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        func set(_ data: Data) { lock.lock(); stored = data; lock.unlock() }
        /// A copy, safe to take while the reader may still be filling it.
        var data: Data { lock.lock(); defer { lock.unlock() }; return stored }
    }

    public func run(_ executable: URL, _ args: [String], cwd: URL?, timeout: TimeInterval, stdin: Data?, home: URL)
        -> (status: Int32, out: Data, err: Data)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = cwd
        var childEnvironment = ["HOME": home.path, "PATH": Self.path]
        if let config = environment["CLAUDE_CONFIG_DIR"], !config.isEmpty { childEnvironment["CLAUDE_CONFIG_DIR"] = config }
        process.environment = childEnvironment
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        // A child that exits before reading its input must not kill this app with SIGPIPE: the write just fails.
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { return nil }

        // The reads and the write block until the child is done with its pipes, so each gets a thread of its own.
        // On GCD's shared queues, several runs at once on a Mac with few cores can fill them with blocked readers,
        // and then the process's own exit notice (also on GCD) never runs: every run times out.
        let out = Buffer(), err = Buffer()
        let readers = DispatchGroup()
        readers.enter()
        Thread.detachNewThread { out.set(outPipe.fileHandleForReading.readDataToEndOfFile()); readers.leave() }
        readers.enter()
        Thread.detachNewThread { err.set(errPipe.fileHandleForReading.readDataToEndOfFile()); readers.leave() }
        Thread.detachNewThread {
            if let stdin { try? inPipe.fileHandleForWriting.write(contentsOf: stdin) }
            try? inPipe.fileHandleForWriting.close()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        _ = readers.wait(timeout: .now() + 5)
        return (process.terminationStatus, out.data, err.data)
    }
}

/// Whether the Mac has developer tools. Without them `/usr/bin/git` is a stub that pops up an install
/// prompt, so git is never run until `xcode-select -p` succeeds.
enum DeveloperTools {
    static func available(runner: ProcessRunning, home: URL) -> Bool {
        guard let result = runner.run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"], cwd: nil, timeout: 10, stdin: nil, home: home)
        else { return false }
        return result.status == 0
    }
}
