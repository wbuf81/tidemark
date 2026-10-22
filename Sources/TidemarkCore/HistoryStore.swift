import Foundation

/// The reading history: one JSON object per line. Corrupt lines are skipped, so a crash
/// mid-write costs one reading, not the history.
public final class HistoryStore: @unchecked Sendable {
    let url: URL
    /// Appends and prunes may come from different threads (prune runs in the background).
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(AppIdentity.supportFolderName)/history.jsonl")
    }

    public func append(_ readings: [Reading]) throws {
        guard !readings.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try Self.lines(readings)
        // A crash mid-write leaves a line with no end; start on a new line so the next reading isn't glued to it.
        if let existing = try? FileHandle(forReadingFrom: url) {
            defer { try? existing.close() }
            if let size = try? existing.seekToEnd(), size > 0, (try? existing.seek(toOffset: size - 1)) != nil,
               let last = try? existing.read(upToCount: 1), last != Data([0x0A]) {
                data = Data([0x0A]) + data
            }
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    public func load() -> [Reading] {
        lock.lock()
        defer { lock.unlock() }
        return (try? Self.readings(in: Data(contentsOf: url)))?.good ?? []
    }

    /// Rewrites the file without readings older than `cutoff` (and without lines that can't be
    /// read). Safe to call from any thread. A file with lines but no readable one is left as it
    /// is, so a damaged file is never wiped.
    public func prune(olderThan cutoff: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return }
        let parsed = Self.readings(in: data)
        guard !(parsed.good.isEmpty && parsed.bad > 0) else { return }
        let kept = parsed.good.filter { $0.time >= cutoff }
        guard kept.count != parsed.good.count || parsed.bad > 0 else { return }
        try Self.lines(kept).write(to: url, options: .atomic)
    }

    private static func readings(in data: Data) -> (good: [Reading], bad: Int) {
        var good: [Reading] = [], bad = 0
        for line in data.split(separator: 0x0A) where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) {
            if let reading = try? decoder.decode(Reading.self, from: Data(line)) { good.append(reading) } else { bad += 1 }
        }
        return (good, bad)
    }

    private static func lines(_ readings: [Reading]) throws -> Data {
        var data = Data()
        for reading in readings {
            data.append(try encoder.encode(reading))
            data.append(0x0A)
        }
        return data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
