import Foundation

/// Everything the Usage pane needs to know about the plans, as plain values, so the pane only lays
/// them out and the words and numbers can be tested.
public struct UsageInput {
    public var orgs: [Org]
    public var latest: [String: Reading]
    public var history: [Reading]
    /// Each read plan's state (the model's `state(for:)`); a plan never read has none.
    public var states: [String: PlanState]
    public var claudeCodeOrg: String?
    /// The plan switch advice points at, when there is advice.
    public var adviceTarget: Org?
    public var signedIn: Bool
    public var limitsOff: Bool
    /// Why a plan couldn't be read in the last round.
    public var orgProblems: [String: RefreshProblem]
    public var showModelLimits: Bool
    public var showSessionLimits: Bool
    public var thresholds: Thresholds
    public var now: Date
    public var formatting: Formatting
    public var calendar: Calendar

    public init(orgs: [Org], latest: [String: Reading], history: [Reading], states: [String: PlanState],
                claudeCodeOrg: String?, adviceTarget: Org? = nil, signedIn: Bool = true, limitsOff: Bool = false,
                orgProblems: [String: RefreshProblem] = [:], showModelLimits: Bool = true,
                showSessionLimits: Bool = true, thresholds: Thresholds = Thresholds(), now: Date,
                formatting: Formatting, calendar: Calendar = .autoupdatingCurrent) {
        self.orgs = orgs
        self.latest = latest
        self.history = history
        self.states = states
        self.claudeCodeOrg = claudeCodeOrg
        self.adviceTarget = adviceTarget
        self.signedIn = signedIn
        self.limitsOff = limitsOff
        self.orgProblems = orgProblems
        self.showModelLimits = showModelLimits
        self.showSessionLimits = showSessionLimits
        self.thresholds = thresholds
        self.now = now
        self.formatting = formatting
        self.calendar = calendar
    }
}

