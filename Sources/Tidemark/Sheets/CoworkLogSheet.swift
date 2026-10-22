import AppKit
import SwiftUI
import TidemarkCore

/// "Log Cowork tasks for Tidemark": Cowork can't tell other apps what it did, so the user pastes an
/// instruction that makes it append a line to a log file in a folder they share, and Tidemark reads
/// that file and nothing else.
@MainActor
final class CoworkLogModel: ObservableObject {
    @Published var folder: URL?
    /// Shown under the folder: waiting for the first line, or when the last task was.
    @Published var status: String?
    @Published var copied = false
    let lastEntry: (URL) -> Date?
    let formatting: Formatting

    init(folder: URL?, lastEntry: @escaping (URL) -> Date?, formatting: Formatting = Formatting(), now: Date = Date()) {
        self.folder = folder
        self.lastEntry = lastEntry
        self.formatting = formatting
        recheck(now: now)
    }

    func recheck(now: Date = Date()) {
        status = folder.map { ShellCopy.coworkStatus(lastTask: lastEntry($0), formatting: formatting, now: now) }
    }
}

struct CoworkLogSheet: View {
    @ObservedObject var state: CoworkLogModel
    var instruction: String
    var cancel: () -> Void
    var copy: () -> Void
    var choose: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.coworkTitle) {
            SheetText(ShellCopy.coworkIntro)
            VStack(alignment: .leading, spacing: 4) {
                step(1, ShellCopy.coworkStep1)
                step(2, ShellCopy.coworkStep2)
            }
            CodeBox(lines: instruction.components(separatedBy: "\n"))
            if let folder = state.folder {
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 12)).foregroundStyle(Palette.fg).lineLimit(1).truncationMode(.middle)
                    SheetText(ShellCopy.coworkSuggestion(), note: true)
                    if let status = state.status { SheetText(status, note: true) }
                }
            }
            SheetText(ShellCopy.coworkNote, note: true)
        } actions: {
            Button(state.folder == nil ? "Cancel" : "Done", action: cancel).keyboardShortcut(.cancelAction)
            Button(state.copied ? "Copied" : "Copy instruction") { copy(); state.copied = true }
            Button(state.folder == nil ? "Choose folder…" : "Choose another…", action: choose)
                .keyboardShortcut(state.folder == nil ? .defaultAction : nil)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").font(.system(size: 13)).foregroundStyle(Palette.fg).frame(width: 14, alignment: .trailing)
            SheetText(text)
        }
    }

    /// Shows the sheet. `onChoose` saves the folder; the sheet then waits for Cowork's first line.
    static func present(over parent: NSWindow?, folder: URL?, lastEntry: @escaping (URL) -> Date?,
                        onChoose: @escaping (URL) -> Void) {
        let state = CoworkLogModel(folder: folder, lastEntry: lastEntry)
        let text = CoworkInstruction.text(folderName: AppIdentity.coworkLogFolderName)
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { state.recheck() }
        }
        SheetPresenter.present(over: parent, title: ShellCopy.coworkTitle) { dismiss in
            CoworkLogSheet(state: state, instruction: text, cancel: { timer.invalidate(); dismiss() },
                           copy: {
                               NSPasteboard.general.clearContents()
                               NSPasteboard.general.setString(text, forType: .string)
                           },
                           choose: {
                               let panel = NSOpenPanel()
                               panel.canChooseFiles = false
                               panel.canChooseDirectories = true
                               panel.canCreateDirectories = true
                               panel.prompt = "Choose"
                               panel.message = "Choose a folder you share with Cowork."
                               guard panel.runModal() == .OK, let picked = panel.url else { return }
                               // The log lives in "Tidemark Log" inside the folder they chose: made now, and read from there.
                               let url: URL
                               do {
                                   url = try CoworkLogFolder.prepare(chosen: picked)
                               } catch {
                                   let alert = NSAlert()
                                   alert.messageText = "Couldn’t make the “\(AppIdentity.coworkLogFolderName)” folder"
                                   alert.informativeText = error.localizedDescription
                                   alert.runModal()
                                   return
                               }
                               state.folder = url
                               state.recheck()
                               onChoose(url)
                           })
        }
    }
}
