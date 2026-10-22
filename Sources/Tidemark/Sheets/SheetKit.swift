import AppKit
import SwiftUI
import TidemarkCore

/// What every consent sheet is made of: a title, words, and a row of buttons, in the mockups'
/// `.sheet` look. Each sheet is a SwiftUI view; `SheetPresenter` puts it on screen (over a window
/// as a real sheet, or in its own window), and `--render` draws it offscreen.
struct SheetFrame<Content: View, Actions: View>: View {
    var title: String
    var step: String?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let step { Text(step).font(.system(size: 11)).foregroundStyle(Palette.faint) }
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.bright)
                .accessibilityAddTraits(.isHeader)
            content
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                actions
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: SheetFrame.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.tile)
    }

    static var width: CGFloat { 420 }
}

/// Body text in a sheet (13 pt), and its smaller grey note (12 pt).
struct SheetText: View {
    var text: String
    var note = false

    init(_ text: String, note: Bool = false) {
        self.text = text
        self.note = note
    }

    var body: some View {
        Text(text)
            .font(.system(size: note ? 12 : 13))
            .foregroundStyle(note ? Palette.dim : Palette.fg)
            .lineSpacing(note ? 1 : 2.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Anthropic's warning about reading claude.ai, in the amber box the mockups use.
struct ClaudeAIWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StateShape(.runsOutEarly, size: 14).padding(.top, 2)
            (Text(ShellCopy.planLimitsWarningHead).fontWeight(.bold).foregroundColor(Palette.bright)
                + Text(" " + ShellCopy.planLimitsWarning).foregroundColor(Palette.fg))
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.amber.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.amber.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// A monospaced box for text a user is shown or copies; `added` lines are green (the hooks' diff).
struct CodeBox: View {
    var lines: [String]
    var addedFrom = Int.max

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line.isEmpty ? " " : line)
                    .foregroundStyle(index >= addedFrom ? Palette.green : Palette.fg)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .lineSpacing(2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.page))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
        .textSelection(.enabled)
    }
}

/// Red text on a bordered button, for what can't be undone. Never the default button.
struct DangerButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) { Text(title).foregroundStyle(Palette.redInk) }
    }
}

/// Puts sheets on screen. With a parent window the sheet slides over it; without one it gets its
/// own centred window (a sheet asked for from the menu bar or first run).
@MainActor
enum SheetPresenter {
    private static var open: [NSWindow] = []
    /// Stand-alone sheets (with no window to slide out of) on screen: true when the first appears,
    /// false when the last goes, so the app can keep its Dock icon meanwhile.
    static var onStandaloneChange: ((Bool) -> Void)?
    private static var standalone = 0

    /// Shows the sheet `make` builds; the view it gets calls `dismiss` to close it.
    static func present<V: View>(over parent: NSWindow? = nil, title: String, _ make: (@escaping () -> Void) -> V) {
        var window: NSWindow?
        var counted = false
        let dismiss: () -> Void = {
            guard let sheet = window else { return }
            if let parent = sheet.sheetParent { parent.endSheet(sheet) }
            sheet.orderOut(nil)
            open.removeAll { $0 === sheet }
            window = nil
            if counted { standalone -= 1; if standalone == 0 { onStandaloneChange?(false) } }
        }
        let host = NSHostingController(rootView: make(dismiss))
        host.sizingOptions = [.preferredContentSize]
        let sheet = NSWindow(contentViewController: host)
        sheet.styleMask = [.titled]
        // The title stays hidden; VoiceOver reads it to name the window.
        sheet.title = title
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.isReleasedWhenClosed = false
        window = sheet
        open.append(sheet)
        if let parent, parent.isVisible {
            parent.beginSheet(sheet)
        } else {
            counted = true
            standalone += 1
            if standalone == 1 { onStandaloneChange?(true) }
            sheet.center()
            sheet.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// A sheet's window for `--render`: not shown, sized to its content.
    static func offscreenWindow<V: View>(_ view: V) -> NSWindow {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        let size = host.view.fittingSize
        window.setContentSize(size)
        return window
    }
}
