import Foundation

/// The Forecast headline: a title, at most one subtitle, and the row it is about.
public struct Headline: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    /// The row to select when the window opens; nil means the first.
    public var focus: LimitID?

    init(title: String, subtitle: String?, focus: LimitID?) {
        self.title = title
        self.subtitle = subtitle
        self.focus = focus
    }
}

/// One of the detail pane's three numbers. Never amber: amber only means "runs out before it resets" (D6).
public struct DetailStat: Equatable, Sendable {
    public var label: String
    public var value: String
    /// A smaller line under the value, when the label alone would wrap.
    public var note: String? = nil
}

/// The Insights window's sentences, kept here so they can be tested.
public enum UsageCopy {
    /// The row's label: the org's name on its week row, else "Fable" or "5 hours".
    public static func rowLabel(_ kind: LimitKind, org name: String) -> String {
        switch kind {
        case .week: name
        case .model(let model): model
        case .session: "5 hours"
        }
    }

    /// The limit in a sentence: "Personal", "Personal's Fable limit", "Personal's 5-hour window".
    static func limitName(_ kind: LimitKind, org name: String) -> String {
        switch kind {
        case .week: name
        case .model(let model): "\(name)’s \(model) limit"
        case .session: "\(name)’s 5-hour window"
        }
    }

    /// What would go unused: "Harbor Labs's week", "Harbor Labs's Fable limit".
    static func unusedName(_ kind: LimitKind, org name: String) -> String {
        kind == .week ? "\(name)’s week" : limitName(kind, org: name)
    }

    /// "week", "Fable", "5 hours"
    static func kindWord(_ kind: LimitKind) -> String {
        switch kind {
        case .week: "week"
        case .model(let model): model
        case .session: "5 hours"
        }
    }

    /// The headline over the rows. First match wins: nothing fresh; a week or model limit runs
    /// out an hour or more early; one would leave `onPaceUnused` or more unused; all on pace.
    /// Stale rows don't count.
    public static func headline(_ rows: [ForecastRow], names: [String: String], signedIn: Bool, problem: String?,
                                now: Date, formatting: Formatting, _ t: Thresholds = Thresholds()) -> Headline {
        let fresh = rows.filter { !$0.isStale }
        guard !fresh.isEmpty else {
            return Headline(title: rows.isEmpty ? "No readings yet" : "No fresh readings",
                            subtitle: signedIn ? problem : "Sign in to claude.ai to see the forecast", focus: nil)
        }
        func name(_ row: ForecastRow) -> String { limitName(row.id.kind, org: names[row.id.org] ?? row.id.org) }
        func time(_ date: Date) -> String { formatting.dayTime(date, now: now) }
        let weekly = fresh.filter { $0.id.kind != .session }
        let out = weekly.filter { ($0.lockedHours ?? 0) >= 1 }.sorted { $0.runsOutAt! < $1.runsOutAt! }
        let wasting = weekly.filter { $0.id.kind == .week && $0.runsOutAt == nil && ($0.forecast.map { $0.unused >= t.onPaceUnused } ?? false) }
            .sorted { $0.forecast!.unused > $1.forecast!.unused }

        var headline: Headline
        if let first = out.first, let reset = first.resetsAt, let outAt = first.runsOutAt {
            let locked = Formatting.duration(first.lockedHours! * 3600)
            if out.count > 1 {
                headline = Headline(title: "\(out.count) limits run out before reset",
                                    subtitle: first.used >= 100 ? "\(name(first)) is out until \(time(reset))"
                                        : "\(name(first)) first, \(time(outAt)), then locked \(locked)",
                                    focus: first.id)
            } else if first.used >= 100 {
                headline = Headline(title: "\(name(first)) is out until \(time(reset))", subtitle: nil, focus: first.id)
            } else {
                headline = Headline(title: "\(name(first)) runs out \(time(outAt)), \(locked) before reset", subtitle: nil, focus: first.id)
            }
        } else if let top = wasting.first, let f = top.forecast, let reset = top.resetsAt {
            headline = Headline(title: "About \(Formatting.percent(f.unused)) of \(unusedName(top.id.kind, org: names[top.id.org] ?? top.id.org)) would go unused",
                                subtitle: "At your pace it reaches ~\(Formatting.percent(f.forecastAtReset)) by \(time(reset)).",
                                focus: top.id)
        } else {
            headline = Headline(title: "Every limit is on pace to be used by reset", subtitle: nil, focus: nil)
        }

        if headline.subtitle == nil {
            if let other = wasting.first(where: { $0.id.org != headline.focus?.org }), let f = other.forecast, let reset = other.resetsAt {
                headline.subtitle = "\(name(other)) would leave about \(Formatting.percent(f.unused)) unused at \(time(reset))."
            } else if let session = fresh.filter({ $0.id.kind == .session && ($0.runsOutAt.map { $0.timeIntervalSince(now) <= 3600 } ?? false) })
                        .min(by: { $0.runsOutAt! < $1.runsOutAt! }),
                      let outAt = session.runsOutAt {
                headline.subtitle = session.used >= 100
                    ? "\(name(session)) is out until \(time(session.resetsAt ?? outAt))."
                    : "\(name(session)) runs out at \(time(outAt))."
            }
        }
        return headline
    }

