import Foundation

/// The rule behind "off means off": claude.ai is asked for nothing, and nothing is written from
/// an answer, unless plan limits are on, demo data isn't and first run is done (its step 3 is where plan
/// limits are asked about, whatever an earlier install left switched on). The app's poller, the sign-in window and
/// every trigger (refresh, wake, the network coming back) go through here.
public enum UsageGate {
    public static func mayRequest(planLimits: Bool, demoMode: Bool, firstRunDone: Bool) -> Bool {
        planLimits && !demoMode && firstRunDone
    }

    /// Runs one usage round, or does nothing (and asks nothing) when the gate is closed.
    public static func run(_ orgs: [Org], at now: Date, planLimits: Bool, demoMode: Bool, firstRunDone: Bool,
                           isolation: isolated (any Actor)? = #isolation,
                           fetch: @escaping (Org) async throws -> Data) async throws -> UsageRound.Outcome? {
        guard mayRequest(planLimits: planLimits, demoMode: demoMode, firstRunDone: firstRunDone) else { return nil }
        return try await UsageRound.run(orgs, at: now, fetch: fetch)
    }

    /// Whether a refresh that began as `started` may still show readings and write history: it was not
    /// stopped meanwhile (plan limits off, Delete all, Uninstall) and the gate is still open.
    public static func mayWrite(_ started: Int, in generation: RefreshGeneration, planLimits: Bool, demoMode: Bool, firstRunDone: Bool) -> Bool {
        generation.isCurrent(started) && mayRequest(planLimits: planLimits, demoMode: demoMode, firstRunDone: firstRunDone)
    }
}

/// A counter a refresh checks before it writes: `cancel()` makes every refresh begun earlier stale.
public struct RefreshGeneration: Equatable, Sendable {
    private var number = 0

    public init() {}

    /// The token a refresh holds while it runs.
    public func begin() -> Int { number }

    /// Stops every refresh already running.
    public mutating func cancel() { number += 1 }

    public func isCurrent(_ token: Int) -> Bool { token == number }
}
