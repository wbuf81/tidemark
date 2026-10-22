import Foundation

/// Why a refresh left an org (or every org) without a fresh reading.
public enum RefreshProblem: Equatable, Sendable {
    /// claude.ai couldn't be reached: offline, or the hidden page didn't load.
    case offline
    /// The site's bot check answered instead of the API.
    case blocked
    /// claude.ai refused access (a JSON 403 while still signed in).
    case refused
    case http(Int)
    /// The org's usage has no weekly limit to show.
    case noWeeklyLimit
    /// claude.ai answered with something Tidemark can't read: its usage page may have changed.
    /// `details` says what was unexpected (empty until the parser reports it).
    case changedShape(details: String)

    public init(_ error: Error) {
        switch error {
        case WebSessionError.blocked: self = .blocked
        case WebSessionError.forbidden: self = .refused
        case WebSessionError.http(let code): self = .http(code)
        case WebSessionError.badResult: self = .changedShape(details: "No answer from the page")
        case UsageParserError.noWeeklyLimit: self = .noWeeklyLimit
        case is UsageParserError: self = .changedShape(details: "")
        // The page didn't load, or its fetch() couldn't connect.
        default: self = .offline
        }
    }
}

/// One refresh across every shown org.
public enum UsageRound {
    public struct Failure: Equatable, Sendable {
        public var org: Org
        public var problem: RefreshProblem

        public init(org: Org, problem: RefreshProblem) {
            self.org = org
            self.problem = problem
        }
    }

    public struct Outcome: Sendable {
        public var readings: [Reading] = []
        public var failures: [Failure] = []

        /// A round's result as given, for `--render`'s states; refreshes build theirs with `run`.
        public init(readings: [Reading] = [], failures: [Failure] = []) {
            self.readings = readings
            self.failures = failures
        }
    }

    /// How long one org's request may take before the round gives up on it as offline.
    public static let requestTimeLimit: Duration = .seconds(20)

    /// Reads each org in turn. An org that can't be read only loses its own reading, so a
    /// free plan or a refused org never blanks the others; a sign-out ends the round, since
    /// every org would fail the same way. A request that doesn't answer within `timeLimit`
    /// counts as offline. `sleep` is the clock the limit runs on (tests pass a fake).
    public static func run(_ orgs: [Org], at now: Date, isolation: isolated (any Actor)? = #isolation,
                           timeLimit: Duration = requestTimeLimit,
                           sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                           fetch: @escaping (Org) async throws -> Data) async throws -> Outcome {
        var outcome = Outcome()
        for org in orgs {
            var answer: Data?
            do {
                let data = try await withTimeLimit(timeLimit, sleep: sleep) { try await fetch(org) }
                answer = data
                outcome.readings.append(try UsageParser.reading(from: data, org: org.id, at: now))
            } catch WebSessionError.signedOut {
                throw WebSessionError.signedOut
            } catch {
                let problem = answer.map { UsageParser.problem(for: error, answer: $0) } ?? RefreshProblem(error)
                outcome.failures.append(Failure(org: org, problem: problem))
            }
        }
        return outcome
    }

    /// Runs `work`, giving up with a timeout once `limit` has passed on `sleep`'s clock. The
    /// caller is released at the limit even when `work` ignores cancellation.
    static func withTimeLimit(_ limit: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void,
                              work: @escaping () async throws -> Data) async throws -> Data {
        let race = Race()
        let job = UncheckedBox(work)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.start(continuation)
                race.add(Task {
                    do { race.finish(.success(try await job.value())) } catch { race.finish(.failure(error)) }
                })
                race.add(Task {
                    do { try await sleep(limit) } catch { return }
                    race.finish(.failure(URLError(.timedOut)))
                })
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
    }

    private struct UncheckedBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    /// Settles once: the first result wins, and the other task is cancelled.
    private final class Race: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        private var pending: Result<Data, Error>?
        private var tasks: [Task<Void, Never>] = []
        private var done = false

        func start(_ continuation: CheckedContinuation<Data, Error>) {
            lock.lock()
            if let pending { lock.unlock(); continuation.resume(with: pending); return }
            self.continuation = continuation
            lock.unlock()
        }

        func add(_ task: Task<Void, Never>) {
            lock.lock()
            if done { lock.unlock(); task.cancel(); return }
            tasks.append(task)
            lock.unlock()
        }

        func finish(_ result: Result<Data, Error>) {
            lock.lock()
            guard !done else { lock.unlock(); return }
            done = true
            let continuation = self.continuation
            self.continuation = nil
            if continuation == nil { pending = result }
            let toCancel = tasks
            lock.unlock()
            toCancel.forEach { $0.cancel() }
            continuation?.resume(with: result)
        }
    }
}
