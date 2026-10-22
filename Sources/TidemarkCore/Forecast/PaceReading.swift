import Foundation

public enum PaceLevel: Equatable, Sendable {
    case light, even, fast

    /// "Light", "Even", "Fast"
    public var label: String {
        switch self {
        case .light: "Light"
        case .even: "Even"
        case .fast: "Fast"
        }
    }
}

/// How the week's use compares with using it evenly: 1.0 means exactly the even share so far.
public struct PaceReading: Equatable, Sendable {
    public var level: PaceLevel
    /// Used ÷ the even share so far (elapsed × 100).
    public var multiple: Double
    /// "1.8× even", one decimal.
    public var text: String

    /// Under this much of the week gone, a few percent says nothing about the pace.
    static let fromElapsed = 0.02

    /// nil without an open week or before 2% of it.
    public static func make(reading: Reading, now: Date) -> PaceReading? {
        guard let reset = reading.weekResetsAt, reset > now else { return nil }
        let elapsed = (Pace.window - reset.timeIntervalSince(now)) / Pace.window
        guard elapsed >= fromElapsed else { return nil }
        let multiple = reading.week / (elapsed * 100)
        // The word follows the number as it is shown (one decimal), so "Light" is never beside "0.9×".
        let number = String(format: "%.1f", multiple)
        let shown = Double(number) ?? multiple
        let level: PaceLevel = shown < 0.85 ? .light : shown > 1.15 ? .fast : .even
        return PaceReading(level: level, multiple: multiple, text: "\(number)× even")
    }
}
