import AppKit
import SwiftUI
import TidemarkCore

/// "Delete all of Tidemark's data?": what goes, what doesn't, and a way to keep the calendar first
/// (Export…). The destructive button is red and never the default.
struct DeleteAllSheet: View {
    var cancel: () -> Void
    var export: () -> Void
    var delete: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.deleteTitle) {
            SheetText(ShellCopy.deleteBody)
            SheetText(ShellCopy.deleteNote, note: true)
            SheetText(ShellCopy.deleteKeeps, note: true)
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button("Export…", action: export)
            DangerButton(title: "Delete everything", action: delete)
        }
    }

    /// Shows the sheet; `onDelete` does the deleting after it closes.
    static func present(over parent: NSWindow?, home: URL, onDelete: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.deleteTitle) { dismiss in
            DeleteAllSheet(cancel: dismiss, export: { DataExport.run(home: home, over: parent) },
                           delete: { dismiss(); onDelete() })
        }
    }
}

/// Export…: a zip of the calendar folder, made with `ditto`, named `Tidemark calendar <date>.zip`.
@MainActor
enum DataExport {
    static func run(home: URL, over parent: NSWindow?) {
        let folder = AppIdentity.calendarURL(home: home)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export yet"
            alert.informativeText = "Tidemark hasn’t saved a calendar on this Mac."
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ShellCopy.exportFileName(on: Date())
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let target = panel.url else { return }
        Task {
            do {
                try await zip(folder, to: target)
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t export the calendar"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// Zips `folder` into `target` with `ditto -c -k`, off the main thread.
    nonisolated static func zip(_ folder: URL, to target: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--keepParent", folder.path, target.path]
                process.environment = ["PATH": "/usr/bin:/bin"]
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
