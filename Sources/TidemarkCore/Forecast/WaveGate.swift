import Foundation

/// Whether the tide waves may drift right now. They are Core Animation layers in the window server, so
/// the only way to make them cost nothing is to take their animations away: this says when. Any one
/// reason to stand still is enough.
public struct WaveGate: Equatable, Sendable {
    /// The window holding the waves is on screen and not covered: not hidden for an hour, not closed
    /// (the notch's slots leave their window when it closes) and not occluded by other windows.
    public var windowVisible = false
    /// The screens are awake (`screensDidSleep` / `screensDidWake`).
    public var screensAwake = true
    /// This login session is the one at the keyboard (`sessionDidResignActive` / `sessionDidBecomeActive`).
    public var sessionActive = true
    /// System Reduce Motion.
    public var reduceMotion = false
    /// A picture (the renders), which can't show Core Animation at all.
    public var stillPicture = false
    /// The reading is old: the water holds still.
    public var isOld = false

    public init() {}

    public var runs: Bool {
        windowVisible && screensAwake && sessionActive && !reduceMotion && !stillPicture && !isOld
    }
}
