import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ModelsTests {
    @Test func weekLeftIsTheRest() {
        #expect(reading(week: 55, weekResetsAt: nil).weekLeft == 45)
    }

    @Test func passedSessionResetEmptiesTheSession() {
        let r = reading(week: 30, weekResetsAt: designNow.addingTimeInterval(36_000),
                        session: 40, sessionResetsAt: designNow.addingTimeInterval(-60))
        let now = r.adjusted(to: designNow)
        #expect(now.session == 0)
        #expect(now.sessionResetsAt == nil)
        #expect(now.week == 30)
    }

    @Test func passedWeekResetEmptiesTheWeek() {
        let r = reading(week: 80, weekResetsAt: designNow.addingTimeInterval(-60), scoped: ["Fable": 50])
        let now = r.adjusted(to: designNow)
        #expect(now.week == 0)
        #expect(now.weekResetsAt == nil)
        #expect(now.scoped == ["Fable": 0])
    }

    @Test func decodesOldLinesWithoutModelResets() throws {
        let line = #"{"org":"personal","scoped":{"Fable":31},"session":10,"sessionResetsAt":1791318000,"t":1791304277.5,"week":57,"weekResetsAt":1791532800}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let r = try decoder.decode(Reading.self, from: Data(line.utf8))
        #expect(r.scoped == ["Fable": 31])
        #expect(r.scopedResetsAt.isEmpty)
        #expect(r.resetsAt(scoped: "Fable") == Date(timeIntervalSince1970: 1791532800))
    }

    @Test func roundTripsModelResetsAndOmitsThemWhenEmpty() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let reset = designNow.addingTimeInterval(3600)
        var r = reading(week: 10, weekResetsAt: designNow.addingTimeInterval(7200), scoped: ["Fable": 5])
        #expect(!String(decoding: try encoder.encode(r), as: UTF8.self).contains("scopedResetsAt"))
        r.scopedResetsAt = ["Fable": reset]
        let back = try decoder.decode(Reading.self, from: try encoder.encode(r))
        #expect(back == r)
        #expect(back.resetsAt(scoped: "Fable") == reset)
    }

    @Test func aModelLimitWithItsOwnPassedResetEmptiesAlone() {
        var r = reading(week: 40, weekResetsAt: designNow.addingTimeInterval(36_000), scoped: ["Fable": 50, "Atlas": 20])
        r.scopedResetsAt = ["Fable": designNow.addingTimeInterval(-60)]
        let now = r.adjusted(to: designNow)
        #expect(now.scoped == ["Fable": 0, "Atlas": 20])
        #expect(now.scopedResetsAt.isEmpty)
        #expect(now.week == 40)
    }
}
