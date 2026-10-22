import AppKit
import SwiftUI
import TidemarkCore

/// The shared building blocks (state shapes, the status glyph, the week ring), on their own.
enum SharedShots: ShotProvider {
    static var section: (title: String, about: String) {
        ("Shared pieces", "Views several screens share, drawn on their own on a tile: `shared-states-*` (every state mark, filled, hollow for an old reading, and couldn't read), `shared-glyphs-*` (Claude Code's status glyphs with their words), `shared-rings-*` (the week ring at 18, 30 and 46 points for 0, 58, 81 and 100 percent) and `shared-ring-first-read-*` (a ring whose first read was on day 4), then the sky pieces: `shared-tide-sky-*` (the sky for the widget, with and without the moon, the details card and the Usage page), `shared-tide-water-*` (a plan slot's water in both styles for Personal 58% fine, Harbor Labs 81% running out and Harbor Labs out, wide and narrow), `shared-forecast-pie-*` (the week pie at 64, 40 and 18 points), `shared-five-hour-line-*` and `shared-status-chip-*` (every mood as the chip and as the corner badge).")
    }

    @MainActor static func shots(_ stage: RenderStage) -> [Shot] {
        func shot(_ name: String, _ about: String, _ view: @escaping () -> some View) -> Shot {
            Shot(screen: "shared", state: name, about: about, byLook: false) { dark in
                Renderer.picture(view().padding(18).background(Palette.tile), dark: dark)
            }
        }
        return [
            shot("states", "Each state's mark: filled (fine, runs out early, out), hollow for an old reading, and couldn't read", { states }),
            shot("glyphs", "Claude Code's five status glyphs with their words; Needs you in blue", { glyphs }),
            shot("rings", "The week ring at 18, 30 and 46 points, used 0, 58, 81 and 100 percent, now-tick at 64 percent", { rings }),
            shot("tide-sky", "TideSky: the widget's sky without and with the moon, the details card's sky and the Usage page's, dawn in light and dusk in dark", { tideSky }),
            shot("tide-water", "TideWater in both styles (level, over the week) for Personal 58% fine, Harbor Labs 81% running out and Harbor Labs out, at slot width and narrow", { tideWater }),
            shot("forecast-pie", "ForecastPie at 64, 40 and 18 points for the same three plans, and an old reading", { forecastPies }),
            shot("five-hour-line", "FiveHourLine at 0, 12, 34 and 100 percent, with and without the now knob", { fiveHourLines }),
            shot("status-chip", "StatusChip for each mood: the chip, and the compact corner badge", { statusChips }),
            shot("ring-first-read", "A 46-point ring at 58 percent whose first reading was on day 4: the days before it stay empty", {
                WeekRing(used: 58, elapsed: 64, state: .fine, size: 46, firstReadDay: 3)
            }),
        ]
    }

    private static let stateNames: [(PlanState?, String)] = [
        (.fine, "Fine"), (.runsOutEarly, "Runs out early"), (.out, "Out"), (nil, "Couldn't read"),
    ]

