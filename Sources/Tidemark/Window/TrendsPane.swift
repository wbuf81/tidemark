import SwiftUI
import TidemarkCore

/// Trends: one row per project (or tag) on one scale, over 8 weeks or a quarter. A row opens its
/// chart and weeks.
struct TrendsPane: View {
    @StateObject private var model: TrendsPaneModel
    private let onOpenWeek: (Date) -> Void

    init(store: CalendarStoring, settings: Settings, now: @escaping () -> Date, onOpenWeek: @escaping (Date) -> Void) {
        _model = StateObject(wrappedValue: TrendsPaneModel(store: store, settings: settings, now: now))
        self.onOpenWeek = onOpenWeek
    }

    /// For renders: a pane on a model that already exists.
    init(model: TrendsPaneModel, onOpenWeek: @escaping (Date) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onOpenWeek = onOpenWeek
    }

    var body: some View {
        TrendsView(model: model, onOpenWeek: onOpenWeek)
            .onAppear { model.reload() }
    }
}

private struct TrendsView: View {
    @ObservedObject var model: TrendsPaneModel
    let onOpenWeek: (Date) -> Void

    var body: some View {
        if let row = model.openRow {
            TrendDetail(row: row, trends: model.trends, grouping: model.grouping,
                        onBack: { model.open = nil }, onOpenWeek: onOpenWeek)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaneHeader(title: "Trends") {
                PaneButton(title: "8 weeks", primary: model.count == 8) { model.count = 8 }
                PaneButton(title: "Quarter", primary: model.count == 13) { model.count = 13 }
                PaneButton(title: "By tag", primary: model.grouping == .tag) {
                    model.grouping = model.grouping == .tag ? .project : .tag
                }
            }
            .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.trends.rows, id: \.name) { row in
                        TrendRowView(row: row, trends: model.trends, scale: model.scale, grouping: model.grouping) {
                            model.open = row.name
                        }
                    }
                    PaneNote(PanesCopy.trendsCaption(model.grouping)).padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tile)
    }
}

/// A row: the name, a bar per week, the total (mockup: `.mrow`).
private struct TrendRowView: View {
    let row: TrendRow
    let trends: TrendModel
    let scale: TimeInterval
    let grouping: TrendGrouping
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.bright)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 96, alignment: .leading)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(row.seconds.enumerated()), id: \.offset) { i, seconds in
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(Palette.blue)
                            .opacity(trends.lastIsPartial && i == row.seconds.count - 1 ? 0.45 : 1)
                            // The pale fill alone is under 3:1; the outline keeps the height readable.
                            .overlay { if trends.lastIsPartial && i == row.seconds.count - 1 { UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2).strokeBorder(Palette.blue, lineWidth: 1) } }
                            .frame(maxWidth: .infinity)
                            .frame(height: max(28 * seconds / scale, seconds > 0 ? 1 : 0))
                    }
                }
                .frame(height: 28, alignment: .bottom)
                .accessibilityHidden(true)
                Text(PanesCopy.hours(row.total))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.dim)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PanesCopy.trendRowVoiceOver(row, weeks: trends.weeks.count, grouping: grouping))
    }
}
