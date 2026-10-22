import Foundation

/// Where Claude Code keeps its files: `$CLAUDE_CONFIG_DIR` when it's set, else `~/.claude`.
public enum ClaudePaths {
    public static func configDir(environment: [String: String], home: URL) -> URL {
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    public static func projectsDir(environment: [String: String], home: URL) -> URL {
        configDir(environment: environment, home: home).appendingPathComponent("projects", isDirectory: true)
    }

    public static func settingsFile(environment: [String: String], home: URL) -> URL {
        configDir(environment: environment, home: home).appendingPathComponent("settings.json")
    }

    /// `.claude.json`: inside `$CLAUDE_CONFIG_DIR` when it's set, else beside `~/.claude`.
    public static func accountFile(environment: [String: String], home: URL) -> URL {
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return configDir(environment: environment, home: home).appendingPathComponent(".claude.json")
        }
        return home.appendingPathComponent(".claude.json")
    }
}
