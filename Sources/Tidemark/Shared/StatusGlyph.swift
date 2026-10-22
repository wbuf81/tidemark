import SwiftUI
import TidemarkCore

/// What Claude Code is doing, as a glyph (the mockups' `GLYPH`, in a 24-unit box). "Needs you" is
/// in blue ink, the rest in the bright text colour. Pair it with `CodeMood.word`.
struct StatusGlyph: View {
    let mood: CodeMood
    let size: CGFloat
    /// Overrides the ink, for a glyph on the sky or on a blue chip.
    let ink: Color?

    init(_ mood: CodeMood, size: CGFloat = 20, ink: Color? = nil) {
        self.mood = mood
        self.size = size
        self.ink = ink
    }

    var body: some View {
        let u = size / 24
        let ink = ink ?? (mood == .permission ? Palette.blueInk : Palette.bright)
        ZStack {
            switch mood {
            case .idle:
                ScaledShape(box: 24) { $0.addEllipse(in: CGRect(x: 5.5, y: 5.5, width: 13, height: 13)) }
                    .stroke(ink.opacity(0.7), lineWidth: 1.8 * u)
            case .thinking:
                ForEach(Array([(5.5, 1.0), (12.0, 0.7), (18.5, 0.45)].enumerated()), id: \.offset) { _, dot in
                    ScaledShape(box: 24) { $0.addEllipse(in: CGRect(x: dot.0 - 2.5, y: 9.5, width: 5, height: 5)) }
                        .fill(ink.opacity(dot.1))
                }
            case .tool:
                ScaledShape(box: 24) { $0.addRoundedRect(in: CGRect(x: 3, y: 5, width: 18, height: 14), cornerSize: CGSize(width: 3, height: 3)) }
                    .stroke(ink, lineWidth: 1.8 * u)
                ScaledShape(box: 24) {
                    $0.move(to: CGPoint(x: 7, y: 10)); $0.addLine(to: CGPoint(x: 10, y: 12.5)); $0.addLine(to: CGPoint(x: 7, y: 15))
                    $0.move(to: CGPoint(x: 12.5, y: 15.5)); $0.addLine(to: CGPoint(x: 17, y: 15.5))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: 1.8 * u, lineCap: .round, lineJoin: .round))
            case .permission:
                // The "!" is cut out of the bubble, so it shows whatever is behind (tile or black notch).
                ZStack {
                    ScaledShape(box: 24) { Self.bubble(&$0) }.fill(ink)
                    ScaledShape(box: 24) { $0.move(to: CGPoint(x: 12, y: 6.8)); $0.addLine(to: CGPoint(x: 12, y: 10.8)) }
                        .stroke(.black, style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                        .blendMode(.destinationOut)
                    ScaledShape(box: 24) { $0.addEllipse(in: CGRect(x: 10.8, y: 12.4, width: 2.4, height: 2.4)) }
                        .fill(.black).blendMode(.destinationOut)
                }
                .compositingGroup()
            case .done:
                ScaledShape(box: 24) {
                    $0.move(to: CGPoint(x: 5, y: 12.5)); $0.addLine(to: CGPoint(x: 10, y: 17)); $0.addLine(to: CGPoint(x: 19, y: 7.5))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2 * u, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    nonisolated private static func bubble(_ p: inout Path) {
        p.move(to: CGPoint(x: 4, y: 6.5))
        p.svgArc(to: CGPoint(x: 7, y: 3.5), r: 3)
        p.addLine(to: CGPoint(x: 17, y: 3.5))
        p.svgArc(to: CGPoint(x: 20, y: 6.5), r: 3)
        p.addLine(to: CGPoint(x: 20, y: 13.5))
        p.svgArc(to: CGPoint(x: 17, y: 16.5), r: 3)
        p.addLine(to: CGPoint(x: 10, y: 16.5))
        p.addLine(to: CGPoint(x: 6, y: 20))
        p.addLine(to: CGPoint(x: 6, y: 16.5))
        p.svgArc(to: CGPoint(x: 4, y: 13.5), r: 3)
        p.closeSubpath()
    }
}
