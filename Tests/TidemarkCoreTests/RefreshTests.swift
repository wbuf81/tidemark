import Foundation
import Testing
@testable import TidemarkCore

private let weekly = Data(#"{"limits":[{"kind":"weekly_all","percent":40,"resets_at":"2026-10-09T08:00:00Z"}]}"#.utf8)
/// A plan with a 5-hour window but no weekly limit (a free plan may look like this).
private let sessionOnly = Data(#"{"limits":[{"kind":"session","percent":10,"resets_at":null}]}"#.utf8)

private final class Asked: @unchecked Sendable { var ids: [String] = [] }

@Suite struct UsageRoundTests {
    @Test func oneUnreadableOrgDoesNotBlankTheOthers() async throws {
        let outcome = try await UsageRound.run([personal, harbor], at: designNow) { org in
            org == personal ? weekly : sessionOnly
        }
        #expect(outcome.readings.map(\.org) == ["personal"])
        #expect(outcome.readings.first?.week == 40)
        #expect(outcome.failures == [UsageRound.Failure(org: harbor, problem: .noWeeklyLimit)])
    }

    @Test func aRefusedOrgOnlyLosesItsOwnReading() async throws {
        let outcome = try await UsageRound.run([personal, harbor], at: designNow) { org in
            if org == personal { throw WebSessionError.forbidden }
            return weekly
        }
        #expect(outcome.readings.map(\.org) == ["harbor"])
        #expect(outcome.failures == [UsageRound.Failure(org: personal, problem: .refused)])
    }

    @Test func signingOutEndsTheRound() async {
        let asked = Asked()
        await #expect(throws: WebSessionError.signedOut) {
            try await UsageRound.run([personal, harbor], at: designNow) { org in
                asked.ids.append(org.id)
                throw WebSessionError.signedOut
            }
        }
        #expect(asked.ids == ["personal"])
    }

    @Test func requestTimesOutAfter20Seconds() async throws {
        let asked = Asked()
        let slept = Asked()
        let outcome = try await UsageRound.run([personal, harbor], at: designNow, sleep: { limit in
            // Virtual time: the limit "passes" at once, but only after the fetch has started.
            slept.ids.append("\(limit)")
            try await Task.sleep(for: .milliseconds(20))
        }) { org in
            asked.ids.append(org.id)
            try await Task.sleep(for: .seconds(3600))   // never answers
            return weekly
        }
        #expect(slept.ids == ["20.0 seconds", "20.0 seconds"])
        #expect(asked.ids == ["personal", "harbor"])
        #expect(outcome.readings.isEmpty)
        #expect(outcome.failures.map(\.problem) == [.offline, .offline])
    }

    @Test func aFetchThatIgnoresCancellationStillTimesOut() async throws {
        let outcome = try await UsageRound.run([personal], at: designNow, sleep: { _ in }) { _ in
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }   // never resumes
            return weekly
        }
        #expect(outcome.failures.map(\.problem) == [.offline])
    }

    @Test func aFastAnswerBeatsTheLimit() async throws {
        let outcome = try await UsageRound.run([personal], at: designNow, sleep: { _ in try await Task.sleep(for: .seconds(3600)) }) { _ in weekly }
        #expect(outcome.readings.count == 1)
        #expect(outcome.failures.isEmpty)
    }

    @Test func anUnreadableAnswerSaysWhatCameBack() async throws {
        let outcome = try await UsageRound.run([personal], at: designNow) { _ in Data("<html>Error 502</html>".utf8) }
        #expect(outcome.failures.map(\.problem) == [.changedShape(details: "HTTP 200: <html>Error ###</html>")])
    }

    @Test func anOutcomeCanBeGivenAsIs() {
        let r = reading(week: 40, weekResetsAt: local(2026, 10, 9, 4))
        let outcome = UsageRound.Outcome(readings: [r], failures: [UsageRound.Failure(org: harbor, problem: .refused)])
        #expect(outcome.readings == [r])
        #expect(outcome.failures.map(\.problem) == [.refused])
        #expect(UsageRound.Outcome().readings.isEmpty && UsageRound.Outcome().failures.isEmpty)
    }
}

@Suite struct RefreshProblemTests {
    @Test func errorsBecomeProblems() {
        #expect(RefreshProblem(WebSessionError.blocked) == .blocked)
        #expect(RefreshProblem(WebSessionError.notReady) == .offline)
        #expect(RefreshProblem(WebSessionError.forbidden) == .refused)
        #expect(RefreshProblem(WebSessionError.http(503)) == .http(503))
        #expect(RefreshProblem(WebSessionError.badResult) == .changedShape(details: "No answer from the page"))
        #expect(RefreshProblem(UsageParserError.notJSON) == .changedShape(details: ""))
        #expect(RefreshProblem(UsageParserError.unreadableResetTime) == .changedShape(details: ""))
        #expect(RefreshProblem(UsageParserError.noWeeklyLimit) == .noWeeklyLimit)
        // A fetch() that couldn't connect fails inside the page's script.
        #expect(RefreshProblem(URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func whenEverythingFailsTheLineSaysWhatHappened() {
        #expect(UsageCopy.problem(.offline) == "Can’t reach claude.ai. Trying again in a few minutes.")
        #expect(UsageCopy.problem(.blocked) == "claude.ai’s bot check stopped Tidemark. Trying again in a few minutes.")
        #expect(UsageCopy.problem(.http(503)) == "claude.ai answered with error 503. Trying again in a few minutes.")
        #expect(UsageCopy.problem(.changedShape(details: "")) == "claude.ai answered in a way Tidemark can’t read; its usage page may have changed.")
        #expect(UsageCopy.problem(.refused) == "claude.ai refused to share usage.")
    }

