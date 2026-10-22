import AppKit
import SwiftUI
import TidemarkCore

/// "Sign out of claude.ai?": says what signing out forgets and what stays, before it does it.
struct SignOutSheet: View {
    var cancel: () -> Void
    var signOut: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.signOutTitle) {
            SheetText(ShellCopy.signOutBody)
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            DangerButton(title: ShellCopy.signOutConfirm, action: signOut)
        }
    }

    /// Shows the sheet; `onSignOut` runs after it closes.
    static func present(over parent: NSWindow?, onSignOut: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.signOutTitle) { dismiss in
            SignOutSheet(cancel: dismiss, signOut: { dismiss(); onSignOut() })
        }
    }
}
