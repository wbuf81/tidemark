import SwiftUI
import TidemarkCore

/// Month: the weeks of one month, two items a day. Clicking a day opens that week.
struct MonthPane: View {
    @StateObject private var model: MonthPaneModel
    private let onOpenWeek: (Date) -> Void

    init(store: CalendarStoring, settings: Settings, now: @escaping () -> Date, onOpenWeek: @escaping (Date) -> Void) {
        _model = StateObject(wrappedValue: MonthPaneModel(store: store, settings: settings, now: now))
        self.onOpenWeek = onOpenWeek
    }

    /// For renders: a pane on a model that already exists.
    init(model: MonthPaneModel, onOpenWeek: @escaping (Date) -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onOpenWeek = onOpenWeek
    }

    var body: some View {
        MonthView(model: model, onOpenWeek: onOpenWeek)
            .onAppear { model.reload() }
    }
}

private struct MonthView: View {
    @ObservedObject var model: MonthPaneModel
    let onOpenWeek: (Date) -> Void
    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: PanesCopy.monthTitle(model.month.month, calendar: cal)) {
                PaneButton(title: PanesCopy.previousMonth(model.month.month, calendar: cal),
                           label: "Previous month") { model.previous() }
                PaneButton(title: PanesCopy.nextMonth(model.month.month, calendar: cal),
                           label: "Next month") { model.next() }
            }
            ScrollView([.vertical]) {
                grid.frame(minWidth: 420)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tile)
    }

    private var grid: some View {
        let weeks = model.month.weeks
        let headers = PanesCopy.weekdayHeaders(weeks.first ?? [], calendar: cal)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, name in
                    Text(name.uppercased())
                        .font(.system(size: 10)).tracking(0.4)
                        .foregroundStyle(Palette.faint)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) { line.frame(width: 1) }
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) { line.frame(height: 1) }
            .overlay(alignment: .bottom) { line.frame(height: 1) }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        DayCell(day: day, calendar: cal) { onOpenWeek(day.date) }
                    }
                }
            }
        }
        .overlay(alignment: .leading) { line.frame(width: 1) }
    }

    private var line: some View { Palette.line }
}

private struct DayCell: View {
    let day: MonthDay
    let calendar: Calendar
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.bright)
                if day.inMonth {
                    ForEach(Array(day.top.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 3) {
                            Rectangle().fill(Palette.c[min(max(item.colorIndex, 0), Palette.c.count - 1)]).frame(width: 2)
                            Text(item.title)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.fg)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(day.inMonth ? Color.clear : Palette.page)
            .overlay(alignment: .trailing) { Palette.line.frame(width: 1) }
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
            .overlay { if day.isToday { Rectangle().inset(by: 1).stroke(Palette.blue, lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(day.inMonth ? Palette.tile : Palette.page)
        .accessibilityLabel(PanesCopy.dayVoiceOver(day, calendar: calendar))
    }
}
