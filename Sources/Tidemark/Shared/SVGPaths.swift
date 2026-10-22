import SwiftUI

/// Helpers for drawing the mockups' SVG geometry exactly: a view box scaled to a rect.
extension Path {
    /// An SVG `A` arc (radius `r`, small arc, `sweep` 1 = clockwise on screen) from the current point to `end`.
    mutating func svgArc(to end: CGPoint, r: CGFloat) {
        guard let start = currentPoint else { return }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        let chord = (dx * dx + dy * dy).squareRoot()
        let d = max(r * r - chord * chord / 4, 0).squareRoot()
        for sign in [CGFloat(1), -1] {
            let center = CGPoint(x: mid.x + sign * d * (-dy / chord), y: mid.y + sign * d * (dx / chord))
            let a1 = atan2(start.y - center.y, start.x - center.x), a2 = atan2(end.y - center.y, end.x - center.x)
            var delta = a2 - a1
            while delta < 0 { delta += 2 * .pi }
            if delta < .pi {
                addRelativeArc(center: center, radius: r, startAngle: .radians(Double(a1)), delta: .radians(Double(delta)))
                return
            }
        }
        addLine(to: end)
    }
}

/// A shape drawn in a square view box of `box` units, scaled to fill its rect.
struct ScaledShape: Shape {
    var box: CGFloat
    var build: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var p = Path()
        build(&p)
        let k = min(rect.width, rect.height) / box
        return p.applying(CGAffineTransform(scaleX: k, y: k)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
