import Foundation

/// Where the app gets its calendar and report writer. Wave 0 returns empty stand-ins; the
/// engine batch replaces the two function bodies (and nothing else in this file).
public enum CalendarStores {
    public static func live(home: URL, environment: [String: String]) -> CalendarStoring {
        CalendarStore(folder: AppIdentity.calendarURL(home: home), home: home, environment: environment)
    }

    public static func reportWriter(home: URL, environment: [String: String]) -> @Sendable (WeekModel, Date) async -> Result<WeekReport, ReportFailure> {
        let report = ClaudeCodeReport(runner: SystemProcessRunner(environment: environment), home: home, environment: environment,
                                      candidates: ClaudeCodeReport.systemCandidates(home: home))
        return { week, now in await report.write(week, now: now) }
    }
}

/// A calendar with nothing in it: every week is empty and every change is ignored.
public final class EmptyCalendarStore: CalendarStoring, @unchecked Sendable {
    public init() {}

    public func week(containing day: Date, weekStart: WeekStart, now: Date) -> WeekModel {
        let days = plainWeekDays(containing: day, weekStart: weekStart)
        return WeekModel(start: days[0], days: days)
    }

    public func month(containing day: Date, weekStart: WeekStart, now: Date) -> MonthModel {
        let cal = Calendar.current
        let first = cal.dateInterval(of: .month, for: day)?.start ?? day
        var weeks: [[MonthDay]] = []
        var weekStartDay = plainWeekDays(containing: first, weekStart: weekStart)[0]
        repeat {
            let days = plainWeekDays(containing: weekStartDay, weekStart: weekStart).prefix(7).map {
                MonthDay(date: $0, inMonth: cal.isDate($0, equalTo: first, toGranularity: .month),
                         isToday: cal.isDate($0, inSameDayAs: now), seconds: 0, top: [])
            }
            weeks.append(days)
            weekStartDay = cal.date(byAdding: .day, value: 7, to: weekStartDay) ?? weekStartDay
        } while cal.isDate(weekStartDay, equalTo: first, toGranularity: .month)
        return MonthModel(month: first, weeks: weeks)
    }

    public func trends(endingWith day: Date, count: Int, grouping: TrendGrouping, weekStart: WeekStart, now: Date) -> TrendModel {
        let last = plainWeekDays(containing: day, weekStart: weekStart)[0]
        let weeks = (0..<max(count, 0)).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -7 * $0, to: last) }
        return TrendModel(weeks: weeks, rows: [], lastIsPartial: false)
    }

    public func nameRows(_ kind: NameKind, now: Date) -> [NameRow] { [] }
    public var names: NameBook { NameBook() }
    public func apply(_ change: NameChange) throws -> NameBook { NameBook() }
    public func replaceNames(_ book: NameBook) throws {}

    public func weekSummary(containing day: Date, weekStart: WeekStart, now: Date) -> WeekSummary {
        let days = plainWeekDays(containing: day, weekStart: weekStart)
        let week = WeekSummary.Week(start: dayString(days[0]), end: dayString(days[6]), seconds: 0, sessions: 0, commits: 0,
                                    days: [], projects: [], previousSeconds: nil)
        return WeekSummary(generated: now, week: week)
    }

    public func save(_ report: WeekReport) throws {}
    public func refresh(_ sources: SourceSwitches, now: Date) async -> RefreshSummary { RefreshSummary() }
    public func findLegacy(in folder: URL) -> LegacyFound? { nil }
    public func importLegacy(from folder: URL) throws -> ImportResult { ImportResult(weeks: 0, sessionsAdded: 0, sessionsKept: 0, mismatches: []) }
    public func deleteAll() throws {}
    public func lastCoworkLogEntry(in folder: URL) -> Date? { nil }
    public var problems: [CalendarProblem] { [] }
}
