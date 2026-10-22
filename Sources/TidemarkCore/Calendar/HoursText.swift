import Foundation

/// Hours and minutes the way the calendar writes them: "9h 05m".
public enum HoursText {
    /// Minutes are rounded half to even, as the old calendar did (90.5 min → 90, 91.5 → 92).
    public static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded(.toNearestOrEven))
        return "\(minutes / 60)h " + String(format: "%02dm", minutes % 60)
    }
}
