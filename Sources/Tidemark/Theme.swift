import AppKit
import SwiftUI

/// Fonts and window shape: one look, the system font with even-width digits, rounded and flat.
enum Theme {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Window corners and borders: rounded and 1 pt.
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 1
}

/// Follow the Mac's appearance, or pin light or dark.
enum ThemeChoice: String, CaseIterable, Codable {
    case followMac, day, night

    var appearance: NSAppearance? {
        switch self {
        case .followMac: nil
        case .day: NSAppearance(named: .aqua)
        case .night: NSAppearance(named: .darkAqua)
        }
    }

    var title: String {
        switch self {
        case .followMac: "Follow the Mac"
        case .day: "Light"
        case .night: "Dark"
        }
    }
}
