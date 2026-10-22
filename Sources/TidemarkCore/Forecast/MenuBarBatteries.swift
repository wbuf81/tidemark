import Foundation

/// What Settings → General → Menu bar shows: a battery per plan, Tidemark's icon, or nothing.
public enum MenuBarMode: String, CaseIterable, Sendable {
    case batteries, icon, off

    public var title: String {
        switch self {
        case .batteries: "A battery per plan"
        case .icon: "Tidemark icon"
        case .off: "Off"
        }
    }

    /// The saved choice, else the old on/off switch (on → a battery per plan, off → off), else batteries.
    public static func migrated(saved: String?, legacyIcon: Bool?) -> MenuBarMode {
        if let saved, let mode = MenuBarMode(rawValue: saved) { return mode }
        switch legacyIcon {
        case false?: return .off
        default: return .batteries
        }
    }
}

/// Whether a battery names its plan or shows its first letter (for a notched MacBook's short menu bar).
public enum PlanNameStyle: String, CaseIterable, Sendable {
    case names, letters

    public var title: String { self == .names ? "Names" : "First letters" }
}

/// The batteries in the menu bar, as the mockup draws them: name, battery (what's left of the week), then the % left.
public enum MenuBarBatteries {
    public enum Fill: Equatable, Sendable {
        /// The menu bar's own ink.
        case ink, amber, red
    }

    public struct Plan: Equatable, Sendable {
        public var id: String
        public var name: String
        /// % of the week used; nil when the plan has never been read.
        public var weekUsed: Double?
        /// The week's state alone (`PlanStates.weekState`): the battery shows the week, so the 5-hour
        /// window never turns it red or says "Out".
        public var state: PlanState?
        public var isOld: Bool
        /// What Claude Code is doing, for the plan it is signed in to; nil for every other plan (and with no hooks).
        public var codeMood: CodeMood?

        public init(id: String, name: String, weekUsed: Double?, state: PlanState?, isOld: Bool, codeMood: CodeMood? = nil) {
            self.id = id; self.name = name; self.weekUsed = weekUsed; self.state = state; self.isOld = isOld; self.codeMood = codeMood
        }
    }

    public struct Item: Equatable, Sendable {
        public var id: String
        public var label: String
        /// 0...100, what's left of the week.
        public var left: Int
        public var fill: Fill
        public var out: Bool
        public var dimmed: Bool
        /// "42%", or "Out".
        public var percentText: String
        /// "Personal: 42% of the week left".
        public var accessibility: String
        /// What moves on this battery.
        public var activity: Activity = .none
    }

    /// What a battery shows about Claude Code: bubbles while it thinks or works, a blue dot when it needs you.
    public enum Activity: Equatable, Sendable {
        case none, working, needsYou

        init(_ mood: CodeMood?) {
            switch mood {
            case .thinking?, .tool?: self = .working
            case .permission?: self = .needsYou
            default: self = .none
            }
        }

        /// What VoiceOver adds to the battery's label.
        var spoken: String? {
            switch self {
            case .none: nil
            case .working: "Claude Code is working"
            case .needsYou: "Claude Code needs you"
            }
        }
    }

    /// What to draw on a battery right now, once the gate has had its say.
    public struct Effect: Equatable, Sendable {
        public var bubbles: Bool
        /// The blue dot is shown (still, when Reduce Motion or any other reason to stand still applies).
        public var dot: Bool
        public var pulse: Bool

        public init(bubbles: Bool, dot: Bool, pulse: Bool) {
            self.bubbles = bubbles; self.dot = dot; self.pulse = pulse
        }
    }

    /// Bubbles and the pulse need the gate to run (the same reasons the tide waves stand still); the dot itself
    /// is a signal and stays, still.
    public static func effect(_ activity: Activity, gate: WaveGate) -> Effect {
        Effect(bubbles: activity == .working && gate.runs, dot: activity == .needsYou, pulse: activity == .needsYou && gate.runs)
    }

    /// One item per plan that has been read, in order; none while plan limits are off.
    public static func make(_ plans: [Plan], limitsOn: Bool, names: PlanNameStyle) -> [Item] {
        guard limitsOn else { return [] }
        return plans.compactMap { plan in
            guard let used = plan.weekUsed else { return nil }
            let left = Int(min(100, max(0, 100 - used)).rounded())
            // Red for a week that is nearly out; the word "Out" only when it is really full.
            let out = used >= 100
            let fill: Fill = plan.state == .out ? .red : plan.state == .runsOutEarly ? .amber : .ink
            let name = plan.name.trimmingCharacters(in: .whitespaces)
            let label = names == .names ? name : name.first.map { String($0).uppercased() } ?? ""
            var spoken = out ? "\(name): out" : "\(name): \(left)% of the week left"
            if plan.isOld { spoken += ", old reading" }
            let activity = Activity(plan.codeMood)
            if let words = activity.spoken { spoken += ", " + words }
            return Item(id: plan.id, label: label, left: left, fill: fill, out: out, dimmed: plan.isOld,
                        percentText: out ? "Out" : "\(left)%", accessibility: spoken, activity: activity)
        }
    }
}
