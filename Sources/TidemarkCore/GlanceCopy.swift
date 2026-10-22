import Foundation

/// A message the widget shows in place of plans: a title, what to do or why, and a one-word form for
/// the narrow strip (which also carries the sentence as its tooltip and VoiceOver label).
public struct GlanceMessage: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var narrow: String
    /// The button's label, nil for none.
    public var action: String?
    /// What the button does.
    public var actionKind: Action = .retry

    public enum Action: Equatable, Sendable {
        case retry
        /// Sign in to claude.ai.
        case signIn
        /// Sign out first, then sign in: the account has no plans.
        case signInAnother
    }

    /// The sentence a tooltip or VoiceOver reads.
    public var sentence: String { detail.isEmpty ? title : "\(title). \(detail)" }
}

/// The widget's, the strip's and the notch's own words (the Usage pane's are in `UsageCopy`).
public enum GlanceCopy {
    public static let signedOut = GlanceMessage(title: "Sign in to claude.ai", detail: "", narrow: "Signed out", action: "Sign in…", actionKind: .signIn)
    public static let loading = GlanceMessage(title: "Loading usage…", detail: "", narrow: "Loading…", action: nil)
    public static let noPlans = GlanceMessage(title: "No plans on this account", detail: "claude.ai shows no usage for this sign-in",
                                              narrow: "No plans", action: "Sign in with another account…", actionKind: .signInAnother)

    static let noWeeklyLimit = GlanceMessage(title: "This account has no weekly limit",
                                             detail: "claude.ai shows no weekly limit for this sign-in", narrow: "No limit", action: nil)

    /// What the widget says when nothing could be read, by why.
    public static func problem(_ problem: RefreshProblem) -> GlanceMessage {
        // Offline retries every minute at most (`NetworkRetry`); the other errors back off, so they say "soon".
        switch problem {
        case .offline:
            return GlanceMessage(title: "Can’t reach claude.ai", detail: "No connection · trying again every minute", narrow: "Offline", action: "Retry")
        case .refused:
            return GlanceMessage(title: "claude.ai refused the request", detail: "Access refused · trying again soon", narrow: "Error", action: "Retry")
        case .http(let code):
            return GlanceMessage(title: "claude.ai answered with an error (\(code))", detail: "Trying again soon",
                                 narrow: "Error", action: "Retry")
        case .blocked:
            return GlanceMessage(title: "Blocked by a bot check", detail: "claude.ai’s bot check stopped Tidemark",
                                 narrow: "Blocked", action: "Retry")
        case .changedShape:
            return GlanceMessage(title: "claude.ai changed how it answers", detail: "Tidemark can’t read its usage page yet",
                                 narrow: "Error", action: "Retry")
        case .noWeeklyLimit:
            return noWeeklyLimit
        }
    }

    /// The notch's words, the same open and at rest and white on black: "Sign in", "Loading…", "Offline", "Blocked".
    public static func notchWord(signedIn: Bool, problem: RefreshProblem?, loading: Bool,
                                 message: GlanceMessage? = nil) -> String? {
        if !signedIn { return "Sign in" }
        if let problem {
            switch problem {
            case .offline: return "Offline"
            case .blocked: return "Blocked"
            case .noWeeklyLimit: return noWeeklyLimit.narrow
            default: return "Error"
            }
        }
        if message == noPlans { return noPlans.narrow }
        return loading ? "Loading…" : nil
    }

    /// How old the last reading is: "Read just now", "Read 2 min ago", "Read 1 h ago", then, past 6
    /// hours, the time it was taken: "Read at 9:14 AM".
    public static func readAge(seconds: TimeInterval, at time: Date, now: Date, formatting: Formatting) -> String {
        if seconds < 60 { return "Read just now" }
        if seconds < 3600 { return "Read \(Int(seconds / 60)) min ago" }
        if seconds < 6 * 3600 { return "Read \(Int(seconds / 3600)) h ago" }
        return "Read at \(formatting.dayTime(time, now: now))"
    }

    /// The strip's one note, saying which limit it means: "5h full 12:24 PM", "wk runs out Sat 2 PM".
    public static func stripNote(_ glance: Glance, asOf: Date? = nil, now: Date, formatting: Formatting) -> String {
        let urgent = glance.mostUrgent
        if urgent.kind == .session {
            switch urgent.note {
            case .fullAt(let date): return "5h full \(formatting.hour(date))"
            case .backAt(let date): return "5h back \(formatting.hour(date))"
            case .resets(let date): return "5h ↺ \(formatting.hour(date))"
            default: return "5h not started"
            }
        }
        return "wk " + Copy.weekNote(urgent, asOf: asOf, now: now, formatting: formatting).text
    }

    /// A plan's line in a menu: "Personal  week 58% · 5h 34%", or what is urgent about it,
    /// "Harbor Labs  runs out Sat 2 PM".
    public static func menuLine(_ org: Org, glance: Glance?, now: Date = Date(), formatting: Formatting = Formatting()) -> String {
        guard let glance else { return org.name }
        if glance.week.isUrgent {
            return "\(org.name)  " + Copy.weekNote(glance.week, now: now, formatting: formatting).text
        }
        return "\(org.name)  week \(Formatting.percent(glance.week.used ?? 0)) · 5h \(Formatting.percent(glance.session.used ?? 0))"
    }
}