    @Test func whenSomeOrgsFailTheLineNamesThem() {
        let failures = [UsageRound.Failure(org: harbor, problem: .noWeeklyLimit)]
        #expect(UsageCopy.problem(failures, shown: 2) == "Couldn’t read Harbor Labs: no weekly limit.")
        #expect(UsageCopy.problem([], shown: 2) == nil)
        let both = [UsageRound.Failure(org: personal, problem: .refused), UsageRound.Failure(org: harbor, problem: .refused)]
        #expect(UsageCopy.problem(both, shown: 2) == "claude.ai refused to share usage for Personal and Harbor Labs.")
        let personal = Org(id: "personal", name: "Personal")
        #expect(UsageCopy.problem([UsageRound.Failure(org: personal, problem: .noWeeklyLimit)], shown: 1)
                == "claude.ai shows no weekly limit for Personal.")
    }

    @Test func theWidgetGetsAShortForm() {
        #expect(UsageCopy.short(.offline) == "no connection")
        #expect(UsageCopy.short(.blocked) == "blocked by a bot check")
        #expect(UsageCopy.short(.http(500)) == "claude.ai error 500")
        #expect(UsageCopy.short(.noWeeklyLimit) == "no weekly limit")
        #expect(UsageCopy.short(.changedShape(details: "")) == "claude.ai changed how it answers")
    }

    @Test func aPlansMenuLineIsItsNameForNow() {
        #expect(UsageCopy.menuLine(personal, glance: nil) == "Personal")
    }
}

@Suite struct UsageGateTests {
    @Test func onlyAnEnabledLiveSessionMayAsk() {
        #expect(UsageGate.mayRequest(planLimits: true, demoMode: false, firstRunDone: true))
        #expect(!UsageGate.mayRequest(planLimits: false, demoMode: false, firstRunDone: true))
        #expect(!UsageGate.mayRequest(planLimits: true, demoMode: true, firstRunDone: true))
        #expect(!UsageGate.mayRequest(planLimits: false, demoMode: true, firstRunDone: true))
    }

    // M2: until first run is done nothing reads claude.ai and no sign-in opens, whatever the switch says
    // (the owner's migrated settings have plan limits on while first run is still to come).
    @Test func nothingIsAskedBeforeFirstRunIsDone() async throws {
        #expect(!UsageGate.mayRequest(planLimits: true, demoMode: false, firstRunDone: false))
        let asked = Asked()
        let outcome = try await UsageGate.run([personal], at: designNow, planLimits: true, demoMode: false, firstRunDone: false) { org in
            asked.ids.append(org.id)
            return weekly
        }
        #expect(outcome == nil)
        #expect(asked.ids.isEmpty)
        let generation = RefreshGeneration()
        #expect(!UsageGate.mayWrite(generation.begin(), in: generation, planLimits: true, demoMode: false, firstRunDone: false))
    }

    // Off means off: not a request through a refresh, a wake or a network return.
    @Test func noRequestsWhenPlanLimitsOff() async throws {
        let asked = Asked()
        for _ in ["refresh", "wake", "network return"] {
            let outcome = try await UsageGate.run([personal, harbor], at: designNow, planLimits: false, demoMode: false, firstRunDone: true) { org in
                asked.ids.append(org.id)
                return weekly
            }
            #expect(outcome == nil)
        }
        #expect(asked.ids.isEmpty)
        let on = try await UsageGate.run([personal], at: designNow, planLimits: true, demoMode: false, firstRunDone: true) { org in
            asked.ids.append(org.id)
            return weekly
        }
        #expect(on?.readings.count == 1)
        #expect(asked.ids == ["personal"])
    }

    // A refresh that was running when limits went off, or Delete all began, must not write.
    @Test func aStoppedRefreshMayNotWrite() {
        var generation = RefreshGeneration()
        let started = generation.begin()
        #expect(UsageGate.mayWrite(started, in: generation, planLimits: true, demoMode: false, firstRunDone: true))
        generation.cancel()
        #expect(!UsageGate.mayWrite(started, in: generation, planLimits: true, demoMode: false, firstRunDone: true))
        let next = generation.begin()
        #expect(UsageGate.mayWrite(next, in: generation, planLimits: true, demoMode: false, firstRunDone: true))
        #expect(!UsageGate.mayWrite(next, in: generation, planLimits: false, demoMode: false, firstRunDone: true))
        #expect(!UsageGate.mayWrite(next, in: generation, planLimits: true, demoMode: true, firstRunDone: true))
    }
}
