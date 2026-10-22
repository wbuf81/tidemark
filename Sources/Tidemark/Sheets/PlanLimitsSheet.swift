import AppKit
import SwiftUI
import TidemarkCore

/// "Turn on plan limits?": what turning claude.ai reading on means, with Anthropic's warning in
/// plain words. Neither button is the default, so Return doesn't turn it on; Escape cancels.
struct PlanLimitsSheet: View {
    var cancel: () -> Void
    var confirm: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.planLimitsTitle) {
            SheetText(ShellCopy.planLimitsIntro)
            ClaudeAIWarning()
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button(ShellCopy.planLimitsConfirm, action: confirm)
        }
    }

    /// Shows the sheet over `parent`; `onConfirm` runs after it closes.
    static func present(over parent: NSWindow?, onConfirm: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.planLimitsTitle) { dismiss in
            PlanLimitsSheet(cancel: dismiss, confirm: { dismiss(); onConfirm() })
        }
    }
}
