import AppKit
import SwiftUI
import TidemarkCore

/// The details card, drawn for the sample plans.
enum DetailsShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("The details card", "The card that opens when a plan is clicked (300 points wide, on the card sky), for Personal 58% fine, Harbor Labs 81% running out and Harbor Labs out; then Harbor Labs with an old reading (\"As of\" under the header, dimmed pie) and with no history yet (\"Not enough readings yet\" in place of the chart and hours).")
    }

    private struct Sample {
        var name: String
        var reading: Reading
        var history: [Reading]
        var now: Date
    }

    private static let formatting = Formatting(calendar: Calendar(identifier: .gregorian), twentyFourHour: false)

    /// `points` are (days into the week, % used); the last reading is `used` at `nowDay`, 2 hours into a 5-hour window.
    private static func sample(_ name: String, org: String, used: Double, session: Double, nowDay: Double,
                               points: [(Double, Double)]) -> Sample {
        let day: TimeInterval = 86_400
        let reset = Date(timeIntervalSince1970: 1_792_000_000)
        let start = reset.addingTimeInterval(-7 * day)
        func reading(_ d: Double, _ week: Double) -> Reading {
            let time = start.addingTimeInterval(d * day)
            return Reading(time: time, org: org, session: session, sessionResetsAt: time.addingTimeInterval(3 * 3600),
                           week: week, weekResetsAt: reset)
        }
        let current = reading(nowDay, used)
        return Sample(name: name, reading: current, history: points.map { reading($0.0, $0.1) }, now: current.time)
    }

    private static let personal = sample("Personal", org: "personal", used: 58, session: 34, nowDay: 5.32,
                                         points: [(1, 12), (2, 18), (3, 26), (4, 38), (5, 52), (5.07, 53), (5.14, 55), (5.2, 56), (5.26, 57.5)])
    private static let harbor = sample("Harbor Labs", org: "harbor", used: 81, session: 12, nowDay: 3.44,
                                       points: [(1, 30), (2, 52), (3, 74), (3.12, 76), (3.2, 77.5), (3.28, 79), (3.36, 80)])
    private static let harborOut = sample("Harbor Labs", org: "harbor-out", used: 100, session: 62, nowDay: 6.9,
                                          points: [(1, 22), (2, 38), (3, 55), (4, 75), (5.6, 90), (5.7, 95), (5.8, 98), (5.88, 100)])

    private static func card(_ s: Sample, old: Bool = false, history: Bool = true) -> some View {
        let past = history ? s.history : []
        let now = old ? s.now.addingTimeInterval(50 * 60) : s.now
        let details = PlanDetails.make(reading: s.reading.adjusted(to: now), history: past, now: now, formatting: formatting, isOld: old)
        return PlanDetailsView(name: s.name, details: details, formatting: formatting, isOld: old)
            .padding(24).background(Palette.tile)
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        func shot(_ state: String, _ about: String, _ view: @escaping () -> some View) -> Shot {
            Shot(screen: "details", state: state, about: about, byLook: false) { dark in
                Renderer.picture(view(), dark: dark)
            }
        }
        return [
            shot("personal", "Personal, 58% used and fine: the verdict line, no locked line, pace, week, 5 hours, busiest hours", { card(personal) }),
            shot("harbor", "Harbor Labs, 81% used and running out: hours until empty, the locked line with its hatch, the dashed forecast", { card(harbor) }),
            shot("harbor-out", "Harbor Labs out: the hatch from where it ran out", { card(harborOut) }),
            shot("old-reading", "Harbor Labs with a reading 50 minutes old: \"As of\" under the header, hollow shape, dimmed pie", { card(harbor, old: true) }),
            shot("no-history", "Harbor Labs with only its latest reading: \"Not enough readings yet\" where the chart and hours would be", { card(harbor, history: false) }),
        ]
    }
}
