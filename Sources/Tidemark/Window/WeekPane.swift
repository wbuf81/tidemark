import SwiftUI
import TidemarkCore

/// A header button as the mockups draw it: 12.5 pt, a 1 pt line, and a blue fill when primary.
struct TidemarkWeekButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(12.5, .medium))
            .foregroundStyle(primary ? (scheme == .dark ? Color(red: 0.043, green: 0.086, blue: 0.141) : .white) : Palette.fg)
            .padding(.horizontal, 11)
            .frame(minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Palette.blue : Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(primary ? Palette.blue : Palette.line, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

/// The brief card, then the grid, or the empty line.
struct WeekBody: View {
    let week: WeekModel
    let now: Date
    let calendar: Calendar
    var twentyFourHour = Formatting.prefers24Hour()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if week.isPartial {
                Text(WindowCopy.partialWeek)
                    .font(Theme.font(12.5)).foregroundStyle(Palette.dim)
            }
            BriefCard(week: week, now: now, calendar: calendar)
            if !week.items.isEmpty {
                WeekGrid(week: week, now: now, calendar: calendar, twentyFourHour: twentyFourHour)
            }
        }
    }
}

/// The Week section, or, until the user has chosen what Tidemark reads, the line that sends them to Settings → Week.
struct WeekGate: View {
    @ObservedObject var settings: Settings
    @ObservedObject var calendar: CalendarViewModel
    @ObservedObject var copy: CopyState
    var onReport: () -> Void
    var onCopy: () -> Void
    var onChooseSources: () -> Void
    var scrolls = true
    var twentyFourHour = Formatting.prefers24Hour()

    var body: some View {
        if settings.sourcesChosen {
            WeekPane(calendar: calendar, copy: copy, onReport: onReport, onCopy: onCopy, scrolls: scrolls, twentyFourHour: twentyFourHour)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(WindowCopy.sourcesNotChosen).font(Theme.font(13)).foregroundStyle(Palette.fg)
                Button(WindowCopy.sourcesNotChosenButton, action: onChooseSources).buttonStyle(TidemarkWeekButtonStyle(primary: true))
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
        }
    }
}

/// The Week section: the range and its buttons, then the week.
struct WeekPane: View {
    @ObservedObject var calendar: CalendarViewModel
    @ObservedObject var copy: CopyState
    var onReport: () -> Void
    var onCopy: () -> Void
    var scrolls = true
    var twentyFourHour = Formatting.prefers24Hour()

    private var cal: Calendar { .current }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 14) {
            header
            WeekBody(week: calendar.week, now: calendar.now(), calendar: cal, twentyFourHour: twentyFourHour)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private var header: some View {
        let title = Text(WindowCopy.range(calendar.week, calendar: cal))
            .font(Theme.font(21, .bold)).foregroundStyle(Palette.bright)
            .accessibilityAddTraits(.isHeader)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title.lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                buttons
            }
            // Too narrow for one line (the window's smallest size): the buttons go under the title.
            VStack(alignment: .leading, spacing: 8) {
                title
                buttons
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("‹ \(WindowCopy.dayMonth(calendar.previousWeekStart, calendar: cal))") { calendar.previousWeek() }
                .accessibilityLabel("Previous week, from \(WindowCopy.dayMonth(calendar.previousWeekStart, calendar: cal))")
                .buttonStyle(TidemarkWeekButtonStyle())
            if !calendar.isThisWeek {
                Button("\(WindowCopy.dayMonth(calendar.nextWeekStart, calendar: cal)) ›") { calendar.nextWeek() }
                    .accessibilityLabel("Next week, from \(WindowCopy.dayMonth(calendar.nextWeekStart, calendar: cal))")
                    .buttonStyle(TidemarkWeekButtonStyle())
            }
            // On this week it does nothing, and stays as the mockup draws it.
            Button("Today") { calendar.today() }
                .buttonStyle(TidemarkWeekButtonStyle())
            Button("Report") { onReport() }
                .buttonStyle(TidemarkWeekButtonStyle())
            Button(copy.copied ? "Copied" : "Copy summary") { onCopy() }
                .buttonStyle(TidemarkWeekButtonStyle(primary: true))
        }
        .fixedSize()
    }
}
