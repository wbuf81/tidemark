import Foundation

enum UsageParserError: Error, Equatable {
    case notJSON
    case noWeeklyLimit
    case unreadableResetTime
}

/// Turns claude.ai's JSON into models. Tolerant: unknown fields are ignored, and the
/// older `five_hour` / `seven_day` fields fill in whatever `limits` doesn't provide.
public enum UsageParser {
    public static func orgs(from data: Data) throws -> [Org] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UsageParserError.notJSON
        }
        return list.compactMap { item in
            guard let id = item["uuid"] as? String, let name = item["name"] as? String else { return nil }
            return Org(id: id, name: name, billingType: item["billing_type"] as? String)
        }
    }

    /// What to show for a failed read of `answer`. An answer that can't be read at all says what
    /// came back: the status code and the first 200 characters, with nothing personal in what gets
    /// copied: every digit is masked as "#", anything that looks like an email address is
    /// "<email>", and the text of a JSON string value (a name, an id) is "…"; keys and structure stay.
    public static func problem(for error: Error, answer: Data, status: Int = 200) -> RefreshProblem {
        switch error {
        case UsageParserError.notJSON, UsageParserError.unreadableResetTime:
            return .changedShape(details: shapeDetails(status: status, body: answer))
        default:
            return RefreshProblem(error)
        }
    }

    public static func shapeDetails(status: Int, body: Data) -> String {
        var text = String(decoding: body.prefix(800), as: UTF8.self)
        text = text.replacingOccurrences(of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, with: "<email>", options: .regularExpression)
        if let first = text.first(where: { !$0.isWhitespace }), first == "{" || first == "[" { text = maskStringValues(text) }
        let masked = String(text.prefix(200).map { $0.isASCII && $0.isNumber ? "#" : $0 })
        return "HTTP \(status): \(masked)"
    }

    /// `json` with the text of every string value replaced by "…", keeping keys (a string followed by a colon).
    private static func maskStringValues(_ json: String) -> String {
        let chars = Array(json)
        var out = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "\"" else { out.append(chars[i]); i += 1; continue }
            var j = i + 1
            while j < chars.count, chars[j] != "\"" { j += chars[j] == "\\" ? 2 : 1 }
            let end = min(j, chars.count - 1)
            var k = end + 1
            while k < chars.count, chars[k].isWhitespace { k += 1 }
            let isKey = j < chars.count && k < chars.count && chars[k] == ":"
            out += isKey ? String(chars[i...end]) : (j < chars.count ? "\"…\"" : "\"…")
            i = end + 1
        }
        return out
    }

    public static func reading(from data: Data, org: String, at time: Date) throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParserError.notJSON
        }
        var session = 0.0
        var sessionResetsAt: Date?
        var week: Double?
        var weekResetsAt: Date?
        var scoped: [String: Double] = [:]
        var scopedResetsAt: [String: Date] = [:]

        if let fiveHour = root["five_hour"] as? [String: Any] {
            session = number(fiveHour["utilization"]) ?? 0
            sessionResetsAt = try resetTime(fiveHour["resets_at"])
        }
        if let sevenDay = root["seven_day"] as? [String: Any] {
            week = number(sevenDay["utilization"])
            weekResetsAt = try resetTime(sevenDay["resets_at"])
        }
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            let percent = number(limit["percent"])
            let reset = try resetTime(limit["resets_at"])
            switch limit["kind"] as? String {
            case "session":
                session = percent ?? 0
                sessionResetsAt = reset
            case "weekly_all":
                week = percent
                weekResetsAt = reset
            case "weekly_scoped":
                let model = (limit["scope"] as? [String: Any])?["model"] as? [String: Any]
                if let name = model?["display_name"] as? String, let percent {
                    scoped[name] = clamp(percent)
                    if let reset { scopedResetsAt[name] = reset }
                }
            default:
                break
            }
        }
        guard let week else { throw UsageParserError.noWeeklyLimit }
        return Reading(time: time, org: org, session: clamp(session), sessionResetsAt: sessionResetsAt,
                       week: clamp(week), weekResetsAt: weekResetsAt, scoped: scoped,
                       scopedResetsAt: scopedResetsAt)
    }

    /// claude.ai sends microseconds ("2026-10-06T15:20:00.408772+00:00"), which
    /// ISO8601DateFormatter can't read, and the fraction drifts between requests. Drop it
    /// and round to the nearest minute so one window always has one reset time.
    static func parseDate(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."),
           let end = trimmed[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            trimmed.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: trimmed) else { return nil }
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    /// nil when claude.ai sends null (no window open); an error when it sends a time we
    /// can't read, so a format change shows as stale rather than as "hasn't started".
    private static func resetTime(_ value: Any?) throws -> Date? {
        guard let text = value as? String else { return nil }
        guard let date = parseDate(text) else { throw UsageParserError.unreadableResetTime }
        return date
    }
    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}
