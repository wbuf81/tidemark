import SwiftUI
import TidemarkCore

/// Something the calendar can't do, above the pane: the title in bold, then what it means. Never
/// a green tick; amber, with its own mark, so colour isn't the only cue.
struct ProblemBanner: View {
    let problems: [CalendarProblem]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(problems) { problem in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.amber)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(problem.title).font(Theme.font(12.5, .semibold)).foregroundStyle(Palette.bright)
                        if !problem.detail.isEmpty {
                            Text(problem.detail).font(Theme.font(12.5)).foregroundStyle(Palette.fg)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.amber.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.amber.opacity(0.55), lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Calendar problem. \(problem.title). \(problem.detail)")
            }
        }
    }
}
