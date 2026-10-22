import Foundation
@testable import TidemarkCore

/// Tests run in New York time so day names and midnights are deterministic.
let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A New York local time, e.g. `local(2026, 10, 6, 11, 32)`.
func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

/// The moment the design was drawn: Tuesday Oct 6 2026, 11:32 AM in New York.
let designNow = local(2026, 10, 6, 11, 32)

func reading(
    org: String = "personal", week: Double, weekResetsAt: Date?,
    session: Double = 0, sessionResetsAt: Date? = nil,
    at time: Date = designNow, scoped: [String: Double] = [:]
) -> Reading {
    Reading(time: time, org: org, session: session, sessionResetsAt: sessionResetsAt,
            week: week, weekResetsAt: weekResetsAt, scoped: scoped)
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.05) -> Bool { abs(a - b) <= tolerance }

/// A 12-hour clock, whatever the Mac running the tests prefers.
let fmt = Formatting(calendar: newYork, twentyFourHour: false)

/// The Forecast design's moment: Friday Oct 16 2026, 2:40 PM in New York.
let forecastNow = local(2026, 10, 16, 14, 40)

/// A fresh, empty folder under the temporary directory. Tests that make one remove it when done,
/// or leave it for the system to clear.
func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("TidemarkTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A temporary home folder with `Library/Application Support` and `.claude/projects` in it, so no
/// test reads or writes the real one.
func fakeHome() -> URL {
    let home = tempDir()
    for path in ["Library/Application Support", ".claude/projects"] {
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    return home
}

/// `Fixtures/<name>` in the folder of the test file that calls this.
func fixtureURL(_ name: String, file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent(name)
}
