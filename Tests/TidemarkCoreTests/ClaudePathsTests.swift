import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ClaudePathsTests {
    let home = URL(fileURLWithPath: "/tmp/h", isDirectory: true)

    @Test func honoursClaudeConfigDir() {
        let env = ["CLAUDE_CONFIG_DIR": "/tmp/c"]
        #expect(ClaudePaths.configDir(environment: env, home: home).path == "/tmp/c")
        #expect(ClaudePaths.projectsDir(environment: env, home: home).path == "/tmp/c/projects")
        #expect(ClaudePaths.settingsFile(environment: env, home: home).path == "/tmp/c/settings.json")
        #expect(ClaudePaths.accountFile(environment: env, home: home).path == "/tmp/c/.claude.json")
    }

    @Test func defaultsUnderHome() {
        #expect(ClaudePaths.configDir(environment: [:], home: home).path == "/tmp/h/.claude")
        #expect(ClaudePaths.projectsDir(environment: [:], home: home).path == "/tmp/h/.claude/projects")
        #expect(ClaudePaths.settingsFile(environment: [:], home: home).path == "/tmp/h/.claude/settings.json")
        #expect(ClaudePaths.accountFile(environment: [:], home: home).path == "/tmp/h/.claude.json")
    }
}
