import Foundation
import Testing
@testable import TidemarkCore

/// Shaped like a real claude.ai usage response (placeholder values only).
let usageJSON = """
{
  "five_hour": {"utilization": 52, "resets_at": "2026-10-06T15:20:00.408772+00:00"},
  "seven_day": {"utilization": 55, "resets_at": "2026-10-09T08:00:00.408798+00:00"},
  "seven_day_opus": null,
  "extra_usage": {"is_enabled": true, "monthly_limit": 0},
  "limits": [
    {"kind": "session", "group": "session", "percent": 52, "severity": "normal",
     "resets_at": "2026-10-06T15:20:00.408772+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_all", "group": "weekly", "percent": 55, "severity": "normal",
     "resets_at": "2026-10-09T08:00:00.408798+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 31, "severity": "normal",
     "resets_at": "2026-10-09T08:00:00.409004+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
  ]
}
"""

let orgsJSON = """
[
  {"uuid": "00000000-0000-4000-8000-000000000001", "name": "Personal", "billing_type": "stripe_subscription", "capabilities": ["chat"]},
  {"uuid": "00000000-0000-4000-8000-000000000002", "name": "Harbor Labs", "billing_type": "stripe_subscription", "capabilities": ["chat"]},
  {"uuid": "00000000-0000-4000-8000-000000000003", "name": "Personal", "billing_type": null, "capabilities": ["chat"]}
]
"""

@Suite struct UsageParserTests {
    @Test func parsesLimits() throws {
        let r = try UsageParser.reading(from: Data(usageJSON.utf8), org: "personal", at: designNow)
        #expect(r.session == 52)
        #expect(r.sessionResetsAt == utc("2026-10-06T15:20:00Z"))
        #expect(r.week == 55)
        #expect(r.weekResetsAt == utc("2026-10-09T08:00:00Z"))
        #expect(r.scoped == ["Fable": 31])
        #expect(r.org == "personal")
        #expect(r.time == designNow)
    }

    @Test func roundsResetTimesToTheMinute() {
        #expect(UsageParser.parseDate("2026-10-08T00:59:59.702797+00:00") == utc("2026-10-08T01:00:00Z"))
        #expect(UsageParser.parseDate("2026-10-08T01:00:00Z") == utc("2026-10-08T01:00:00Z"))
        #expect(UsageParser.parseDate("not a date") == nil)
    }

