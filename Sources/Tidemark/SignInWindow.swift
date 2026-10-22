import AppKit
import TidemarkCore

/// The sign-in window's native parts: the hint, the Open copied sign-in link button and, below
/// them, `page`. The app passes the claude.ai sign-in page; `--render` passes a placeholder, so
/// drawing the window never makes a web view or opens the app's website data.
///
/// Laid out with Auto Layout so the hint can grow to as many lines as it needs (it never clips),
/// and the window can't be made smaller than 480 × 560.
@MainActor
enum SignInWindow {
    static let size = NSSize(width: 520, height: 760)
    static let minSize = NSSize(width: 480, height: 560)

    /// The window, not yet placed or shown. The button sends `openLink` to `target`.
    static func make(page: NSView, target: AnyObject?, openLink: Selector?) -> NSWindow {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hint = NSTextField(wrappingLabelWithString: ShellCopy.signInHint)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .labelColor
        hint.setContentCompressionResistancePriority(.required, for: .vertical)
        let paste = NSButton(title: ShellCopy.openCopiedLink, target: target, action: openLink)
        for view in [hint, paste, page] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            paste.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            paste.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            page.topAnchor.constraint(equalTo: paste.bottomAnchor, constant: 10),
            page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = ShellCopy.signInWindowTitle
        window.contentView = container
        window.contentMinSize = minSize
        window.isReleasedWhenClosed = false
        return window
    }
}
