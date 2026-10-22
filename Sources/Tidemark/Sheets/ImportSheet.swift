import AppKit
import SwiftUI
import TidemarkCore

/// "Import your week calendar?": the old calendar that was found, and that its originals stay as
/// they are.
struct ImportSheet: View {
    var found: LegacyFound
    var notNow: () -> Void
    var importAll: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.importTitle) {
            SheetText(ShellCopy.importBody(found))
        } actions: {
            Button("Not now", action: notNow).keyboardShortcut(.cancelAction)
            Button(ShellCopy.importButton(weeks: found.weeks), action: importAll).keyboardShortcut(.defaultAction)
        }
    }

    static func present(over parent: NSWindow?, found: LegacyFound, notNow: @escaping () -> Void = {},
                        onImport: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.importTitle) { dismiss in
            ImportSheet(found: found, notNow: { dismiss(); notNow() }, importAll: { dismiss(); onImport() })
        }
    }
}
