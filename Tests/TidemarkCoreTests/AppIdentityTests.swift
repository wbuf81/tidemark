import Foundation
import Testing
@testable import TidemarkCore

/// The names and identifiers that never change after release.
@Suite struct AppIdentityTests {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func frozenValues() {
        #expect(AppIdentity.name == "Tidemark")
        #expect(AppIdentity.bundleID == "io.github.wbuf81.tidemark")
        #expect(AppIdentity.supportFolderName == "Tidemark")
        #expect(AppIdentity.hooksMarker == "# tidemark")
        #expect(AppIdentity.legacyHooksMarkers == ["# claude-dock"])
        #expect(AppIdentity.legacyBundleID == "com.wbuf81.claudedock")
        #expect(AppIdentity.legacySupportFolderName == "ClaudeDock")
        #expect(AppIdentity.webStoreID == UUID(uuidString: "8AD323F0-8465-42C6-98BD-6E670027E1DC"))
        #expect(AppIdentity.coworkLogFolderName == "Tidemark Log")
        #expect(AppIdentity.legacyCoworkLogFolderNames == ["Claude Calendar Log"])
        #expect(AppIdentity.weekSummaryFormat == "week-summary/1")
        #expect(AppIdentity.envPrefix == "TIDEMARK_")
        #expect(AppIdentity.releasesURL.absoluteString == "https://github.com/wbuf81/tidemark/releases")
    }

    @Test func foldersUnderHome() {
        let home = URL(fileURLWithPath: "/tmp/h")
        #expect(AppIdentity.supportURL(home: home).path == "/tmp/h/Library/Application Support/Tidemark")
        #expect(AppIdentity.calendarURL(home: home).path == "/tmp/h/Library/Application Support/Tidemark/calendar")
        #expect(AppIdentity.sessionsURL(home: home).path == "/tmp/h/Library/Application Support/Tidemark/sessions")
    }

    @Test func buildScriptStampsTheBundleID() throws {
        // build.sh writes Info.plist through scripts/write-info-plist.sh.
        let build = try String(contentsOf: repo.appendingPathComponent("build.sh"), encoding: .utf8)
        let plist = try String(contentsOf: repo.appendingPathComponent("scripts/write-info-plist.sh"), encoding: .utf8)
        #expect(build.contains("scripts/write-info-plist.sh"))
        #expect(plist.contains("<string>io.github.wbuf81.tidemark</string>"))
        #expect(!build.contains("NSAllowsLocalNetworking") && !plist.contains("NSAllowsLocalNetworking"))
    }

    @Test func noOldNameInSources() throws {
        let sources = repo.appendingPathComponent("Sources")
        let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            let path = file.path
            if file.lastPathComponent == "AppIdentity.swift" || path.contains("/Sources/TidemarkCore/Migration/") { continue }
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            if text.contains("claude dock") || text.contains("claudedock") { offenders.append(file.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "old name in: \(offenders.sorted())")
    }
}