/// What the Usage pane shows.
public struct UsageSummary: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case ready, signedOut, limitsOff
    }

    /// A number tile in the brief.
    public struct Tile: Equatable, Sendable, Identifiable {
        /// "week-<plan id>", "session-<plan id>" or "code".
        public var id: String
        public var label: String
        public var value: String
        public var caption: String
        /// The plan's state mark beside the label (week tiles); `hollow` for an old reading.
        public var state: PlanState?
        public var showsShape: Bool
        public var hollow: Bool
    }

    /// One plan's row: seven day bars (past solid, forecast outlined) and where it ends up.
    public struct Plan: Equatable, Sendable, Identifiable {
        /// The plan's id.
        public var id: String
        public var name: String
        /// nil when never read: a grey ring with a dash.
        public var state: PlanState?
        public var stale: Bool
        public var days: [DayBar]
        /// "~80%", "out Sat", "as of 10:42 AM" or why it couldn't be read.
        public var end: String
        public var voiceOver: String
    }

    public var mode: Mode
    public var headline: Headline
    /// The headline as a paragraph, with how to switch plans at the end when there is advice.
    public var lede: String
    public var switchHow: String?
    public var tiles: [Tile]
    public var plans: [Plan]
    /// Every limit of every plan the pane may show, in row order, after the model and 5-hour toggles.
    public var limits: [ForecastRow]
    /// The model limits claude.ai reports, by name, whether or not they are shown.
    public var modelNames: [String]
    public var modelToggle: String

    public static func make(_ i: UsageInput) -> UsageSummary {
        let f = i.formatting
        let names = Dictionary(i.orgs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // The headline counts every row: hiding model or 5-hour rows only changes what is drawn (S3.6).
        let all = ForecastRows.make(orgs: i.orgs.map(\.id), latest: i.latest, history: i.history,
                                    now: i.now, calendar: i.calendar)
        let headline = UsageCopy.headline(all, names: names, signedIn: i.signedIn, problem: nil, now: i.now,
                                          formatting: f, i.thresholds)
        let target = i.adviceTarget
        let how = target.map { UsageCopy.switchHow(to: $0.name) }
        var lede = [headline.title, headline.subtitle].compactMap { $0 }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        if let how { lede += " " + how }

        let modelNames = Array(Set(i.orgs.compactMap { i.latest[$0.id] }.flatMap { $0.scoped.keys })).sorted()
        let limits = all.filter { row in
            switch row.id.kind {
            case .model: i.showModelLimits
            case .session: i.showSessionLimits
            case .week: true
            }
        }
        let mode: Mode = i.limitsOff ? .limitsOff : !i.signedIn ? .signedOut : .ready
        let plans = i.orgs.map { plan($0, i) }
        return UsageSummary(mode: mode, headline: headline, lede: lede, switchHow: how,
                            tiles: tiles(i, plans), plans: plans, limits: limits, modelNames: modelNames,
                            modelToggle: UsageCopy.modelToggle(names: modelNames))
    }

    // MARK: Plans

    private static func plan(_ org: Org, _ i: UsageInput) -> Plan {
        let f = i.formatting
        guard let raw = i.latest[org.id] else {
            let line = UsageCopy.unreadLine(i.orgProblems[org.id])
            return Plan(id: org.id, name: org.name, state: nil, stale: false, days: [], end: line,
                        voiceOver: "\(org.name): " + line.prefix(1).lowercased() + line.dropFirst() + ".")
        }
        let days = ForecastRows.dayBars(org: org.id, latest: i.latest, history: i.history, now: i.now, calendar: i.calendar)
        let state = i.states[org.id]
        let row = ForecastRows.weekRow(org: org.id, latest: i.latest, history: i.history, now: i.now, calendar: i.calendar)
        let stale = !raw.isFresh(now: i.now)
        if stale {
            let end = "as of \(f.dayTime(raw.time, now: i.now))"
            return Plan(id: org.id, name: org.name, state: state, stale: true, days: days, end: end,
                        voiceOver: "\(org.name): week \(Int(raw.week.rounded())) percent used, reading from \(f.dayTime(raw.time, now: i.now)).")
        }
        let end = row.map { endText($0, i) } ?? "not started"
        let voice = row.map { UsageCopy.voiceOver($0, org: org.name, now: i.now, formatting: f, i.thresholds) } ?? "\(org.name): not started."
        return Plan(id: org.id, name: org.name, state: state, stale: false, days: days, end: end, voiceOver: voice)
    }

    /// "~80%" where it ends up, "out Sat" (or "out 9 PM" today) when it runs out, "out now" when used up.
    private static func endText(_ row: ForecastRow, _ i: UsageInput) -> String {
        guard row.resetsAt != nil else { return "not started" }
        if row.used >= 100 { return "out now" }
        if let out = row.runsOutAt {
            return "out " + i.formatting.day(out, now: i.now)
        }
        return "~\(Formatting.percent(row.forecast?.forecastAtReset ?? row.used))"
    }

    // MARK: Tiles

    private static func tiles(_ i: UsageInput, _ plans: [Plan]) -> [Tile] {
        let f = i.formatting
        var tiles: [Tile] = i.orgs.map { org in
            let plan = plans.first { $0.id == org.id }!
            let label = "\(org.name) · week"
            guard let raw = i.latest[org.id] else {
                return Tile(id: "week-\(org.id)", label: label, value: "—", caption: plan.end, state: nil, showsShape: true, hollow: false)
            }
            let reading = raw.adjusted(to: i.now)
            let row = ForecastRows.weekRow(org: org.id, latest: i.latest, history: i.history, now: i.now, calendar: i.calendar)
            var caption: String
            if let reset = reading.weekResetsAt, let row {
                let resetText = f.dayTime(reset, now: i.now)
                if row.used >= 100 {
                    caption = "out until \(resetText)"
                } else if let out = row.runsOutAt {
                    caption = "runs out \(f.dayTime(out, now: i.now)), resets \(resetText)"
                } else if let unused = row.forecast?.unused, unused >= i.thresholds.onPaceUnused {
                    caption = "~\(Formatting.percent(unused)) would go unused at reset, \(resetText)"
                } else {
                    caption = "resets \(resetText)"
                }
            } else {
                caption = "week not started"
            }
            if plan.stale { caption = "as of \(f.dayTime(raw.time, now: i.now)) · " + caption }
            return Tile(id: "week-\(org.id)", label: label, value: Formatting.percent(reading.week), caption: caption,
                        state: plan.state, showsShape: true, hollow: plan.stale)
        }
        // The 5-hour window and Claude Code's plan: the plan Claude Code is on, or the first one.
        let current = i.orgs.first { $0.id == i.claudeCodeOrg }
        if let org = current ?? i.orgs.first, let raw = i.latest[org.id] {
            let reading = raw.adjusted(to: i.now)
            let caption = reading.sessionResetsAt.map { "resets \(f.dayTime($0, now: i.now))" } ?? "not started"
            tiles.append(Tile(id: "session-\(org.id)", label: "\(org.name) · 5 hours", value: Formatting.percent(reading.session),
                              caption: caption, state: nil, showsShape: false, hollow: false))
        }
        if let current {
            let caption = i.adviceTarget != nil ? "switch suggested" : ""
            tiles.append(Tile(id: "code", label: "Claude Code is on", value: current.name, caption: caption,
                              state: nil, showsShape: false, hollow: false))
        }
        return tiles
    }
}
