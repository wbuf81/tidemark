import SwiftUI
import TidemarkCore

extension GlanceTone {
    /// The mark colour for a bar's fill: green has room, amber will fill or run out, red is full or nearly out.
    var color: Color {
        switch self {
        case .green: Palette.green
        case .amber: Palette.amber
        case .red: Palette.red
        case .none: Palette.faint
        }
    }

    /// The same for text, a shade darker where the mark's would not reach 4.5:1.
    var ink: Color {
        switch self {
        case .green, .none: Palette.bright
        case .amber: Palette.amberInk
        case .red: Palette.redInk
        }
    }
}

/// A small grey-bordered button, dark text like the mockup's, for the widget's messages: Retry, Sign in…
struct ActionChip: View {
    let title: String
    let k: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.font(10.5 * k, .semibold)).foregroundStyle(Palette.fg)
                .padding(.horizontal, 8 * k).padding(.vertical, 3 * k)
                .overlay(RoundedRectangle(cornerRadius: 5 * k).strokeBorder(Palette.track, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Claude Code's status at the start of the widget: its glyph, its word and "Claude Code". At XS the
/// glyph alone.
struct StatusSlot: View {
    let mood: CodeMood
    let width: CGFloat
    let k: CGFloat

    var body: some View {
        let compact = width <= 32 * k
        VStack(spacing: 3 * k) {
            StatusGlyph(mood, size: 20 * k)
            if !compact {
                Text(mood.word).font(Theme.font(11.5 * k, .semibold))
                    .foregroundStyle(mood == .permission ? Palette.blueInk : Palette.bright)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("Claude Code").font(Theme.font(10 * k))
                    .foregroundStyle(mood == .permission ? Palette.blueInk : Palette.faint)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 5 * k)
        .frame(width: width, alignment: .center)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude Code: \(mood.word)")
    }
}
