import Testing
@testable import TidemarkCore

@Suite struct HoursTextTests {
    @Test func writesHoursAndMinutes() {
        #expect(HoursText.format(0) == "0h 00m")
        #expect(HoursText.format(5430) == "1h 30m")
        #expect(HoursText.format(5490) == "1h 32m")
        #expect(HoursText.format(32700) == "9h 05m")
        #expect(HoursText.format(69600) == "19h 20m")
    }
}
