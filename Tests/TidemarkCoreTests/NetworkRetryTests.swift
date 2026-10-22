import Testing
@testable import TidemarkCore

@Suite struct NetworkRetryTests {
    @Test func backoffGrowsThenStaysAtTheLongestWait() {
        var retry = NetworkRetry()
        let waits = (0..<7).map { _ in retry.failed() }
        #expect(waits == [30, 60, 120, 300, 600, 600, 600])
    }

    @Test func backoffResetsOnWakeAndNetworkReturn() {
        var retry = NetworkRetry()
        _ = retry.failed(); _ = retry.failed(); _ = retry.failed()
        retry.wake()
        let afterWake = retry.failed()
        #expect(afterWake == 30)
        _ = retry.failed()
        let refreshNow = retry.networkReturned()
        #expect(refreshNow)
        let afterReturn = retry.failed()
        #expect(afterReturn == 30)
        retry.succeeded()
        #expect(retry.failures == 0)
    }

    @Test func aNetworkThatNeverFailedNeedsNoExtraRefresh() {
        var retry = NetworkRetry()
        let refreshNow = retry.networkReturned()
        #expect(!refreshNow)
    }

    // The poller's schedule: 3 minutes while it works, the retry steps after a failure, and never
    // quicker than 3 minutes after a bot check or a refusal.
    @Test func theNextReadWaitsByHowTheLastOneWent() {
        var retry = NetworkRetry()
        #expect(retry.next(after: .succeeded) == 180)
        #expect(retry.next(after: .failed(.offline)) == 30)
        #expect(retry.next(after: .failed(.offline)) == 60)
        #expect(retry.next(after: .failed(.blocked)) == 180)
        #expect(retry.next(after: .failed(.refused)) == 300)
        #expect(retry.next(after: .succeeded) == 180)
        #expect(retry.failures == 0)
        #expect(retry.next(after: .failed(.refused)) == 180)
        #expect(retry.next(after: .failed(.http(503))) == 60)
    }

    // "No connection · trying again every minute" is true: offline never waits longer than 60 seconds,
    // while the other errors keep backing off.
    @Test func offlineRetriesAtLeastEveryMinute() {
        var retry = NetworkRetry()
        let offline = (0..<6).map { _ in retry.next(after: .failed(.offline)) }
        #expect(offline == [30, 60, 60, 60, 60, 60])
        var other = NetworkRetry()
        let http = (0..<6).map { _ in other.next(after: .failed(.http(503))) }
        #expect(http == [30, 60, 120, 300, 600, 600])
    }
}
