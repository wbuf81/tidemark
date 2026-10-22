import AppKit
import SwiftUI
import TidemarkCore

/// "Get notified?": says what Tidemark would notify about before macOS asks.
struct NotificationsSheet: View {
    var notNow: () -> Void
    var proceed: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.notifyTitle) {
            SheetText(ShellCopy.notifyBody)
        } actions: {
            Button("Not now", action: notNow).keyboardShortcut(.cancelAction)
            Button("Continue", action: proceed).keyboardShortcut(.defaultAction)
        }
    }

    /// Shows the sheet; Continue runs `onContinue` (the system's own prompt) after it closes, Not now
    /// runs `onNotNow`.
    static func present(over parent: NSWindow?, onContinue: @escaping () -> Void, onNotNow: @escaping () -> Void = {}) {
        SheetPresenter.present(over: parent, title: ShellCopy.notifyTitle) { dismiss in
            NotificationsSheet(notNow: { dismiss(); onNotNow() }, proceed: { dismiss(); onContinue() })
        }
    }
}
