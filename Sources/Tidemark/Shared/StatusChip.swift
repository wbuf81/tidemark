import SwiftUI
import TidemarkCore

/// Claude Code's status on its plan (the mockups' `cchip` and `cbadge`). The chip is the glyph and its
/// word in a capsule in the plan's name row; quiet when idle, blue when Claude Code needs you. Compact
/// is the badge: the glyph alone in an 18 pt circle, for the slot's corner at narrow widths. Words come
/// from `CodeMood.word`; the badge keeps it as its accessibility label.
struct StatusChip: View {
    let mood: CodeMood
    let compact: Bool
    /// The slot's text scale, so the chip grows with the text around it.
    let scale: CGFloat

    @Environment(\.colorScheme) private var scheme

    init(mood: CodeMood, compact: Bool = false, scale: CGFloat = 1) {
        self.mood = mood
        self.compact = compact
        self.scale = scale
    }

    var body: some View {
        let p = TidePalette.for(scheme)
        let needs = mood == .permission
        let ink = needs ? Color.white : p.fg
        Group {
            if compact {
                StatusGlyph(mood, size: 12 * scale, ink: ink)
                    .frame(width: 18 * scale, height: 18 * scale)
                    .background(Circle().fill(needs ? TidePalette.needsBlue : p.sky2))
                    .overlay(Circle().stroke(p.line, lineWidth: needs ? 0 : 1.5))
            } else {
                HStack(spacing: 4 * scale) {
                    StatusGlyph(mood, size: 13 * scale, ink: ink)
                    Text(mood.word).font(Theme.font(10.5 * scale, .semibold)).foregroundStyle(mood == .idle ? p.dim : ink)
                }
                .padding(.leading, 6 * scale).padding(.trailing, 8 * scale).padding(.vertical, 2 * scale)
                .background(Capsule().fill(needs ? TidePalette.needsBlue : p.sky1.opacity(0.82)))
                .overlay(Capsule().stroke(p.line, lineWidth: needs ? 0 : 1))
            }
        }
        .opacity(mood == .idle ? 0.8 : 1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude Code: \(mood.word)")
    }
}
