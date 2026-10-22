import SwiftUI
import TidemarkCore

/// A plan's state as a shape, so colour is never the only cue: fine = circle, runs out early =
/// triangle, out = square. An old reading draws the same shape hollow; `nil` (couldn't read) is a
/// grey ring with a dash. Geometry is the mockups' `shape()` in a 10-unit box.
struct StateShape: View {
    let state: PlanState?
    let hollow: Bool
    let size: CGFloat

    init(_ state: PlanState?, hollow: Bool = false, size: CGFloat = 10) {
        self.state = state
        self.hollow = hollow
        self.size = size
    }

    var body: some View {
        let u = size / 10
        let tone = Palette.color(for: state)
        ZStack {
            if let state {
                if hollow {
                    ScaledShape(box: 10) { Self.hollowPath(state, &$0) }
                        .stroke(tone, style: StrokeStyle(lineWidth: (state == .fine ? 1.5 : 1.4) * u, lineJoin: .round))
                } else {
                    ScaledShape(box: 10) { Self.filledPath(state, &$0) }.fill(tone)
                }
            } else {
                ScaledShape(box: 10) { $0.addEllipse(in: CGRect(x: 1.3, y: 1.3, width: 7.4, height: 7.4)) }
                    .stroke(tone, lineWidth: 1.5 * u)
                ScaledShape(box: 10) { $0.move(to: CGPoint(x: 3, y: 5)); $0.addLine(to: CGPoint(x: 7, y: 5)) }
                    .stroke(tone, style: StrokeStyle(lineWidth: 1.5 * u, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    nonisolated static func filledPath(_ state: PlanState, _ p: inout Path) {
        switch state {
        case .fine: p.addEllipse(in: CGRect(x: 0.8, y: 0.8, width: 8.4, height: 8.4))
        case .runsOutEarly:
            p.move(to: CGPoint(x: 5, y: 0.6)); p.addLine(to: CGPoint(x: 9.6, y: 9))
            p.addLine(to: CGPoint(x: 0.4, y: 9)); p.closeSubpath()
        case .out: p.addRoundedRect(in: CGRect(x: 0.9, y: 0.9, width: 8.2, height: 8.2), cornerSize: CGSize(width: 1.3, height: 1.3))
        }
    }

    nonisolated static func hollowPath(_ state: PlanState, _ p: inout Path) {
        switch state {
        case .fine: p.addEllipse(in: CGRect(x: 1.3, y: 1.3, width: 7.4, height: 7.4))
        case .runsOutEarly:
            p.move(to: CGPoint(x: 5, y: 1.6)); p.addLine(to: CGPoint(x: 8.8, y: 8.4))
            p.addLine(to: CGPoint(x: 1.2, y: 8.4)); p.closeSubpath()
        case .out: p.addRoundedRect(in: CGRect(x: 1.6, y: 1.6, width: 6.8, height: 6.8), cornerSize: CGSize(width: 1, height: 1))
        }
    }
}
