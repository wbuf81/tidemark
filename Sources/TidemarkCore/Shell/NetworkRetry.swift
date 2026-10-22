import Foundation

/// How long to wait before asking claude.ai again after a failure. Each failure waits longer;
/// a success, the Mac waking, or the network coming back starts over, so the first try after
/// any of those is quick.
public struct NetworkRetry: Equatable, Sendable {
    public static let delays: [TimeInterval] = [30, 60, 120, 300, 600]

    public private(set) var failures = 0

    public init() {}

    /// Seconds to wait before the next try, given that the last one just failed.
    public mutating func failed() -> TimeInterval {
        defer { failures += 1 }
        return Self.delays[min(failures, Self.delays.count - 1)]
    }

    public mutating func succeeded() { failures = 0 }

    /// The Mac woke up: whatever it was waiting for may be over.
    public mutating func wake() { failures = 0 }

    /// The network came back. True when a refresh should run now, because one was waiting.
    public mutating func networkReturned() -> Bool {
        defer { failures = 0 }
        return failures > 0
    }

    /// Seconds between reads while they work.
    public static let pollInterval: TimeInterval = 180

    /// How a read went, for choosing the wait before the next.
    public enum Result: Equatable, Sendable {
        case succeeded
        case failed(RefreshProblem)
    }

    /// Offline is the one failure that says "trying again every minute", so its wait stops at a minute.
    public static let offlineLongestWait: TimeInterval = 60

    /// The wait before the next read. A success starts over at the 3-minute rhythm; a failure steps
    /// up the retry waits (offline stops at a minute), but never below 3 minutes after a bot check or a refusal, so a site that
    /// has just said no isn't asked again quickly.
    public mutating func next(after result: Result) -> TimeInterval {
        switch result {
        case .succeeded:
            succeeded()
            return Self.pollInterval
        case .failed(let problem):
            let wait = failed()
            switch problem {
            case .offline: return min(wait, Self.offlineLongestWait)
            case .blocked, .refused: return max(wait, Self.pollInterval)
            default: return wait
            }
        }
    }
}
