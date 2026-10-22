import Foundation
import Testing
@testable import TidemarkCore

@Suite struct DisplayNamesTests {
    func shortNames(_ names: [String]) -> [String] {
        DisplayNames.short(names.map { Org(id: $0, name: $0) }).map(\.name)
    }

    @Test func dropsLeadingWordsEveryOrgShares() {
        #expect(shortNames(["Team Rocket Personal", "Team Rocket Harbor Labs"]) == ["Personal", "Harbor Labs"])
    }

    @Test func keepsNamesWithNothingInCommon() {
        #expect(shortNames(["Personal", "Harbor Labs"]) == ["Personal", "Harbor Labs"])
        #expect(shortNames(["Team Personal", "Club Harbor Labs"]) == ["Team Personal", "Club Harbor Labs"])
    }

    @Test func neverEmptiesAName() {
        #expect(shortNames(["Team Rocket", "Team Rocket Harbor Labs"]) == ["Rocket", "Rocket Harbor Labs"])
        #expect(shortNames(["Personal", "Personal"]) == ["Personal", "Personal"])
    }

    @Test func singleOrgKeepsItsName() {
        #expect(shortNames(["Team Rocket Personal"]) == ["Team Rocket Personal"])
    }

    @Test func keepsIdsAndBilling() {
        let orgs = DisplayNames.short([Org(id: "a", name: "Team Personal", billingType: "x"), Org(id: "b", name: "Team Harbor Labs")])
        #expect(orgs[0] == Org(id: "a", name: "Personal", billingType: "x"))
    }
}
