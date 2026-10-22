import Foundation

/// How a plan's tide is drawn behind its slot.
public enum TideStyle: String, CaseIterable, Sendable {
    /// The water sits at how full the plan is.
    case level
    /// The water's surface traces how the week filled up, with the forecast ahead.
    case week

    public var label: String {
        switch self {
        case .level: "Water level"
        case .week: "Over the week"
        }
    }
}
