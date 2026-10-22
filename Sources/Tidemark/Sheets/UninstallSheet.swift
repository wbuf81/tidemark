import AppKit
import SwiftUI
import TidemarkCore

/// "Uninstall Tidemark?": lists every file and setting Tidemark keeps, from `DataInventory`, and says
/// the app itself goes to the Bin by hand.
struct UninstallSheet: View {
    var items: [DataItem]
    var home: URL
    var cancel: () -> Void
    var export: () -> Void
    var uninstall: () -> Void

    var body: some View {
        SheetFrame(title: ShellCopy.uninstallTitle) {
            SheetText(ShellCopy.uninstallBody)
            SheetText(ShellCopy.uninstallList, note: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.what).font(.system(size: 12)).foregroundStyle(Palette.fg)
                            Text(ShellCopy.displayPath(item.path, home: home))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.dim)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: min(max(CGFloat(items.count) * 34 + 16, 60), 190))
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.page))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
            SheetText(ShellCopy.uninstallNote, note: true)
            SheetText(ShellCopy.uninstallExportNote, note: true)
        } actions: {
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            Button("Export…", action: export)
            DangerButton(title: "Uninstall Tidemark", action: uninstall)
        }
    }

    static func present(over parent: NSWindow?, home: URL, onUninstall: @escaping () -> Void) {
        SheetPresenter.present(over: parent, title: ShellCopy.uninstallTitle) { dismiss in
            // Only what is there: a list of things that don't exist would only worry people.
            UninstallSheet(items: DataInventory.items(home: home).filter { FileManager.default.fileExists(atPath: $0.path.path) },
                           home: home, cancel: dismiss,
                           export: { DataExport.run(home: home, over: parent) },
                           uninstall: { dismiss(); onUninstall() })
        }
    }
}
