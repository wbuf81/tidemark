import Foundation

/// A calendar the app can point somewhere else, so turning demo data on or off changes every
/// window at once. Forwards every call to `target`.
public final class SwitchableCalendar: CalendarStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _target: CalendarStoring

    public init(_ target: CalendarStoring) {
        _target = target
    }

    public var target: CalendarStoring {
        get { lock.withLock { _target } }
        set { lock.withLock { _target = newValue } }
    }

    public func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel {
        target.week(containing: day, weekStart: weekStart, now: now)
    }
    public func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel {
        target.month(containing: day, weekStart: weekStart, now: now)
    }
    public func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        target.trends(endingWith: day, count: count, grouping: grouping, weekStart: weekStart, now: now)
    }
    public func nameRows(_ kind: NameKind, now: Date) -> [NameRow] { target.nameRows(kind, now: now) }
    public var names: NameBook { target.names }
    @discardableResult public func apply(_ change: NameChange) throws -> NameBook { try target.apply(change) }
    public func replaceNames(_ book: NameBook) throws { try target.replaceNames(book) }
    public func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary {
        target.weekSummary(containing: day, weekStart: weekStart, now: now)
    }
    public func save(_ report: WeekReport) throws { try target.save(report) }
    public func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary { await target.refresh(sources, now: now) }
    public func findLegacy(in folder: URL) -> LegacyFound? { target.findLegacy(in: folder) }
    public func importLegacy(from folder: URL) throws -> ImportResult { try target.importLegacy(from: folder) }
    public func importLegacy(from folder: URL, sources: SourceSwitches) throws -> ImportResult {
        try target.importLegacy(from: folder, sources: sources)
    }
    public func deleteAll() throws { try target.deleteAll() }
    public func lastCoworkLogEntry(in folder: URL) -> Date? { target.lastCoworkLogEntry(in: folder) }
    public var problems: [CalendarProblem] { target.problems }
}
