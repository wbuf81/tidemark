import SwiftUI

/// The thin 3 pt line for the 5-hour window (the mockups' `fl5`): filled to `used` percent, with an
/// optional knob at `now` percent of the window. Both are 0...100; nil `used` is an empty line.
/// Fills the width it's given (at least 20 pt).
struct FiveHourLine: View {
    let used: Double?
    let now: Double?

    @Environment(\.colorScheme) private var scheme

    init(used: Double?, now: Double? = nil) {
        self.used = used
        self.now = now
    }

    var body: some View {
        let p = TidePalette.for(scheme)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.track)
                Capsule().fill(p.fg).frame(width: geo.size.width * min(max((used ?? 0) / 100, 0), 1))
                if let now {
                    Circle().fill(p.fg).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(p.sky2, lineWidth: 2))
                        .position(x: geo.size.width * min(max(now / 100, 0), 1), y: 1.5)
                }
            }
        }
        .frame(minWidth: 20, maxWidth: .infinity)
        .frame(height: 3)
    }
}
