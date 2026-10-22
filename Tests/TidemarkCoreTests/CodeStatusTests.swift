import Foundation
import Testing
@testable import TidemarkCore

@Suite struct CodeStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func s(_ pid: Int32, _ mood: CodeMood, ago: TimeInterval) -> LiveSession {
        LiveSession(pid: pid, mood: mood, time: now.addingTimeInterval(-ago))
    }
    let alive: (Int32) -> Bool = { _ in true }

    @Test func parsesTheHookFile() {
        #expect(CodeStatus.parse("tool 1800000000\n", pid: 42) == LiveSession(pid: 42, mood: .tool, time: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(CodeStatus.parse("permission 1800000000", pid: 7)?.mood == .permission)
        #expect(CodeStatus.parse("", pid: 1) == nil)
        #expect(CodeStatus.parse("dancing 1800000000", pid: 1) == nil)
        #expect(CodeStatus.parse("tool soon", pid: 1) == nil)
        #expect(CodeStatus.parse("tool inf", pid: 1) == nil)
        #expect(CodeStatus.parse("tool nan", pid: 1) == nil)
    }

    // M1: hooks from an older install (outdated) write where Tidemark doesn't look, so only today's hooks feed the live status;
    // otherwise the status would sit on "Idle" while Claude Code works.
    @Test func onlyCurrentHooksFeedTheLiveStatus() {
        #expect(HookState.connected.feedsLiveStatus)
        #expect(!HookState.outdated.feedsLiveStatus)
        #expect(!HookState.notConnected.feedsLiveStatus)
    }

    @Test func noSessionsNoMood() {
        #expect(CodeStatus.mood([], isAlive: alive, now: now) == nil)
    }

    @Test func eachMoodShowsAsWritten() {
        for mood in CodeMood.allCases {
            #expect(CodeStatus.mood([s(1, mood, ago: 2)], isAlive: alive, now: now) == mood)
        }
    }

    @Test func mostUrgentWins() {
        let sessions = [s(1, .thinking, ago: 1), s(2, .permission, ago: 5), s(3, .tool, ago: 1), s(4, .done, ago: 1)]
        #expect(CodeStatus.mood(sessions, isAlive: alive, now: now) == .permission)
        #expect(CodeStatus.mood([s(1, .idle, ago: 1), s(2, .done, ago: 1)], isAlive: alive, now: now) == .done)
    }

    @Test func doneTurnsIdleAfterTenSeconds() {
        #expect(CodeStatus.mood([s(1, .done, ago: 9.9)], isAlive: alive, now: now) == .done)
        #expect(CodeStatus.mood([s(1, .done, ago: 10)], isAlive: alive, now: now) == .idle)
    }

    @Test func aStuckMoodTurnsIdleAfterTenMinutes() {
        #expect(CodeStatus.mood([s(1, .permission, ago: 599)], isAlive: alive, now: now) == .permission)
        #expect(CodeStatus.mood([s(1, .tool, ago: 600)], isAlive: alive, now: now) == .idle)
    }

    // Review focus: a session killed with kill -9 never sends SessionEnd.
    @Test func deadProcessesDontCount() {
        let sessions = [s(1, .permission, ago: 1), s(2, .thinking, ago: 1)]
        #expect(CodeStatus.mood(sessions, isAlive: { $0 == 2 }, now: now) == .thinking)
        #expect(CodeStatus.mood(sessions, isAlive: { _ in false }, now: now) == nil)
    }

    // Review focus: after a reboot an old pid can belong to another process.
    @Test func oldFilesExpire() {
        #expect(CodeStatus.mood([s(1, .idle, ago: 12 * 3600 - 1)], isAlive: alive, now: now) == .idle)
        #expect(CodeStatus.mood([s(1, .idle, ago: 12 * 3600)], isAlive: alive, now: now) == nil)
    }

    @Test func nextChangeIsTheEarliestTimedEdge() {
        #expect(CodeStatus.nextChange([s(1, .done, ago: 4), s(2, .tool, ago: 100)], now: now) == now.addingTimeInterval(6))
        #expect(CodeStatus.nextChange([s(1, .tool, ago: 100)], now: now) == now.addingTimeInterval(500))
        #expect(CodeStatus.nextChange([s(1, .idle, ago: 100), s(2, .done, ago: 30)], now: now) == nil)
    }

    @Test func withoutHooksTheFolderWatchDrivesIt() {
        #expect(CodeStatus.fallbackMood(claudeCodeActiveAt: nil, now: now) == nil)
        #expect(CodeStatus.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-59), now: now) == .tool)
        #expect(CodeStatus.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-65), now: now) == .done)
        #expect(CodeStatus.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-70), now: now) == nil)
    }

    // MARK: Settling a mood whose Stop hook never came (Esc mid-turn)

    func at(_ ago: TimeInterval) -> Date { now.addingTimeInterval(-ago) }

    @Test func aWorkingMoodWithRecentTranscriptWritesStays() {
        #expect(CodeStatus.settle(.tool, sessions: [s(1, .tool, ago: 120)], claudeCodeActiveAt: at(10), now: now) == .tool)
    }

    @Test func aQuietTranscriptAndOldEventRests() {
        #expect(CodeStatus.settle(.tool, sessions: [s(1, .tool, ago: 120)], claudeCodeActiveAt: at(61), now: now) == .idle)
        #expect(CodeStatus.settle(.thinking, sessions: [s(1, .thinking, ago: 120)], claudeCodeActiveAt: nil, now: now) == .idle)
    }

    @Test func permissionNeverSettles() {
        #expect(CodeStatus.settle(.permission, sessions: [s(1, .permission, ago: 120)], claudeCodeActiveAt: at(61), now: now) == .permission)
    }

    @Test func aPromptJustSentStaysThinking() {
        #expect(CodeStatus.settle(.thinking, sessions: [s(1, .thinking, ago: 3)], claudeCodeActiveAt: at(300), now: now) == .thinking)
    }

    @Test func otherMoodsAndNilPassThrough() {
        #expect(CodeStatus.settle(.done, sessions: [s(1, .done, ago: 2)], claudeCodeActiveAt: nil, now: now) == .done)
        #expect(CodeStatus.settle(nil, sessions: [], claudeCodeActiveAt: nil, now: now) == nil)
    }
}
