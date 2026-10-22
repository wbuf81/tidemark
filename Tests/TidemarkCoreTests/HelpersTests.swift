import Foundation
import Testing

@Suite struct HelpersTests {
    @Test func tempDirIsFreshAndEmpty() throws {
        let a = tempDir(), b = tempDir()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(a != b)
        #expect(try FileManager.default.contentsOfDirectory(atPath: a.path).isEmpty)
    }

    @Test func fakeHomeHasTheFoldersTheAppLooksIn() {
        let home = fakeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var isFolder: ObjCBool = false
        for path in ["Library/Application Support", ".claude/projects"] {
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path, isDirectory: &isFolder) && isFolder.boolValue)
        }
    }

    @Test func fixtureURLSitsNextToTheCallingTestFile() {
        let url = fixtureURL("example.json")
        #expect(url.lastPathComponent == "example.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Fixtures")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "TidemarkCoreTests")
    }
}
