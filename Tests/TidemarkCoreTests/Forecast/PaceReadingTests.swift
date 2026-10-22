import Testing
import Foundation
@testable import TidemarkCore

@Suite struct PaceReadingSuite {
    static let reset = local(2026, 10, 11, 9)
    /// Half the week gone.
    static let half = reset.addingTimeInterval(-84 * 3600)

    static func pace(_ used: Double, now: Date = half) -> PaceReading? {
        PaceReading.make(reading: reading(week: used, weekResetsAt: reset, at: now), now: now)
    }

    @Test func usedOverTheEvenShareSoFar() throws {
        let fast = try #require(Self.pace(90))
        #expect(near(fast.multiple, 1.8, 0.001))
        #expect(fast.text == "1.8× even")
        #expect(fast.level == .fast)
    }

    @Test func levelsChangeAtTheirEdges() throws {
        #expect(try #require(Self.pace(42)).level == .light)      // 0.84, shown 0.8
        #expect(try #require(Self.pace(43)).level == .even)       // 0.86, shown 0.9
        #expect(try #require(Self.pace(57)).level == .even)       // 1.14, shown 1.1
        #expect(try #require(Self.pace(58)).level == .fast)       // 1.16, shown 1.2
        #expect(try #require(Self.pace(20)).text == "0.4× even")
    }

    @Test func levelWords() {
        #expect(PaceLevel.light.label == "Light")
        #expect(PaceLevel.even.label == "Even")
        #expect(PaceLevel.fast.label == "Fast")
    }

    @Test func nilBeforeTwoPercentOfTheWeekOrWithoutOne() {
        let early = Self.reset.addingTimeInterval(-168 * 3600 + 3 * 3600)   // 1.8% in
        #expect(Self.pace(5, now: early) == nil)
        let later = Self.reset.addingTimeInterval(-168 * 3600 + 3.5 * 3600) // 2.08% in
        #expect(Self.pace(5, now: later) != nil)
        #expect(PaceReading.make(reading: reading(week: 0, weekResetsAt: nil), now: designNow) == nil)
        #expect(Self.pace(10, now: Self.reset.addingTimeInterval(60)) == nil)
    }

    @Test func theWordAlwaysAgreesWithTheShownNumber() throws {
        for used in stride(from: 20.0, through: 80.0, by: 0.5) {
            let pace = try #require(Self.pace(used))
            let shown = try #require(Double(pace.text.split(separator: "×")[0]))
            switch pace.level {
            case .light: #expect(shown <= 0.8, "\(pace.text) is Light")
            case .even: #expect(shown >= 0.9 && shown <= 1.1, "\(pace.text) is Even")
            case .fast: #expect(shown >= 1.2, "\(pace.text) is Fast")
            }
        }
    }
}
