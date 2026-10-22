import Foundation

/// The calendar as the window, the widget and the shell use it. Frozen (docs/contracts.md).
///
/// Safe to call from any thread. Queries answer from the last saved state and never wait for a
/// refresh; `refresh` runs one at a time.
public protocol CalendarStoring: AnyObject, Sendable {
    func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel
    func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel
    func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel
    func nameRows(_ kind: NameKind, now: Date) -> [NameRow]
    var names: NameBook { get }
    @discardableResult func apply(_ change: NameChange) throws -> NameBook
    /// Puts back a whole name book, for Undo.
    func replaceNames(_ book: NameBook) throws
    /// The week in brief, for the widget's week band.
    func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary
    func save(_ report: WeekReport) throws
    func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary
    /// An old week calendar in `folder` (its `data/` or the folder holding it), if there is one.
    func findLegacy(in folder: URL) -> LegacyFound?
    func importLegacy(from folder: URL) throws -> ImportResult
    /// Like `importLegacy(from:)`, with the switches the user has chosen now (first messages come in only when theirs is on),
    /// whether or not a refresh has run with them yet.
    func importLegacy(from folder: URL, sources: SourceSwitches) throws -> ImportResult
    /// Everything the calendar keeps, except the copied originals of an import.
    func deleteAll() throws
    /// When Cowork last logged a task to `folder`, for "Logging works · last task 10:42 AM".
    func lastCoworkLogEntry(in folder: URL) -> Date?
    var problems: [CalendarProblem] { get }
}

extension CalendarStoring {
    public func importLegacy(from folder: URL, sources: SourceSwitches) throws -> ImportResult { try importLegacy(from: folder) }
}

/// The week's 8 local midnights, for stores that have nothing else to go on.
func plainWeekDays(containing day: Date, weekStart: WeekStart, calendar: Calendar = .current) -> [Date] {
    var cal = calendar
    switch weekStart {
    case .region: break
    case .monday: cal.firstWeekday = 2
    case .sunday: cal.firstWeekday = 1
    }
    let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? cal.startOfDay(for: day)
    return (0...7).map { cal.date(byAdding: .day, value: $0, to: start) ?? start }
}

func dayString(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}
