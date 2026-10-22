import Foundation

/// A Mac notification's text.
public struct Notice: Equatable, Sendable {
    public var title: String
    public var body: String
    /// The plan's name, when the notice is about one plan.
    public var plan: String?

    public init(title: String, body: String, plan: String? = nil) {
        self.title = title
        self.body = body
        self.plan = plan
    }
}

extension Copy {
    /// claude.ai ended a session that worked earlier in this run; clicking it opens sign-in.
    public static let signedOutNotice = Notice(title: "Tidemark was signed out",
                                               body: "claude.ai ended the session. Click to sign in again.")

    /// How to follow switch advice: Claude Code takes its plan from its login.
    public static func howToSwitch(to target: Org) -> String {
        "Run /login in Claude Code and pick \(target.name)."
    }

    /// Switch advice changed its target: where to move Claude Code, why, and how.
    public static func switchNotice(_ advice: Advice) -> Notice {
        Notice(title: "Move Claude Code to \(advice.target.name)", body: "\(advice.reason). \(howToSwitch(to: advice.target))",
               plan: advice.target.name)
    }

    /// The plan Claude Code is on is out or nearly out for the week (S4.5): why, and when it is back.
    /// "Harbor Labs is nearly out" / "6% of its week left, back Mon 9 AM".
    public static func nearlyOutNotice(_ org: Org, left: Double, resets: Date, now: Date, formatting: Formatting) -> Notice {
        let back = formatting.dayTime(resets, now: now)
        if left <= 0 { return Notice(title: "\(org.name) is out", body: "Back \(back).", plan: org.name) }
        return Notice(title: "\(org.name) is nearly out",
                      body: "\(Formatting.percent(left)) of its week left, back \(back)", plan: org.name)
    }

    /// The plan's week will run out well before it resets: "Harbor Labs runs out Sat 2 PM" /
    /// "About 2 days before it resets."
    public static func runsOutNotice(_ org: Org, at out: Date, early: TimeInterval, now: Date, formatting: Formatting) -> Notice {
        Notice(title: "\(org.name) runs out \(formatting.dayTime(out, now: now))",
               body: "About \(roughly(early)) before it resets.", plan: org.name)
    }

    /// The plan's 5-hour window is nearly full: "Harbor Labs’s 5-hour window is at 96%" / "Back at 4:20 PM."
    public static func sessionNotice(_ org: Org, used: Double, resets: Date?, now: Date, formatting: Formatting) -> Notice {
        Notice(title: "\(org.name)’s 5-hour window is at \(Formatting.percent(used))",
               body: resets.map { "Back at \(formatting.dayTime($0, now: now))." } ?? "It opens again when you next use it.",
               plan: org.name)
    }

    /// "2 days", "5 hours", "20 minutes": a gap in the nearest whole unit, for a sentence.
    static func roughly(_ interval: TimeInterval) -> String {
        let hours = interval / 3600
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if hours >= 36 { return unit(Int((hours / 24).rounded()), "day") }
        if hours >= 1 { return unit(Int(hours.rounded()), "hour") }
        return unit(max(Int((interval / 60).rounded()), 1), "minute")
    }
}

/// Which plans to warn about, and when.
public enum Notices {
    /// What the plan Claude Code is on has to say about its week.
    public enum WeekAlert: Equatable, Sendable {
        /// Under the red threshold: nearly out (or out).
        case nearlyOut
        /// The pace runs it out the red number of hours early.
        case runsOut
    }

    /// The week's alert, if any. A plan nearly out beats one that will run out.
    public static func weekAlert(_ r: Reading, _ f: WeekForecast?, _ t: Thresholds = Thresholds()) -> WeekAlert? {
        if r.weekResetsAt != nil, r.weekLeft < t.redWeekLeft { return .nearlyOut }
        if (f?.runsOutEarlyByHours ?? 0) >= Thresholds.redRunsOutEarlyHours { return .runsOut }
        return nil
    }

    /// The 5-hour window is at the red threshold or above.
    public static func sessionNearlyFull(_ r: Reading, _ t: Thresholds = Thresholds()) -> Bool {
        r.sessionResetsAt != nil && r.session >= t.redSession
    }

