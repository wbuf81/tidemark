import Foundation
import Testing
@testable import TidemarkCore

@Suite struct FormattingTests {
    @Test func sameDayShowsTimeOnly() {
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 20), now: designNow) == "4:20 PM")
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 0), now: designNow) == "4 PM")
    }

    @Test func otherDayShowsWeekday() {
        #expect(fmt.dayTime(local(2026, 10, 9, 4, 0), now: designNow) == "Fri 4 AM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 0), now: designNow) == "Wed 9 PM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 30), now: designNow) == "Wed 9:30 PM")
    }

    // L5: the day without the clock follows the same rule: a bare weekday only within five days, the date from six.
    @Test func theDayAloneCarriesTheDateFromSixDaysAway() {
        let wed = local(2026, 10, 21, 11, 32)
        #expect(fmt.day(local(2026, 10, 21, 21, 0), now: wed) == "9 PM")
        #expect(fmt.day(local(2026, 10, 26, 9, 0), now: wed) == "Mon")
        #expect(fmt.day(local(2026, 10, 27, 9, 0), now: wed) == "Tue 27 Oct")
        #expect(fmt.day(local(2026, 10, 15, 11, 32), now: wed) == "Thu 15 Oct")
    }

    // S3.2: a bare weekday would read as this week's.
    @Test func sixDaysAwayCarriesTheDate() {
        let wed = local(2026, 10, 21, 11, 32)
        #expect(fmt.dayTime(local(2026, 9, 29, 11, 32), now: wed) == "Tue 29 Sep, 11:32 AM")
        #expect(fmt.dayTime(local(2026, 10, 16, 11, 32), now: wed) == "Fri 11:32 AM")          // 5 days back
        #expect(fmt.dayTime(local(2026, 10, 15, 11, 32), now: wed) == "Thu 15 Oct, 11:32 AM")   // 6 days back
        #expect(fmt.dayTime(local(2026, 10, 27, 9, 0), now: wed) == "Tue 27 Oct, 9 AM")          // 6 days ahead
        #expect(fmt.dayTime(local(2026, 10, 26, 9, 0), now: wed) == "Mon 9 AM")
        let f24 = Formatting(calendar: newYork, twentyFourHour: true)
        #expect(f24.dayTime(local(2026, 9, 29, 11, 32), now: wed) == "Tue 29 Sep, 11:32")
        #expect(fmt.spoken(local(2026, 10, 23, 4), now: wed) == "Friday 4 AM")
        #expect(fmt.spoken(local(2026, 9, 29, 11, 32), now: wed) == "Tuesday 29 September, 11:32 AM")
        #expect(fmt.spoken(local(2026, 10, 21, 16, 20), now: wed) == "4:20 PM")
    }

    @Test func twentyFourHourClock() {
        let f = Formatting(calendar: newYork, twentyFourHour: true)
        #expect(f.dayTime(local(2026, 10, 6, 16, 20), now: designNow) == "16:20")
        #expect(f.dayTime(local(2026, 10, 6, 16, 0), now: designNow) == "16:00")
        #expect(f.dayTime(local(2026, 10, 9, 4, 0), now: designNow) == "Fri 04:00")
    }

    @Test func theLocaleChoosesTheClock() {
        #expect(Formatting.prefers24Hour(Locale(identifier: "en_US")) == false)
        #expect(Formatting.prefers24Hour(Locale(identifier: "en_GB")) == true)
        #expect(Formatting.prefers24Hour(Locale(identifier: "de_DE")) == true)
    }

    @Test func compactDurations() {
        #expect(Formatting.compact(34 * 3600 + 20 * 60) == "1d 10h")
        #expect(Formatting.compact(3 * 3600 + 5 * 60) == "3h 5m")
        #expect(Formatting.compact(12 * 60) == "12m")
        #expect(Formatting.compact(2 * 3600) == "2h")
        #expect(Formatting.compact(-5) == "0m")
    }

    @Test func percents() {
        #expect(Formatting.percent(54.6) == "55%")
        #expect(Formatting.percent(0) == "0%")
    }

    @Test func monthDay() {
        #expect(fmt.monthDay(local(2026, 10, 16)) == "16 Oct")
    }

    @Test func durations() {
        #expect(Formatting.duration(0) == "0 min")
        #expect(Formatting.duration(45 * 60) == "45 min")
        #expect(Formatting.duration(59.7 * 60) == "1 h")
        #expect(Formatting.duration(27 * 3600) == "27 h")
        #expect(Formatting.duration(47.4 * 3600) == "47 h")
        #expect(Formatting.duration(51 * 3600) == "2 d 3 h")
        #expect(Formatting.duration(72 * 3600) == "3 d")
    }

    @Test func weekdayAndHour() {
        #expect(fmt.weekday(local(2026, 10, 17)) == "Sat")
        #expect(fmt.hour(local(2026, 10, 16, 13)) == "1 PM")
        #expect(fmt.hour(local(2026, 10, 16, 13, 30)) == "1:30 PM")
        #expect(Formatting(calendar: newYork, twentyFourHour: true).hour(local(2026, 10, 16, 13)) == "13:00")
    }
}

/// The widget's notes use a short clock: no space before am/pm, no minutes on the hour.
@Suite struct ShortTimeTests {
    @Test func twelveHour() {
        #expect(fmt.shortTime(local(2026, 10, 6, 14, 20)) == "2:20pm")
        #expect(fmt.shortTime(local(2026, 10, 6, 15, 0)) == "3pm")
        #expect(fmt.shortTime(local(2026, 10, 6, 0, 5)) == "12:05am")
    }

    @Test func twentyFourHour() {
        let f24 = Formatting(calendar: newYork, twentyFourHour: true)
        #expect(f24.shortTime(local(2026, 10, 6, 14, 20)) == "14:20")
        #expect(f24.shortTime(local(2026, 10, 6, 15, 0)) == "15:00")
    }
}