    /// A row as one sentence for VoiceOver.
    public static func voiceOver(_ row: ForecastRow, org name: String, now: Date, formatting: Formatting,
                                 _ t: Thresholds = Thresholds()) -> String {
        let label = "\(name), \(kindWord(row.id.kind))"
        let session = row.id.kind == .session
        guard let reset = row.resetsAt else { return "\(label): not started." }
        let resetTime = formatting.dayTime(reset, now: now)
        if let out = row.runsOutAt, let locked = row.lockedHours {
            if row.used >= 100 { return "\(label): used up until \(resetTime)." }
            return "\(label): runs out \(formatting.dayTime(out, now: now)), \(Formatting.duration(locked * 3600)) before it \(session ? "ends" : "resets") \(resetTime)."
        }
        var text = "\(label): about \(Formatting.percent(row.forecast?.forecastAtReset ?? row.used)) at \(session ? "the end" : "reset")"
        if row.id.kind == .week, let unused = row.forecast?.unused, unused >= t.onPaceUnused {
            text += ", about \(Formatting.percent(unused)) unused"
        }
        return text + ". \(session ? "Window ends" : "Resets") \(resetTime)."
    }

    /// "Personal · week", "Personal · Fable", "Personal · 5 hours"
    public static func detailTitle(_ kind: LimitKind, org name: String) -> String { "\(name) · \(kindWord(kind))" }

    /// "Used 41% in 25% of the window."
    public static func lead(_ d: LimitDetail) -> String {
        "Used \(Formatting.percent(d.used)) in \(Formatting.percent(d.elapsedFraction * 100)) of the window."
    }

    /// Pace, then when it runs out and how long it's locked, or what's left at reset and unused.
    public static func stats(_ d: LimitDetail, now: Date, formatting: Formatting, _ t: Thresholds = Thresholds()) -> [DetailStat] {
        let session = d.id.kind == .session
        // A model limit is a cap, not something to use up: no pace against use-it-all (S3.4).
        let isModel: Bool = { if case .model = d.id.kind { true } else { false } }()
        let pace = isModel ? [] : [DetailStat(label: "Pace", value: d.paceMultiple.map { String(format: "%.1f×", $0) } ?? "—",
                                              note: "vs use-it-all")]
        if let out = d.runsOutAt {
            return pace + [
                DetailStat(label: "Runs out", value: d.used >= 100 ? "Now" : formatting.dayTime(out, now: now)),
                DetailStat(label: session ? "Locked before end" : "Locked before reset",
                           value: Formatting.duration(d.resetsAt.timeIntervalSince(out)))]
        }
        let unused = d.forecast?.unused ?? 0
        return pace + [
            DetailStat(label: session ? "At end" : "At reset",
                       value: "~\(Formatting.percent(d.forecast?.forecastAtReset ?? d.used))"),
            DetailStat(label: d.id.kind == .week ? "Unused" : "Left at reset", value: unused < 0.5 ? "0%" : "~\(Formatting.percent(unused))")]
    }