    /// The plans to read: those shown, plus the hidden one Claude Code is on, so it still gets its
    /// warnings and its notification (B23). It is read, never drawn.
    public static func toRead(shown: [Org], known: [Org], claudeCodeOrg: String?) -> [Org] {
        guard let id = claudeCodeOrg, !shown.contains(where: { $0.id == id }),
              let hidden = known.first(where: { $0.id == id }) else { return shown }
        return shown + [hidden]
    }

    /// The switch-advice notice, once per target and week window of the plan Claude Code is on. A relaunch brings
    /// the same advice back, and the saved `log` keeps it from posting again.
    public static func adviceDue(_ advice: Advice, claudeCodeOrg: String?, weekResetsAt: Date?, log: inout NoticeLog) -> Notice? {
        let window = Int((weekResetsAt?.timeIntervalSince1970 ?? 0) / 60)
        guard log.firstTime("\(claudeCodeOrg ?? "-")|advice|\(advice.target.id)|\(window)") else { return nil }
        return Copy.switchNotice(advice)
    }

    /// The notice for a week alert: why, and when it is back. nil when the reading can't say.
    public static func notice(for alert: WeekAlert, org: Org, reading r: Reading, forecast f: WeekForecast?,
                              now: Date, formatting: Formatting) -> Notice? {
        switch alert {
        case .nearlyOut:
            return r.weekResetsAt.map { Copy.nearlyOutNotice(org, left: r.weekLeft, resets: $0, now: now, formatting: formatting) }
        case .runsOut:
            guard let out = f?.runsOutAt, let early = f?.runsOutEarlyByHours else { return nil }
            return Copy.runsOutNotice(org, at: out, early: early * 3600, now: now, formatting: formatting)
        }
    }

    /// What is due to post now: the plan Claude Code is on, shown or not, read from its newest reading.
    public struct Due: Equatable, Sendable {
        public var week: Notice?
        public var sessionFull: Notice?
    }

    /// The notices to post for the plan Claude Code is on (B23), each once per window: a week alert once per
    /// week window and kind, a full 5-hour window once per window. `orgs` is every plan known, shown or
    /// not. A relaunch, leaving demo mode or the 12-hour rule wobbling cannot post one twice (M2); save
    /// `log` to keep that across launches.
    public static func due(claudeCodeOrg: String?, orgs: [Org], latest: [String: Reading], history: [Reading],
                           now: Date, formatting: Formatting, thresholds t: Thresholds = Thresholds(),
                           log: inout NoticeLog) -> Due {
        var due = Due()
        guard let id = claudeCodeOrg, let org = orgs.first(where: { $0.id == id }),
              let r = latest[id]?.adjusted(to: now) else { return due }
        func minute(_ date: Date?) -> Int { Int((date?.timeIntervalSince1970 ?? 0) / 60) }
        let forecast = Pace.forecast(r, history: history, now: now)
        if let alert = weekAlert(r, forecast, t),
           log.firstTime("\(id)|\(alert)|\(minute(r.weekResetsAt))") {
            due.week = notice(for: alert, org: org, reading: r, forecast: forecast, now: now, formatting: formatting)
        }
        if sessionNearlyFull(r, t), log.firstTime("\(id)|session|\(minute(r.sessionResetsAt))") {
            due.sessionFull = Copy.sessionNotice(org, used: r.session, resets: r.sessionResetsAt, now: now, formatting: formatting)
        }
        return due
    }
}

/// The notices already posted, by plan, kind and window, so each posts once. Codable, to be kept in settings.
public struct NoticeLog: Codable, Equatable, Sendable {
    private var keys: [String] = []
    static let keep = 40

    public init() {}

    /// True the first time `key` is seen, and remembers it.
    public mutating func firstTime(_ key: String) -> Bool {
        if keys.contains(key) { return false }
        keys.append(key)
        if keys.count > Self.keep { keys.removeFirst(keys.count - Self.keep) }
        return true
    }
}
