import Foundation

/// Every adjustable threshold, in percent or hours. Defaults are the spec's values.
/// Decoding is tolerant: each field falls back to its default when missing, and fields
/// this version doesn't know (a removed one, or one from a newer version) are ignored,
/// so a saved set never resets the rest.
public struct Thresholds: Codable, Equatable, Sendable {
    public var redWeekLeft = 10.0
    public var redSession = 95.0
    public var yellowSession = 80.0
    public var onPaceUnused = 5.0
    public var eligibleWeekLeft = 10.0
    public var eligibleSessionBelow = 80.0
    public var primaryReserveWeekLeft = 15.0

    /// Red when the week will run out this many hours early. Fixed now: no longer a saved setting.
    public static let redRunsOutEarlyHours = 12.0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case redWeekLeft, redSession, yellowSession, onPaceUnused
        case eligibleWeekLeft, eligibleSessionBelow, primaryReserveWeekLeft
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds()
        redWeekLeft = try c.decodeIfPresent(Double.self, forKey: .redWeekLeft) ?? d.redWeekLeft
        redSession = try c.decodeIfPresent(Double.self, forKey: .redSession) ?? d.redSession
        yellowSession = try c.decodeIfPresent(Double.self, forKey: .yellowSession) ?? d.yellowSession
        onPaceUnused = try c.decodeIfPresent(Double.self, forKey: .onPaceUnused) ?? d.onPaceUnused
        eligibleWeekLeft = try c.decodeIfPresent(Double.self, forKey: .eligibleWeekLeft) ?? d.eligibleWeekLeft
        eligibleSessionBelow = try c.decodeIfPresent(Double.self, forKey: .eligibleSessionBelow) ?? d.eligibleSessionBelow
        primaryReserveWeekLeft = try c.decodeIfPresent(Double.self, forKey: .primaryReserveWeekLeft) ?? d.primaryReserveWeekLeft
    }
}
