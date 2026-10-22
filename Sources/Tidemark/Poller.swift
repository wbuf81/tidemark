import Foundation
import Network
import TidemarkCore

/// Reads claude.ai every 3 minutes (backing off on errors, by `NetworkRetry`) and watches which org
/// Claude Code is signed into. Does nothing at all while plan limits are off: no request, no web
/// view (`UsageGate`). A Mac that wakes, or a network that comes back, ends the back-off and reads
/// at once. `stop()` also ends a round already running: it may not show readings or write history.
@MainActor
final class Poller {
    private let model: AppModel
    private let session: ClaudeWebSession
    private let account: ClaudeCodeAccount
    private var loop: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var retry = NetworkRetry()
    private var nextDelay = NetworkRetry.pollInterval
    private var generation = RefreshGeneration()
    private var inFlightNumber = 0
    private var orgsFetchedAt: Date?
    private var accountModified: Date?
    private var inFlight: Task<Void, Never>?
    private var monitor: NWPathMonitor?
    private var online = true

    /// Whether claude.ai may be asked right now.
    private var mayRequest: Bool {
        UsageGate.mayRequest(planLimits: model.settings.planLimits, demoMode: model.settings.demoMode,
                             firstRunDone: model.settings.firstRunDone)
    }

    init(model: AppModel, session: ClaudeWebSession, account: ClaudeCodeAccount) {
        self.model = model
        self.session = session
        self.account = account
    }

    /// Starts or restarts polling. With `immediately: false` the first refresh waits one interval.
    func start(immediately: Bool = true) {
        loop?.cancel()
        loop = nil
        guard mayRequest else { stopWatching(); return }
        if !immediately { nextDelay = NetworkRetry.pollInterval }
        watchNetwork()
        loop = Task { [weak self] in
            var refreshNow = immediately
            while !Task.isCancelled {
                guard let self else { return }
                if refreshNow { await self.refresh() }
                refreshNow = true
                try? await Task.sleep(for: .seconds(self.nextDelay))
            }
        }
        if watcher == nil {
            watcher = Task { [weak self] in
                while !Task.isCancelled {
                    self?.checkAccount()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        generation.cancel()
        inFlight?.cancel()
        inFlight = nil
        stopWatching()
    }

    /// The Mac woke up: whatever it was backing off from may be over, so start over now.
    func wake() {
        guard mayRequest else { return }
        retry.wake()
        start()
    }

    /// Reads again when the network returns after being away.
    private func watchNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let returned = satisfied && !self.online
                    self.online = satisfied
                    if returned, self.mayRequest, self.retry.networkReturned() { self.start() }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "\(AppIdentity.name).Network"))
        self.monitor = monitor
    }

    private func stopWatching() {
        monitor?.cancel()
        monitor = nil
        watcher?.cancel()
        watcher = nil
        online = true
        retry = NetworkRetry()
    }

    /// Refreshes, or waits for the refresh already running (the loop, the Refresh button,
    /// opening Insights and Settings can all ask at once).
    func refresh() async {
        if let inFlight { return await inFlight.value }
        inFlightNumber += 1
        let number = inFlightNumber
        let task = Task { await refreshNow() }
        inFlight = task
        await task.value
        if inFlightNumber == number { inFlight = nil }
    }

    private func refreshNow() async {
        // Off means off: nothing is asked of claude.ai.
        guard mayRequest else { return }
        let token = generation.begin()
        func mayWrite() -> Bool {
            UsageGate.mayWrite(token, in: generation, planLimits: model.settings.planLimits, demoMode: model.settings.demoMode,
                               firstRunDone: model.settings.firstRunDone)
        }
        do {
            if model.orgsToRead.isEmpty || (orgsFetchedAt.map { Date().timeIntervalSince($0) > 86_400 } ?? true) {
                let data = try await session.getJSON("/api/organizations")
                guard mayWrite() else { return }
                let all: [Org]
                do {
                    all = try UsageParser.orgs(from: data)
                } catch {
                    // The org list has the odd shape: say what came back (masked), not nothing.
                    let problem = UsageParser.problem(for: error, answer: data)
                    nextDelay = retry.next(after: .failed(problem))
                    model.refreshFailed(problem)
                    return
                }
                model.setAvailableOrgs(all, claudeCodeOrg: account.currentOrg())
                orgsFetchedAt = Date()
            }
            let now = Date()
            let round = try await UsageGate.run(model.orgsToRead, at: now, planLimits: model.settings.planLimits,
                                                demoMode: model.settings.demoMode, firstRunDone: model.settings.firstRunDone) { [session] org in
                try await session.getJSON("/api/organizations/\(org.id)/usage")
            }
            guard let outcome = round, mayWrite() else { return }
            // A JSON 403 can mean the session is gone or only that org refused; when every
            // org refused, the org list tells which.
            if outcome.readings.isEmpty, outcome.failures.contains(where: { $0.problem == .refused }),
               await sessionIsGone() {
                guard mayWrite() else { return }
                model.sessionEnded()
                nextDelay = NetworkRetry.pollInterval
                return
            }
            model.ingest(outcome, claudeCodeOrg: account.currentOrg(), at: now)
            // Back off only when nothing worked: one org that never reads (a free plan, say)
            // mustn't slow down the others.
            if outcome.readings.isEmpty, let first = outcome.failures.first {
                nextDelay = retry.next(after: .failed(first.problem))
            } else {
                nextDelay = retry.next(after: .succeeded)
            }
        } catch WebSessionError.signedOut {
            guard mayWrite() else { return }
            model.sessionEnded()
            nextDelay = NetworkRetry.pollInterval
        } catch WebSessionError.forbidden {
            let gone = await sessionIsGone()
            guard mayWrite() else { return }
            if gone {
                model.sessionEnded()
                nextDelay = NetworkRetry.pollInterval
            } else {
                nextDelay = retry.next(after: .failed(.refused))
                model.refreshFailed(.refused)
            }
        } catch {
            guard mayWrite() else { return }
            let problem = RefreshProblem(error)
            nextDelay = retry.next(after: .failed(problem))
            model.refreshFailed(problem)
        }
    }

    /// After a sign-in the account may be different: re-read the org list, then poll.
    func restartAfterSignIn() {
        orgsFetchedAt = nil
        start()
    }

    private func sessionIsGone() async -> Bool {
        do {
            _ = try await session.getJSON("/api/organizations")
            return false
        } catch WebSessionError.signedOut, WebSessionError.forbidden {
            return true
        } catch {
            return false
        }
    }

    private func checkAccount() {
        let modified = account.modified()
        guard modified != accountModified else { return }
        accountModified = modified
        model.setClaudeCodeOrg(account.currentOrg())
    }
}
