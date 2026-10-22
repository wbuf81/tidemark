import AppKit

/// Draws AppKit windows to images without ever putting them on screen, for `--render`. SwiftUI's
/// `ImageRenderer` can't draw AppKit-backed controls (forms, toggles, pop-up buttons, alerts),
/// so these windows are built for real, laid out in a light or dark appearance, and asked to
/// draw into a bitmap. Nothing here orders a window in, makes it key or activates the app, so
/// windows draw as they look while another app is in front.
@MainActor
enum Offscreen {
    /// The window as it would look on screen: its frame view (title bar and all) when
    /// `chrome`, otherwise just its content view. Nil when it has nothing to draw.
    static func image(of window: NSWindow, dark: Bool, chrome: Bool = true) -> NSBitmapImageRep? {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let content = window.contentView else { return nil }
        let view = chrome ? (content.superview ?? content) : content
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// `image` laid over the window background colour in a rounded rect of `radius` points:
    /// for windows whose background is a material (an alert's), which a bitmap can't draw.
    static func onBackground(_ image: NSBitmapImageRep, dark: Bool, radius: CGFloat) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.pixelsWide, pixelsHigh: image.pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = image.size   // in points, before the context is made, so it draws in points too
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(origin: .zero, size: image.size)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// How tall the window's scrolling content is (the first scroll view in it, such as a
    /// form's), so it can be built again tall enough to show all of it; nil without one.
    static func scrolledHeight(in window: NSWindow) -> CGFloat? {
        guard let content = window.contentView else { return nil }
        content.layoutSubtreeIfNeeded()
        return firstScrollView(in: content)?.documentView.map { ceil($0.frame.height) }
    }

    /// The same for a bare view (a tab's page before it has a window).
    static func scrolledHeight(in view: NSView) -> CGFloat? {
        view.layoutSubtreeIfNeeded()
        return firstScrollView(in: view)?.documentView.map { ceil($0.frame.height) }
    }

    /// The first scroll view in `view` (a form's), as it is now.
    static func scrollView(in view: NSView) -> NSScrollView? { firstScrollView(in: view) }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
