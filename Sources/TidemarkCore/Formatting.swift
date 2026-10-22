import Foundation

/// Short time and number text used across the widget and Insights. The words are English, so
/// day names are too; the clock is 12- or 24-hour as the Mac's region prefers.
public struct Formatting: Sendable {
    var calendar: Calendar
    var twentyFourHour: Bool
    private let locale = Locale(identifier: "en_US_POSIX")

    /// The calendar follows the Mac's time zone as it changes.
    public init(calendar: Calendar = .autoupdatingCurrent, twentyFourHour: Bool = Formatting.prefers24Hour()) {
        self.calendar = calendar
        self.twentyFourHour = twentyFourHour
    }

    /// Whether a region writes times on a 24-hour clock.
    public static func prefers24Hour(_ locale: Locale = .autoupdatingCurrent) -> Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "a").contains("a")
    }

    /// A date this many days or more from `now` (before or after) carries its date, since a bare
    /// weekday would be taken for one this week.
    public static let datedFromDays = 6

    /// "4:20 PM" or "4 PM" on the same day as `now`; "Fri 4 AM" or "Wed 9:30 PM" otherwise; a date
    /// 6 or more days away carries it: "Tue 29 Sep, 11:32 AM". On a 24-hour clock: "16:20",
    /// "Fri 04:00", "Tue 29 Sep, 11:32".
    public func dayTime(_ date: Date, now: Date) -> String {
        let time = format(date, timePattern(date))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if isDated(date, now: now) { return "\(format(date, "EEE d MMM")), \(time)" }
        return "\(format(date, "EEE")) \(time)"
    }

    /// The day without the clock: the time itself when it is today, "Sat" within five days, "Fri 23 Oct" from six.
    public func day(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return format(date, timePattern(date)) }
        if isDated(date, now: now) { return format(date, "EEE d MMM") }
        return format(date, "EEE")
    }

    /// The same, spelled out for VoiceOver: "Friday 4 AM", "Tuesday 29 September, 11:32 AM".
    public func spoken(_ date: Date, now: Date) -> String {
        let time = format(date, timePattern(date))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if isDated(date, now: now) { return "\(format(date, "EEEE d MMMM")), \(time)" }
        return "\(format(date, "EEEE")) \(time)"
    }

    private func timePattern(_ date: Date) -> String {
        twentyFourHour ? "HH:mm" : calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
    }

    private func isDated(_ date: Date, now: Date) -> Bool {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        return abs(days) >= Self.datedFromDays
    }

    /// "16 Oct"
    public func monthDay(_ date: Date) -> String { format(date, "d MMM") }

    /// "1d 10h", "3h 5m", "2h" or "12m". Negative intervals read as "0m".
    static func compact(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m" }
        return "\(rest)m"
    }

    /// "55%": whole numbers, rounded.
    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// "Sat"
    public func weekday(_ date: Date) -> String { format(date, "EEE") }

    /// "1 PM" or "1:30 PM"; on a 24-hour clock "13:00".
    public func hour(_ date: Date) -> String {
        format(date, twentyFourHour ? "HH:mm" : calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a")
    }

    /// "2:20pm" or "3pm", for the widget's notes; on a 24-hour clock "14:20".
    func shortTime(_ date: Date) -> String {
        if twentyFourHour { return format(date, "HH:mm") }
        return format(date, calendar.component(.minute, from: date) == 0 ? "ha" : "h:mma").lowercased()
    }

    /// "45 min", "27 h" or "2 d 3 h": minutes under an hour, whole hours under two days.
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded()), 0)
        if minutes < 60 { return "\(minutes) min" }
        let hours = Int((interval / 3600).rounded())
        if hours < 48 { return "\(hours) h" }
        return hours % 24 == 0 ? "\(hours / 24) d" : "\(hours / 24) d \(hours % 24) h"
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
