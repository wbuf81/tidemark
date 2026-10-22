import Foundation
import Testing
@testable import TidemarkCore

@Suite struct PlanStateTests {
    func reading(session: Double = 10, weekLeft: Double = 50) -> Reading {
        Reading(time: Date(timeIntervalSince1970: 0), org: "demo", session: session, sessionResetsAt: nil,
                week: 100 - weekLeft, weekResetsAt: nil)
    }

    func forecast(runsOutEarlyByHours: Double? = nil, unused: Double = 0) -> WeekForecast {
        WeekForecast(used: 50, hoursLeft: 80, elapsedFraction: 0.5, pacePerHour: 1, forecastAtReset: 100 - unused, unused: unused,
                     runsOutEarlyByHours: runsOutEarlyByHours, runsOutAt: nil, useItAllPerHour: 1, byMidnight: 0)
    }

    @Test func weekLeftBelowTenIsOut() {
        #expect(PlanStates.state(reading(weekLeft: 6), nil) == .out)
    }

    @Test func sessionAt96IsOut() {
        #expect(PlanStates.state(reading(session: 96), nil) == .out)
    }

    @Test func runningOutEarlyWarns() {
        #expect(PlanStates.state(reading(), forecast(runsOutEarlyByHours: 3)) == .runsOutEarly)
    }

    @Test func sessionAt84Warns() {
        #expect(PlanStates.state(reading(session: 84), nil) == .runsOutEarly)
    }

    @Test func onPaceWithUnusedTimeIsFine() {
        #expect(PlanStates.state(reading(), forecast(unused: 20)) == .fine)
    }

    @Test func noForecastIsFine() {
        #expect(PlanStates.state(reading(session: 10), nil) == .fine)
    }
}
