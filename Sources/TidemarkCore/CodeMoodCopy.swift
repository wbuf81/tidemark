import Foundation

public extension CodeMood {
    /// The word beside the status glyph.
    var word: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .tool: "Working"
        case .permission: "Needs you"
        case .done: "Done"
        }
    }
}
