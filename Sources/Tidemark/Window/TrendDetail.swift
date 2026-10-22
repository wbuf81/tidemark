import SwiftUI
import TidemarkCore

/// One trend row opened: a bar chart per week with hours labels, then the weeks listed, each
/// opening that week.
struct TrendDetail: View {
    let row: TrendRow
    let trends: TrendModel
    let grouping: TrendGrouping
    let onBack: () -> Void
    let onOpenWeek: (Date) -> Void
    private let cal = Calendar.current

    private var peak: TimeInterval { max(row.seconds.max() ?? 0, 1) }
    private let chartHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: row.name) {
                PaneButton(title: "‹ Trends", label: "Back to Trends", action: onBack)
            }
            PaneNote(PanesCopy.detailSummary(row, weeks: trends.weeks.count))
            chart
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(trends.weeks.enumerated().reversed()), id: \.offset) { i, start in
                        weekRow(i, start)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tile)
    }

    private func isPartial(_ i: Int) -> Bool { trends.lastIsPartial && i == trends.weeks.count - 1 }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(row.seconds.enumerated()), id: \.offset) { i, seconds in
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(PanesCopy.hours(seconds))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Palette.dim)
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(Palette.blue)
                        .opacity(isPartial(i) ? 0.45 : 1)
                        .overlay { if isPartial(i) { UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).strokeBorder(Palette.blue, lineWidth: 1) } }
                        .frame(height: max((chartHeight - 40) * seconds / peak, seconds > 0 ? 1 : 0))
                    Text(trends.weeks.indices.contains(i) ? shortDay(trends.weeks[i]) : "")
                        .font(.system(size: 10)).foregroundStyle(Palette.faint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: chartHeight)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.tile))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chart of \(row.name), one bar per week. \(PanesCopy.detailSummary(row, weeks: trends.weeks.count)).")
    }

    private func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func weekRow(_ i: Int, _ start: Date) -> some View {
        let seconds = row.seconds.indices.contains(i) ? row.seconds[i] : 0
        return Button { onOpenWeek(start) } label: {
            HStack {
                Text(PanesCopy.detailWeekLabel(start: start, isPartial: isPartial(i), calendar: cal))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.bright)
                Spacer()
                Text(PanesCopy.hours(seconds))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.dim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PanesCopy.detailWeekVoiceOver(start: start, seconds: seconds, isPartial: isPartial(i), calendar: cal))
    }
}
