import SwiftUI
import TidemarkCore

/// A glass card over the sky (the mockups' `tdcard` and `tdpanel`): the palette's glass wash, a hairline,
/// and a firmer edge when it is the selected plan.
struct GlassCard: ViewModifier {
    var selected = false
    var padding: CGFloat = 14
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let p = TidePalette.for(scheme)
        let shape = RoundedRectangle(cornerRadius: 14)
        content
            .padding(padding)
            .background(p.glass, in: shape)
            .overlay(shape.strokeBorder(selected ? p.fg.opacity(0.75) : p.line, lineWidth: selected ? 1.6 : 1))
    }
}

extension View {
    func glassCard(selected: Bool = false, padding: CGFloat = 14) -> some View {
        modifier(GlassCard(selected: selected, padding: padding))
    }
}

/// A small glass button, drawn by hand so it also draws in pictures.
struct UsageButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        Button(action: action) {
            Text(title)
                .font(Theme.font(12.5, .medium))
                .foregroundStyle(p.fg)
                .padding(.vertical, 4).padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(p.glass, in: Capsule())
                .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The locked mark: a small square in the red hatch, as the chart's locked stretch.
struct LockedSwatch: View {
    var size: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        Canvas { ctx, canvas in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 2)
            TideHatch.fill(&ctx, region: rect, spacing: 3.4, stripe: 1.3, stripeColor: p.redMark, base: p.redMark.opacity(0.22))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Lays its children in equal columns as many as fit `minWidth`, each row as tall as its tallest card.
struct CardGrid: Layout {
    var minWidth: CGFloat = 210
    var spacing: CGFloat = 12

    /// Every card in one row at its narrowest: the width when the proposal leaves it open (nil or infinite).
    private func idealWidth(_ count: Int) -> CGFloat { minWidth * CGFloat(count) + spacing * CGFloat(max(count - 1, 0)) }

    private func columns(_ width: CGFloat, _ count: Int) -> Int {
        guard width.isFinite else { return max(1, count) }
        // Clamped in floating point first: a huge finite proposal would trap converting to Int.
        return max(1, min(count, Int(min(Double(count), ((width + spacing) / (minWidth + spacing)).rounded(.down)))))
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let n = columns(width, subviews.count)
        let cell = (width - spacing * CGFloat(n - 1)) / CGFloat(n)
        var frames: [CGRect] = [], y: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: n) {
            let row = subviews[start..<min(start + n, subviews.count)]
            let height = row.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
            for (i, _) in row.enumerated() {
                frames.append(CGRect(x: CGFloat(i) * (cell + spacing), y: y, width: cell, height: height))
            }
            y += height + spacing
        }
        return (frames, max(y - spacing, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth(subviews.count)
        return CGSize(width: width, height: arrange(width, subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}

/// The text colour for a state's numbers: the state's ink, or the normal ink when fine.
enum UsageText {
    static func ink(_ state: PlanState?) -> Color {
        switch state {
        case .runsOutEarly: Palette.amberInk
        case .out: Palette.redInk
        default: Palette.bright
        }
    }
}