    private static var states: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([false, true], id: \.self) { hollow in
                HStack(spacing: 22) {
                    Text(hollow ? "Old reading" : "Current").font(Theme.font(11)).foregroundStyle(Palette.dim).frame(width: 84, alignment: .leading)
                    ForEach(Array(stateNames.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 6) {
                            StateShape(entry.0, hollow: hollow, size: 14)
                            Text(entry.1).font(Theme.font(12)).foregroundStyle(hollow ? Palette.dim : Palette.fg)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                Text("Sizes").font(Theme.font(11)).foregroundStyle(Palette.dim).frame(width: 70, alignment: .leading)
                ForEach([8, 10, 14, 20, 32], id: \.self) { StateShape(.runsOutEarly, size: CGFloat($0)) }
            }
        }
    }

    private static var glyphs: some View {
        HStack(alignment: .top, spacing: 26) {
            ForEach(CodeMood.allCases, id: \.self) { mood in
                VStack(spacing: 6) {
                    StatusGlyph(mood, size: 22)
                    Text(mood.word).font(Theme.font(12, .semibold))
                        .foregroundStyle(mood == .permission ? Palette.blueInk : Palette.bright)
                }
            }
            VStack(spacing: 6) {
                ZStack { Color.black; StatusGlyph(.permission, size: 20).colorScheme(.dark) }
                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
                Text("On the notch").font(Theme.font(10)).foregroundStyle(Palette.dim)
            }
        }
    }

    private static var rings: some View {
        let columns: [(Double, PlanState)] = [(0, .fine), (58, .fine), (81, .runsOutEarly), (100, .out)]
        return VStack(alignment: .leading, spacing: 14) {
            ForEach([18, 30, 46], id: \.self) { size in
                HStack(spacing: 22) {
                    Text("\(size) pt").font(Theme.font(11)).foregroundStyle(Palette.dim).frame(width: 40, alignment: .leading)
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                        WeekRing(used: c.0, elapsed: 64, state: c.1, size: CGFloat(size))
                    }
                    WeekRing(used: nil, elapsed: 64, state: nil, size: CGFloat(size))
                    WeekRing(used: 58, elapsed: 64, state: .fine, size: CGFloat(size), dimmed: true)
                }
            }
            Text("Columns: 0, 58, 81, 100 percent, couldn't read, old reading").font(Theme.font(10)).foregroundStyle(Palette.dim)
        }
    }

    // MARK: The sky pieces

    private static func onSky<V: View>(_ kind: TideSky.Kind, width: CGFloat? = nil, height: CGFloat? = nil, @ViewBuilder _ content: () -> V) -> some View {
        content().padding(10).frame(width: width, height: height).background(TideSky(kind))
    }

    private static func label(_ text: String) -> some View {
        Text(text).font(Theme.font(11)).foregroundStyle(Palette.dim)
    }

