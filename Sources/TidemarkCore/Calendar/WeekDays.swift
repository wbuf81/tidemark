import Foundation

/// The week's day boundaries, in the calendar's time zone.
enum WeekDays {
    /// Eight local midnights: the seven days of the week and the midnight that ends it. Days are
    /// real local days, so a DST day is 23 or 25 hours long.
    static func midnights(containing day: Date, weekStart: WeekStart, calendar: Calendar) -> [Date] {
        let first: Int
        switch weekStart {
        case .region: first = calendar.firstWeekday
        case .monday: first = 2
        case .sunday: first = 1
        }
        let today = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: today)
        let back = (weekday - first + 7) % 7
        let start = calendar.date(byAdding: .day, value: -back, to: today) ?? today
        return (0...7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
    }
}