    /// The bar chart's heading and its grey note.
    public static func barsTitle(_ kind: LimitKind) -> (title: String, note: String) {
        kind == .session ? ("Recent windows", "peak use") : ("Recent pace", "% used per day")
    }

    /// "Use-it-all from now: 11.2% a day"; nil for 5-hour windows.
    public static func barsCaption(_ d: LimitDetail) -> String? {
        d.perDayLine.map { String(format: "Use-it-all from now: %.1f%% a day", $0) }
    }

    /// The bar chart as one sentence for VoiceOver: "Recent pace: Wed 2, Today 13; use-it-all 3.6% a day".
    public static func barsSummary(_ d: LimitDetail, now: Date, formatting: Formatting) -> String {
        let heading = barsTitle(d.id.kind)
        let values = d.bars.map { bar in
            "\(barLabel(bar, kind: d.id.kind, now: now, formatting: formatting)) \(bar.value.map { String(Int($0.rounded())) } ?? "no data")"
                + (barWord(bar).map { " \($0)" } ?? "")
        }
        let tail = d.perDayLine.map { String(format: "use-it-all %.1f%% a day", $0) } ?? heading.note
        return "\(heading.title): \(values.joined(separator: ", ")); \(tail)"
    }

    /// The word a bar's tone says besides its pattern, for VoiceOver (D12: never colour alone).
    static func barWord(_ bar: DetailBar) -> String? {
        switch bar.tone {
        case .under: "under"
        case .over: "over"
        case .hitLimit: "full"
        default: nil
        }
    }

    /// Under the bars, when one day holds the use of several because nothing was read in between:
    /// "Thu holds 3 days of use: nothing was read on Tue or Wed." nil when every day was read (M4).
    public static func gapNote(_ d: LimitDetail, formatting: Formatting) -> String? {
        guard let i = d.bars.firstIndex(where: { $0.includesDays > 1 }) else { return nil }
        let bar = d.bars[i]
        let quiet = d.bars[max(i - (bar.includesDays - 1), 0)..<i].map { formatting.weekday($0.date) }
        let list = quiet.count > 1 ? quiet.dropLast().joined(separator: ", ") + " or " + quiet.last! : quiet.first ?? ""
        return "\(formatting.weekday(bar.date)) holds \(bar.includesDays) days of use: nothing was read on \(list)."
    }

    /// The bar chart's keys, in order, only for what the chart can show: the grey bars say what they are,
    /// today has its own key, a model limit is "within limit" and has no use-it-all line.
    public static func barKeys(_ d: LimitDetail) -> [String] {
        switch d.id.kind {
        case .session: return ["Peak", "Reached 100%", "Open window"]
        case .model: return ["Within limit", "Reached 100%", "Today so far"]
        case .week: return ["On pace", "Under", "Over", "Today so far", "Use-it-all/day"]
        }
    }

    /// What a plan or limit says when it couldn't be read: "Couldn’t read: access refused · trying again".
    public static func unreadLine(_ problem: RefreshProblem?) -> String {
        guard let problem else { return "No reading yet" }
        return "Couldn’t read: \(short(problem)) · trying again"
    }

    /// The Today box's lines, joined to their label: "Today: only 5% left…" (lower case after the colon).
    public static func todayLine(_ today: Copy.Today) -> (main: String, warning: String?) {
        ("Today: " + today.main.prefix(1).lowercased() + today.main.dropFirst(), today.warning)
    }

    /// "As of 11:32 AM", on its own line under a stale pane's subtitle.
    public static func asOfLine(_ time: Date, now: Date, formatting: Formatting) -> String {
        "As of \(formatting.dayTime(time, now: now))"
    }

    /// Under a bar: "Today", "Sat", or a 5-hour window's start, "9 AM".
    public static func barLabel(_ bar: DetailBar, kind: LimitKind, now: Date, formatting: Formatting) -> String {
        if kind == .session { return formatting.hour(bar.date) }
        return formatting.calendar.isDate(bar.date, inSameDayAs: now) ? "Today" : formatting.weekday(bar.date)
    }

