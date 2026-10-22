import Foundation
import TidemarkCore

/// One canned state for demo mode and the showcase.
struct DemoScenario {
    var name: String
    var orgs: [Org]
    var primary: String
    var readings: [Reading]
    var claudeCodeOrg: String
    /// Claude Code is working on `claudeCodeOrg`, so it shows the in-use effect.
    var claudeCodeWorking = false
    var now: Date
    /// Claude Code's mood on `claudeCodeOrg`; nil shows none.
    var codeMood: CodeMood? = nil
}

/// invented sample data, so no real account ever shows up in a demo or a screenshot.
enum DemoData {
    static let personal = Org(id: "demo-personal", name: "Personal", billingType: "demo")
    static let harbor = Org(id: "demo-harbor-labs", name: "Harbor Labs", billingType: "demo")
    /// A third org, for `--render`'s three-org states.
    static let lighthouse = Org(id: "demo-lighthouse-co", name: "Lighthouse Co", billingType: "demo")

    /// Readings every 30 minutes from the start of each org's week (and 5-hour window) up to the
    /// scenario's moment, so charts and bars have a past. The week rises steadily with a slow
    /// wave (one period every 72 hours), which is zero now and 72 hours ago: the 72-hour pace,
    /// and so every forecast, stoplight and piece of advice, is the same as with no history. A daily
    /// swing, also zero now and 72 hours ago, makes some hours busy and others quiet, as a real week is.
    static func history(for scenario: DemoScenario) -> [Reading] {
        let now = scenario.now
        return scenario.readings.flatMap { latest -> [Reading] in
            guard let reset = latest.weekResetsAt else { return [] }
            let start = reset.addingTimeInterval(-Pace.window)
            let elapsed = now.timeIntervalSince(start)
            guard elapsed > 3600 else { return [] }
            let sessionStart = latest.sessionResetsAt.map { $0.addingTimeInterval(-5 * 3600) }
            // Counted back from now, so one reading lands exactly 72 hours ago, where the wave is zero.
            var times: [Date] = []
            var k = 1
            while now.addingTimeInterval(-1800 * Double(k)) > start {
                times.append(now.addingTimeInterval(-1800 * Double(k)))
                k += 1
            }
            times.reverse()
            return times.map { time -> Reading in
                let share = time.timeIntervalSince(start) / elapsed
                let wave = 8 * 3600 / elapsed * sin(2 * .pi * time.timeIntervalSince(now) / (72 * 3600))
                // Dips below the steady rise once a day and comes back to it every 24 hours (so at now and 72 hours ago).
                let daily = -5 * 3600 / elapsed * (1 - cos(2 * .pi * time.timeIntervalSince(now) / (24 * 3600))) / 2
                let fraction = min(max(share + wave + daily, 0), share)
                var r = Reading(time: time, org: latest.org, session: 0, sessionResetsAt: nil,
                                week: (latest.week * fraction * 10).rounded() / 10, weekResetsAt: reset,
                                scoped: latest.scoped.mapValues { ($0 * fraction * 10).rounded() / 10 },
                                scopedResetsAt: latest.scopedResetsAt)
                if let sessionStart, let sessionReset = latest.sessionResetsAt, time > sessionStart {
                    r.session = (latest.session * time.timeIntervalSince(sessionStart) / now.timeIntervalSince(sessionStart)).rounded()
                    r.sessionResetsAt = sessionReset
                }
                return r
            }
        }
    }

    /// A week calendar's week for the demo and the showcase: a sample set of projects, Monday to
    /// `now`'s day, so the week band and Insights' week window have something to draw.
    static func week(now: Date, calendar: Calendar = .current) -> WeekSummary {
        let today = (calendar.component(.weekday, from: now) + 5) % 7   // days since Monday (weekday 1 is Sunday)
        let monday = calendar.date(byAdding: .day, value: -today, to: calendar.startOfDay(for: now))!
        func day(_ i: Int) -> String {
            let d = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: i, to: monday)!)
            return String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!)
        }
        let hours = [6.5, 9.25, 7.75, 8.5, 5.0, 1.5, 0.75]
        let days = (0..<7).map { i in
            WeekSummary.Day(date: day(i), seconds: i <= today ? hours[i] * 3600 : 0, commits: i <= today ? [14, 31, 22, 18, 9, 2, 0][i] : 0)
        }
        let total = days.map(\.seconds).reduce(0, +)
        let share = [0.38, 0.24, 0.16, 0.12, 0.06, 0.04]
        let names = ["tide-tables", "lighthouse-api", "field-notes", "harbor-site", "Daily briefs", "Side projects"]
        let weeks = (1...7).reversed().map { back in
            WeekSummary.Total(start: day(-7 * back), seconds: [41, 47, 52, 38, 56, 49, 44][back - 1] * 3600)
        }
        return WeekSummary(
            generated: now,
            week: WeekSummary.Week(start: day(0), end: day(6), seconds: total, sessions: 12 + 3 * today,
                                   commits: days.map(\.commits).reduce(0, +), days: days,
                                   projects: zip(names, share).map { WeekSummary.Project(name: $0, seconds: total * $1) },
                                   previousSeconds: 44 * 3600),
            weeks: weeks + [WeekSummary.Total(start: day(0), seconds: total)],
            links: WeekSummary.Links(week: "https://example.com/week.html"))
    }

    /// Every scenario, relative to `now` so demo mode looks right on any day.
    static func scenarios(now: Date = Date()) -> [DemoScenario] {
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        // Real weekly resets land on the hour; keep the demo's looking the same.
        func onTheHour(_ hours: Double) -> Date {
            Date(timeIntervalSince1970: (at(hours).timeIntervalSince1970 / 3600).rounded() * 3600)
        }
        func r(_ org: Org, week: Double, weekReset: Double?, session: Double = 0,
               sessionReset: Double? = nil, fable: Double = 20) -> Reading {
            Reading(time: now, org: org.id, session: session, sessionResetsAt: sessionReset.map(at),
                    week: week, weekResetsAt: weekReset.map(onTheHour), scoped: ["Fable": fable])
        }
        func scenario(_ name: String, working: Bool = false, codeMood: CodeMood? = nil, _ readings: [Reading]) -> DemoScenario {
            DemoScenario(name: name, orgs: [personal, harbor], primary: personal.id,
                         readings: readings, claudeCodeOrg: personal.id, claudeCodeWorking: working, now: now, codeMood: codeMood)
        }
        return [
            scenario("green-and-red", codeMood: .tool, [
                r(personal, week: 55, weekReset: 64.5, session: 1, sessionReset: 4.8, fable: 31),
                r(harbor, week: 95, weekReset: 33.5, fable: 2),
            ]),
            scenario("switch-for-desktop-app", working: true, codeMood: .tool, [
                r(personal, week: 60, weekReset: 64.5, session: 85, sessionReset: 1.5),
                r(harbor, week: 40, weekReset: 40),
            ]),
            scenario("use-it-before-it-expires", codeMood: .permission, [
                r(personal, week: 30, weekReset: 64.5, session: 10, sessionReset: 3),
                r(harbor, week: 70, weekReset: 33.5),
            ]),
            scenario("both-low", [
                r(personal, week: 92, weekReset: 64.5, session: 40, sessionReset: 2),
                r(harbor, week: 96, weekReset: 33.5),
            ]),
            scenario("on-pace-and-fresh", [
                r(personal, week: 88, weekReset: 20, session: 30, sessionReset: 3),
                r(harbor, week: 0, weekReset: nil, fable: 0),
            ]),
        ]
    }
}