    @Test func sessionWithoutWindowHasNoReset() throws {
        let json = """
        {"limits": [
          {"kind": "session", "percent": 0, "resets_at": null},
          {"kind": "weekly_all", "percent": 95, "resets_at": "2026-10-08T00:59:59.702797+00:00"}
        ]}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "harbor", at: designNow)
        #expect(r.session == 0)
        #expect(r.sessionResetsAt == nil)
        #expect(r.week == 95)
    }

    // Review Focus 1
    @Test func weekNotStartedHasNoReset() throws {
        let json = #"{"limits": [{"kind": "weekly_all", "percent": 0, "resets_at": null}]}"#
        let r = try UsageParser.reading(from: Data(json.utf8), org: "harbor", at: designNow)
        #expect(r.week == 0)
        #expect(r.weekResetsAt == nil)
    }

    // Final review #6: a reset time we can't read is an error, not "hasn't started".
    @Test func unreadableResetTimeIsAnError() {
        let json = #"{"limits": [{"kind": "weekly_all", "percent": 55, "resets_at": "next friday"}]}"#
        #expect(throws: UsageParserError.unreadableResetTime) {
            try UsageParser.reading(from: Data(json.utf8), org: "personal", at: designNow)
        }
    }

    @Test func fallsBackToOlderShape() throws {
        let json = """
        {"five_hour": {"utilization": 12, "resets_at": "2026-10-06T15:20:00+00:00"},
         "seven_day": {"utilization": 40, "resets_at": "2026-10-09T08:00:00+00:00"}}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "personal", at: designNow)
        #expect(r.session == 12)
        #expect(r.week == 40)
        #expect(r.weekResetsAt == utc("2026-10-09T08:00:00Z"))
    }

    // Review Focus 4
    @Test func htmlIsNotJSON() {
        #expect(throws: UsageParserError.notJSON) {
            try UsageParser.reading(from: Data("<html>Just a moment...</html>".utf8), org: "personal", at: designNow)
        }
        #expect(throws: UsageParserError.notJSON) {
            try UsageParser.orgs(from: Data("<html></html>".utf8))
        }
    }

    @Test func missingWeeklyLimitThrows() {
        #expect(throws: UsageParserError.noWeeklyLimit) {
            try UsageParser.reading(from: Data(#"{"limits": []}"#.utf8), org: "personal", at: designNow)
        }
    }

    // Review Focus 5
    @Test func clampsPercentages() throws {
        let json = """
        {"limits": [
          {"kind": "session", "percent": -3, "resets_at": null},
          {"kind": "weekly_all", "percent": 140, "resets_at": "2026-10-09T08:00:00+00:00"},
          {"kind": "weekly_scoped", "percent": 120, "resets_at": null, "scope": {"model": {"display_name": "Fable"}}}
        ]}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "personal", at: designNow)
        #expect(r.session == 0)
        #expect(r.week == 100)
        #expect(r.scoped["Fable"] == 100)
    }

    @Test func parsesOrgs() throws {
        let orgs = try UsageParser.orgs(from: Data(orgsJSON.utf8))
        #expect(orgs.map(\.name) == ["Personal", "Harbor Labs", "Personal"])
        #expect(orgs[0].id == "00000000-0000-4000-8000-000000000001")
        #expect(orgs[0].billingType == "stripe_subscription")
        #expect(orgs[2].billingType == nil)
    }

    @Test func keepsEachModelLimitsReset() throws {
        let r = try UsageParser.reading(from: Data(usageJSON.utf8), org: "personal", at: designNow)
        #expect(r.scopedResetsAt == ["Fable": utc("2026-10-09T08:00:00Z")])
    }

    @Test func newShapeOfAnswerSaysClaudeAiChanged() {
        let body = Data(("<html>Order 12345 for ada@example.com " + String(repeating: "x", count: 300) + "</html>").utf8)
        let problem = UsageParser.problem(for: UsageParserError.notJSON, answer: body, status: 200)
        guard case .changedShape(let details) = problem else { Issue.record("not changedShape"); return }
        #expect(details.hasPrefix("HTTP 200: <html>Order ##### for <email> xxx"))
        #expect(!details.contains("@"))
        #expect(!details.contains { $0.isNumber && $0 != "2" && $0 != "0" })
        #expect(UsageParser.problem(for: UsageParserError.noWeeklyLimit, answer: body) == .noWeeklyLimit)
    }

    // The org list holds the account's name and email: a list that can't be read says what shape came
    // back without them.
    @Test func masksStringValuesAndEmailsButKeepsTheShape() {
        let body = Data(#"{"uuid":"abc-123","name":"Ada Lovelace","email":"ada@example.com","ok":true,"n":42}"#.utf8)
        guard case .changedShape(let details) = UsageParser.problem(for: UsageParserError.notJSON, answer: body, status: 200) else {
            Issue.record("not changedShape"); return
        }
        #expect(details.hasPrefix("HTTP 200: "))
        #expect(!details.contains("Ada") && !details.contains("Lovelace") && !details.contains("example.com") && !details.contains("abc"))
        #expect(details.contains("\"uuid\"") && details.contains("\"name\"") && details.contains("true"))
        #expect(!details.contains { $0.isNumber && $0 != "2" && $0 != "0" })
        let plain = UsageParser.shapeDetails(status: 502, body: Data("Mail ada@example.com or bob.smith+x@example.com now".utf8))
        #expect(plain == "HTTP 502: Mail <email> or <email> now")
    }

    @Test func anOrgListThatIsntAListSaysWhatCameBack() {
        let answer = Data(#"{"error":"nope"}"#.utf8)
        do {
            _ = try UsageParser.orgs(from: answer)
            Issue.record("should have thrown")
        } catch {
            guard case .changedShape(let details) = UsageParser.problem(for: error, answer: answer) else { Issue.record("not changedShape"); return }
            #expect(details.hasPrefix("HTTP 200: "))
        }
    }
}
