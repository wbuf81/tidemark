import Foundation

/// Where overlapping sessions sit side by side on a day's column.
public enum WeekLayout {
    /// The most lanes a day shows side by side; more overlaps share the last lane.
    public static let maxLanes = 4

    /// Per item id: its lane and how many lanes its group of overlapping items has. Items that
    /// overlap in time on the same day (any of their spans) share one group, so a chain of
    /// overlaps is as wide as its busiest point; separate items get one lane.
    public static func lanes(_ items: [WeekItem]) -> [String: (lane: Int, lanes: Int)] {
        var out: [String: (lane: Int, lanes: Int)] = [:]
        for (_, day) in Dictionary(grouping: items, by: \.day) {
            let sorted = day.sorted { (start($0), $0.id) < (start($1), $1.id) }
            var laneItems: [[WeekItem]] = []   // items placed in each lane of the current group
            var group: [(id: String, lane: Int)] = []
            var groupEnd = Date.distantPast
            func close() {
                let count = min(laneItems.count, maxLanes)
                for member in group { out[member.id] = (min(member.lane, maxLanes - 1), max(count, 1)) }
                laneItems = []
                group = []
            }
            for item in sorted {
                if !group.isEmpty, start(item) >= groupEnd { close() }
                var lane = laneItems.firstIndex { placed in !placed.contains { overlaps($0, item) } }
                if lane == nil {
                    if laneItems.count < maxLanes { laneItems.append([]); lane = laneItems.count - 1 } else { lane = maxLanes - 1 }
                }
                let chosen = lane ?? 0
                laneItems[chosen].append(item)
                group.append((item.id, chosen))
                groupEnd = max(groupEnd, end(item))
            }
            close()
        }
        return out
    }

    /// The items that had no lane of their own (the fifth overlap onward), for their VoiceOver text.
    public static func hiddenBehind(_ items: [WeekItem]) -> [String: [WeekItem]] {
        var out: [String: [WeekItem]] = [:]
        let placed = lanes(items)
        for (_, day) in Dictionary(grouping: items, by: \.day) {
            let atLast = day.filter { placed[$0.id]?.lane == maxLanes - 1 && placed[$0.id]?.lanes == maxLanes }
            guard atLast.count > 1 else { continue }
            for item in atLast {
                let others = atLast.filter { $0.id != item.id && overlaps($0, item) }
                if !others.isEmpty { out[item.id] = others }
            }
        }
        return out
    }

    /// Hours from `firstHour` o'clock to `date` on `day`, by the wall clock (hour and minute), not by
    /// elapsed time, so a 23 or 25 hour day still puts 9:00 at the 9 o'clock row. A time after the
    /// day ends counts as the day's end.
    public static func hourOffset(_ date: Date, onDay day: Date, firstHour: Int, calendar: Calendar) -> Double {
        let midnight = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight.addingTimeInterval(86400)
        if date >= next { return Double(24 - firstHour) }
        if date <= midnight { return Double(-firstHour) }
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600 - Double(firstHour)
    }

    static func start(_ item: WeekItem) -> Date { item.spans.map(\.start).min() ?? .distantPast }
    static func end(_ item: WeekItem) -> Date { item.spans.map(\.end).max() ?? .distantPast }

    static func overlaps(_ a: WeekItem, _ b: WeekItem) -> Bool {
        a.spans.contains { x in b.spans.contains { y in x.start < y.end && y.start < x.end } }
    }
}
