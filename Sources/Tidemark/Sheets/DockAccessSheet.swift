import AppKit
import SwiftUI
import TidemarkCore

/// "Measure the Dock exactly?": says what the Accessibility permission is for before macOS asks for it.
struct DockAccessSheet: View {
    var cancel: () -> Void
    var proceed: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.dockAccessTitle) {
            SheetText(ShellCopy.dockAccessBody)
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button(ShellCopy.dockAccessConfirm, action: proceed).keyboardShortcut(.defaultAction)
        }
    }

    /// Shows the sheet; `onContinue` runs after it closes.
    static func present(over parent: NSWindow?, onContinue: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.dockAccessTitle) { dismiss in
            DockAccessSheet(cancel: dismiss, proceed: { dismiss(); onContinue() })
        }
    }
}
