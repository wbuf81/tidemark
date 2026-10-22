import AppKit
import SwiftUI
import TidemarkCore

/// "Show what Claude Code is doing?": says exactly what Add hooks will write into Claude Code's
/// settings before it writes anything. Also builds the alert for when the change fails.
struct HooksSheet: View {
    var state: HookState
    var file = ShellCopy.defaultSettingsFile
    var notNow: () -> Void
    var proceed: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.hooksTitle) {
            SheetText(ShellCopy.hooksIntro)
            CodeBox(lines: [ShellCopy.hooksFileLine(file: file)] + ShellCopy.hooksAdded.map { "+ " + $0 }, addedFrom: 1)
            SheetText(ShellCopy.hooksNote, note: true)
        } actions: {
            Button("Not now", action: notNow).keyboardShortcut(.cancelAction)
            Button(state == .outdated ? "Update hooks" : "Add hooks", action: proceed).keyboardShortcut(.defaultAction)
        }
    }

    static func present(over parent: NSWindow?, state: HookState, file: String = ShellCopy.defaultSettingsFile, onConfirm: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.hooksTitle) { dismiss in
            HooksSheet(state: state, file: file, notNow: dismiss, proceed: { dismiss(); onConfirm() })
        }
    }
}

/// The alert for a failed change to Claude Code's settings: why, what to do, and a way to the file.
@MainActor
enum HooksFailureAlert {
    /// `reason` is a sentence (the hook file's own words, or macOS's for any other error).
    static func make(reason: String, unreadable: Bool = true, file: String = ShellCopy.defaultSettingsFile) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = ShellCopy.hooksFailureTitle(file: file)
        alert.informativeText = ShellCopy.hooksFailureBody(reason: reason, unreadable: unreadable)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        return alert
    }

    /// The sentence for an error from the hook file.
    static func reason(_ error: Error) -> String {
        if case HookFileError.unreadable(let why) = error { return why }
        return error.localizedDescription
    }

    /// Runs the alert; "Show in Finder" reveals `settings`.
    static func run(_ error: Error, settings: URL, file: String = ShellCopy.defaultSettingsFile) {
        var unreadable = false
        if case HookFileError.unreadable = error { unreadable = true }
        let alert = make(reason: reason(error), unreadable: unreadable, file: file)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([settings])
        }
    }
}
