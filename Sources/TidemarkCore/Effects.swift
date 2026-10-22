/// How an org that's in use shows it, on its 5-hour line.
public enum EffectStyle: String, Codable, CaseIterable, Sendable {
    /// Sparks shed along the 5-hour line, which burns like a fuse.
    case sparks
    /// Specks of light streaming along the filled part of the line.
    case flow
    /// A soft sweep of light along the line.
    case shimmer
    case off
}

/// How many particles, as a multiple of the normal birth rates and speck counts.
public enum EffectAmount: String, Codable, CaseIterable, Sendable {
    case subtle, normal, lots

    public var multiplier: Double {
        switch self {
        case .subtle: 0.5
        case .normal: 1
        case .lots: 1.8
        }
    }
}