    /// Under the chart: "Thu", or "1 PM" in a 5-hour window.
    public static func tickLabel(_ tick: AxisTick, kind: LimitKind, formatting: Formatting) -> String {
        kind == .session ? formatting.hour(tick.date) : formatting.weekday(tick.date)
    }
}

extension UsageCopy {
    /// A few words for the widget, which has room for little more than a caption.
    public static func short(_ problem: RefreshProblem) -> String {
        switch problem {
        case .offline: "no connection"
        case .blocked: "blocked by a bot check"
        case .changedShape: "claude.ai changed how it answers"
        case .refused: "access refused"
        case .http(let code): "claude.ai error \(code)"
        case .noWeeklyLimit: "no weekly limit"
        }
    }

    /// The Usage line after a round where some plans failed; nil when none did.
    public static func problem(_ failures: [UsageRound.Failure], shown: Int) -> String? {
        guard let first = failures.first else { return nil }
        let orgs = failures.map(\.org)
        guard failures.count < shown else { return problem(first.problem, orgs: orgs) }
        return "Couldn’t read \(names(orgs)): \(short(first.problem))."
    }

    /// The Usage line when nothing could be read. `orgs` names who it failed for, when known.
    public static func problem(_ problem: RefreshProblem, orgs: [Org] = []) -> String {
        let retry = "Trying again in a few minutes."
        switch problem {
        case .offline: return "Can’t reach claude.ai. \(retry)"
        case .blocked: return "claude.ai’s bot check stopped Tidemark. \(retry)"
        case .http(let code): return "claude.ai answered with error \(code). \(retry)"
        case .changedShape: return "claude.ai answered in a way Tidemark can’t read; its usage page may have changed."
        case .refused: return orgs.isEmpty ? "claude.ai refused to share usage." : "claude.ai refused to share usage for \(names(orgs))."
        case .noWeeklyLimit: return "claude.ai shows no weekly limit for \(orgs.isEmpty ? "this account" : names(orgs))."
        }
    }

    /// How to move Claude Code to another plan, in the same words everywhere switch advice shows
    /// (B21). With a `reason`, it comes first: "Harbor Labs is nearly out. Move Claude Code to …".
    public static func switchHow(to plan: String, reason: String? = nil) -> String {
        let how = "Move Claude Code to \(plan): run /login in Claude Code and pick \(plan)."
        return reason.map { "\($0). \(how)" } ?? how
    }

    /// The Usage pane's toggle for model limits, naming the models claude.ai reports (S4.4).
    public static func modelToggle(names: [String]) -> String {
        let all = names.sorted()
        guard !all.isEmpty else { return "Show model limits" }
        let list = all.count == 1 ? all[0] : all.dropLast().joined(separator: ", ") + " and " + all.last!
        return "Show model limits (\(list))"
    }

    /// Usage with plan limits turned off in Settings.
    public static let limitsOff = (title: "Plan limits are off",
                                   detail: "Turn them on in Settings → General to see each plan’s 5-hour window and week.",
                                   button: "Turn on…")

    /// Usage while signed out of claude.ai.
    public static let signedOut = (title: "Sign in to claude.ai",
                                   detail: "Sign in to see each plan’s 5-hour window and week.",
                                   button: "Sign in…")

    /// One plan's line in a menu. Pass the model's `now` and `formatting` so the line follows the model's
    /// clock (renders and tests fix it); left out, it follows the real one.
    public static func menuLine(_ org: Org, glance: Glance?, now: Date? = nil, formatting: Formatting? = nil) -> String {
        GlanceCopy.menuLine(org, glance: glance, now: now ?? Date(), formatting: formatting ?? Formatting())
    }

    /// "Personal", "Personal and Harbor Labs", "Personal, Harbor Labs and Lighthouse Co".
    static func names(_ orgs: [Org]) -> String {
        let all = orgs.map(\.name)
        guard all.count > 1 else { return all.first ?? "" }
        return all.dropLast().joined(separator: ", ") + " and " + all.last!
    }
}
