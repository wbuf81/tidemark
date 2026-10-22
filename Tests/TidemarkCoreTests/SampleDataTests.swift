import Foundation
import Testing

/// The sample data is invented and neutral. The patterns are held as base64 so this file never matches itself.
@Suite struct SampleDataTests {
    private static func decode(_ s: String) -> String { String(decoding: Data(base64Encoded: s)!, as: UTF8.self) }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every text file under `folder` (relative to the repo), except this file and the fixture data.
    private static func textFiles(under folder: String) -> [URL] {
        let root = repoRoot.appendingPathComponent(folder)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker where url.lastPathComponent != "SampleDataTests.swift" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(url)
        }
        return files
    }

    private static func hits(_ pattern: String, in folders: [String]) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var found: [String] = []
        for folder in folders {
            for url in textFiles(under: folder) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    let s = String(line)
                    if regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
                        found.append("\(url.lastPathComponent):\(n + 1)")
                    }
                }
            }
        }
        return found
    }

    @Test func noPokemonAnywhere() {
        let pattern = Self.decode("UGlrYWNodXxDaGFyaXphcmR8QnVsYmFzYXVyfFBva8OpZGV4fFBva8OpbW9ufEd5bSBiYWRnZXN8QmVycnkgZmFybXxUcmFpbmVyIGNhcmRzfEVsaXRlIEZvdXI=")
        #expect(Self.hits(pattern, in: ["Sources", "Tests"]).isEmpty, "\(Self.hits(pattern, in: ["Sources", "Tests"]))")
    }

    @Test func noOwnersTagsInDemo() {
        let pattern = Self.decode("T3RoZXIgZGV2ZWxvcG1lbnQ=")
        #expect(Self.hits(pattern, in: ["Sources"]).isEmpty)
    }
}
