import AppKit
import SwiftUI
import TidemarkCore

/// What "Copy summary" puts on the pasteboard: the header, the brief and the calendar, with no
/// sidebar and no buttons. Titles the model hides stay hidden; the model already masked them.
struct CopySummaryView: View {
    let week: WeekModel
    let now: Date
    let calendar: Calendar
    var twentyFourHour = Formatting.prefers24Hour()
    static let width: CGFloat = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(WindowCopy.range(week, calendar: calendar))
                .font(Theme.font(21, .bold)).foregroundStyle(Palette.bright)
            WeekBody(week: week, now: now, calendar: calendar, twentyFourHour: twentyFourHour)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: Self.width, alignment: .topLeading)
        .background(Palette.tile)
    }
}

/// Puts the week on the general pasteboard as a picture, and says "Copied" for two seconds.
@MainActor
final class CopyState: ObservableObject {
    @Published private(set) var copied = false
    private var reset: Task<Void, Never>?

    /// The picture at 2×, in light or dark: what would go on the pasteboard.
    static func image(week: WeekModel, now: Date, calendar: Calendar, dark: Bool, twentyFourHour: Bool = Formatting.prefers24Hour()) -> NSBitmapImageRep? {
        Renderer.picture(CopySummaryView(week: week, now: now, calendar: calendar, twentyFourHour: twentyFourHour), dark: dark)
    }

    func copy(week: WeekModel, now: Date, calendar: Calendar, dark: Bool) {
        guard let image = Self.image(week: week, now: now, calendar: calendar, dark: dark),
              let png = image.representation(using: .png, properties: [:]),
              let tiff = image.tiffRepresentation else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        board.setData(tiff, forType: .tiff)
        copied = true
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        reset?.cancel()
        reset = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { self?.copied = false }
        }
    }
}
