import Foundation

/// A Claude organization the signed-in account belongs to.
public struct Org: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var billingType: String?

    public init(id: String, name: String, billingType: String? = nil) {
        self.id = id
        self.name = name
        self.billingType = billingType
    }
}

/// How the owner uses an org. The primary org is shared with the Claude desktop app.
public enum Role: String, Codable, Sendable {
    case primary, overflow
}

/// One usage snapshot for one org. Percentages are "used", 0–100.
public struct Reading: Codable, Equatable, Sendable {
    public var time: Date
    public var org: String
    public var session: Double
    /// nil when no 5-hour window is open.
    public var sessionResetsAt: Date?
    public var week: Double
    /// nil when the week hasn't started (nothing used yet).
    public var weekResetsAt: Date?
    /// Model-specific weekly limits, e.g. ["Fable": 31].
    public var scoped: [String: Double]
    /// Each model-specific limit's own reset, when claude.ai gives one; a name that's missing
    /// resets with the week. Older history lines have none.
    public var scopedResetsAt: [String: Date]

    public init(time: Date, org: String, session: Double, sessionResetsAt: Date?,
                week: Double, weekResetsAt: Date?, scoped: [String: Double] = [:],
                scopedResetsAt: [String: Date] = [:]) {
        self.time = time
        self.org = org
        self.session = session
        self.sessionResetsAt = sessionResetsAt
        self.week = week
        self.weekResetsAt = weekResetsAt
        self.scoped = scoped
        self.scopedResetsAt = scopedResetsAt
    }

    enum CodingKeys: String, CodingKey {
        case time = "t", org, session, sessionResetsAt, week, weekResetsAt, scoped, scopedResetsAt
    }

    // Written by hand so history lines from before `scopedResetsAt` still load, and lines
    // without model resets stay as short as before.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Date.self, forKey: .time)
        org = try c.decode(String.self, forKey: .org)
        session = try c.decode(Double.self, forKey: .session)
        sessionResetsAt = try c.decodeIfPresent(Date.self, forKey: .sessionResetsAt)
        week = try c.decode(Double.self, forKey: .week)
        weekResetsAt = try c.decodeIfPresent(Date.self, forKey: .weekResetsAt)
        scoped = try c.decodeIfPresent([String: Double].self, forKey: .scoped) ?? [:]
        scopedResetsAt = try c.decodeIfPresent([String: Date].self, forKey: .scopedResetsAt) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(time, forKey: .time)
        try c.encode(org, forKey: .org)
        try c.encode(session, forKey: .session)
        try c.encodeIfPresent(sessionResetsAt, forKey: .sessionResetsAt)
        try c.encode(week, forKey: .week)
        try c.encodeIfPresent(weekResetsAt, forKey: .weekResetsAt)
        try c.encode(scoped, forKey: .scoped)
        if !scopedResetsAt.isEmpty { try c.encode(scopedResetsAt, forKey: .scopedResetsAt) }
    }

    /// A model limit's reset: its own, else the week's.
    func resetsAt(scoped name: String) -> Date? { scopedResetsAt[name] ?? weekResetsAt }

    var weekLeft: Double { 100 - week }

    /// How long a reading counts as current. Refreshes come every 3 minutes, so an older
    /// reading means its org has stopped reading.
    static let freshFor: TimeInterval = 600

    public func isFresh(now: Date) -> Bool { now.timeIntervalSince(time) <= Self.freshFor }

    /// The reading as it stands at `now`: a window whose reset time has passed is empty again.
    public func adjusted(to now: Date) -> Reading {
        var r = self
        if let reset = r.sessionResetsAt, reset <= now {
            r.session = 0
            r.sessionResetsAt = nil
        }
        for name in Array(r.scoped.keys) {
            if let reset = resetsAt(scoped: name), reset <= now {
                r.scoped[name] = 0
                r.scopedResetsAt[name] = nil
            }
        }
        if let reset = r.weekResetsAt, reset <= now {
            r.week = 0
            r.weekResetsAt = nil
        }
        return r
    }
}
