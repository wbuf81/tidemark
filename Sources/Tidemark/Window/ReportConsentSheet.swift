import SwiftUI
import TidemarkCore

/// The one-time question before Tidemark hands Claude Code a week's summary. Words from the
/// approved mockups.
struct ReportConsentSheet: View {
    var onCancel: () -> Void
    var onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Write the report with Claude Code?")
                .font(Theme.font(16, .bold)).foregroundStyle(Palette.bright)
                .accessibilityAddTraits(.isHeader)
            Text("Tidemark runs Claude Code on this Mac with last week’s summary: titles, hours, projects and commit messages. First messages go in only if you turned them on.")
                .font(Theme.font(13)).foregroundStyle(Palette.fg).lineSpacing(2)
            VStack(alignment: .leading, spacing: 4) {
                bullet("Claude Code can read that one summary file. It can’t edit files, run commands or go online.")
                bullet("It uses a little of your Claude plan, about one short message.")
            }
            Text("Needs Claude Code installed and signed in. Asked once; change it in Settings → Week.")
                .font(Theme.font(12)).foregroundStyle(Palette.dim)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(TidemarkWeekButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Write report", action: onWrite).buttonStyle(TidemarkWeekButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(width: 440, alignment: .leading)
        .background(Palette.tile)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.font(13)).foregroundStyle(Palette.fg)
        .padding(.leading, 4)
    }
}
