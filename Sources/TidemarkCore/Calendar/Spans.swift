import Foundation

/// Time-span arithmetic for the calendar: overlaps count once, touching spans are one.
enum Spans {
    /// Sorted and merged; spans that touch (one ends where the next starts) become one.
    static func merged(_ spans: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for span in spans.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = result.last, span.start <= last.end {
                if span.end > last.end { result[result.count - 1] = DateInterval(start: last.start, end: span.end) }
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// Total seconds covered, overlaps counted once.
    static func union(_ spans: [DateInterval]) -> TimeInterval {
        merged(spans).reduce(0) { $0 + $1.duration }
    }

    /// The part of each span inside `window`; spans outside it are dropped. A zero-length span
    /// inside the window stays (the start is inclusive, the end exclusive for points).
    static func clip(_ spans: [DateInterval], to window: DateInterval) -> [DateInterval] {
        spans.compactMap { span in
            let start = max(span.start, window.start)
            let end = min(span.end, window.end)
            if end > start { return DateInterval(start: start, end: end) }
            if span.duration == 0, span.start >= window.start, span.start < window.end { return span }
            return nil
        }
    }
}