    private static var tideSky: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Widget, 640 x 86, with the moon")
            TideSky(.widget(moon: true)).frame(width: 640, height: 86).clipShape(RoundedRectangle(cornerRadius: 10))
            label("Widget, 236 x 86, no moon")
            TideSky(.widget(moon: false)).frame(width: 236, height: 86).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    label("Card, 300 x 420")
                    TideSky(.card).frame(width: 300, height: 420).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("Page, 600 x 420")
                    TideSky(.page).frame(width: 600, height: 420).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private static func slot(_ sample: TideSample, style: TideStyle, narrow: Bool) -> some View {
        let w: CGFloat = narrow ? 118 : 250
        let verdict = narrow ? sample.verdict.short.joined(separator: " ") : sample.verdict.line
        return ZStack(alignment: .topLeading) {
            TideWater(chart: sample.chart, style: style, locked: sample.chart.lockedFrom != nil, isOld: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    StateShape(sample.state, size: 7)
                    Text(sample.name.uppercased()).font(Theme.font(10, .semibold)).tracking(0.7)
                }
                Spacer(minLength: 0)
                (Text("\(sample.pie.used)").font(.system(size: narrow ? 20 : 25, weight: .light)) + Text("%").font(.system(size: 12)))
                Text(verdict).font(Theme.font(narrow ? 11 : 13)).lineLimit(1)
            }
            .padding(narrow ? 9 : 12)
        }
        .frame(width: w, height: 86).clipped()
    }

    private static var tideWater: some View {
        TideWaterSheet()
    }

    private struct TideWaterSheet: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TideStyle.allCases, id: \.self) { style in
                    label(style.label)
                    onSky(.widget(moon: false)) {
                        HStack(spacing: 0) {
                            ForEach(TideSample.all) { SharedShots.slot($0, style: style, narrow: false) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    onSky(.widget(moon: false)) {
                        HStack(spacing: 0) {
                            ForEach(TideSample.all) { SharedShots.slot($0, style: style, narrow: true) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                label("Old reading: the water dims to 55%")
                onSky(.widget(moon: false)) {
                    ZStack {
                        TideWater(chart: TideSample.all[1].chart, style: .level, locked: true, isOld: true)
                    }.frame(width: 250, height: 86)
                }.clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private static var forecastPies: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([64, 40, 18] as [CGFloat], id: \.self) { size in
                label("\(Int(size)) pt")
                onSky(.card) {
                    HStack(spacing: 22) {
                        ForEach(TideSample.all) { ForecastPie(pie: $0.pie, size: size, isOld: false) }
                        ForecastPie(pie: TideSample.all[0].pie, size: size, isOld: true)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private static var fiveHourLines: some View {
        onSky(.widget(moon: false), width: 300) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach([(0.0, nil), (12, 44), (34, nil), (100, 70)] as [(Double, Double?)], id: \.0) { used, now in
                    HStack(spacing: 6) {
                        Text("5h").font(Theme.font(10.5))
                        FiveHourLine(used: used, now: now)
                        Text("\(Int(used))%").font(Theme.font(10.5, .semibold))
                    }
                }
            }.padding(8)
        }.clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private static var statusChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            onSky(.widget(moon: false), width: 560) {
                HStack(spacing: 10) { ForEach(CodeMood.allCases, id: \.self) { StatusChip(mood: $0, compact: false) } }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
            onSky(.widget(moon: false), width: 560) {
                HStack(spacing: 14) { ForEach(CodeMood.allCases, id: \.self) { StatusChip(mood: $0, compact: true) } }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
            onSky(.card, width: 560) {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        ForecastPie(pie: TideSample.all[0].pie, size: 40, isOld: false)
                        StatusChip(mood: .permission, compact: true).offset(x: 5, y: 4)
                    }
                    ZStack(alignment: .bottomTrailing) {
                        ForecastPie(pie: TideSample.all[1].pie, size: 40, isOld: false)
                        StatusChip(mood: .thinking, compact: true).offset(x: 5, y: 4)
                    }
                }.padding(8)
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Sample plans for the sky pieces' pictures, built with Core's real types from hand-made readings: the
/// mockups' Personal (58%, fine), Harbor Labs (81%, runs out Thursday night) and Harbor Labs out.
struct TideSample: Identifiable {
    var id: String { org }
    var org: String
    var name: String
    var state: PlanState
    var pie: WeekPie
    var chart: LeftChart
    var verdict: PlanVerdict

    static let all: [TideSample] = [
        make("Personal", .fine, org: "personal", used: 58, nowDay: 5.32, points: [(1, 12), (2, 18), (3, 26), (4, 38), (5, 52)]),
        make("Harbor Labs", .runsOutEarly, org: "harbor", used: 81, nowDay: 3.44, points: [(1, 30), (2, 52), (3, 74)]),
        make("Harbor Labs", .out, org: "harbor-out", used: 100, nowDay: 6.9, points: [(1, 22), (2, 38), (3, 55), (4, 75), (5.88, 100)]),
    ]

    /// `points` are (days into the week, % used); the last reading is `used` at `nowDay`.
    private static func make(_ name: String, _ state: PlanState, org: String, used: Double, nowDay: Double,
                             points: [(Double, Double)]) -> TideSample {
        let day: TimeInterval = 86_400
        let reset = Date(timeIntervalSince1970: 1_792_000_000)
        let start = reset.addingTimeInterval(-7 * day)
        func reading(_ d: Double, _ week: Double) -> Reading {
            Reading(time: start.addingTimeInterval(d * day), org: org, session: 0, sessionResetsAt: nil, week: week, weekResetsAt: reset)
        }
        let history = points.map { reading($0.0, $0.1) }
        let current = reading(nowDay, used)
        let now = current.time
        let pie = WeekPie.make(reading: current, history: history, now: now)!
        let chart = LeftChart.make(reading: current, history: history, now: now)!
        let forecast = Pace.forecast(current, history: history, now: now)
        let verdict = PlanVerdict.make(reading: current, forecast: forecast, state: state, now: now, formatting: Formatting(calendar: Calendar(identifier: .gregorian), twentyFourHour: false))
        return TideSample(org: org, name: name, state: state, pie: pie, chart: chart, verdict: verdict)
    }
}
