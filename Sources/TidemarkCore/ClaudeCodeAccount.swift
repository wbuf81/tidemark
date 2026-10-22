import Foundation

/// Which org Claude Code is signed into. Reads one field from Claude Code's config file
/// and nothing else.
public struct ClaudeCodeAccount: Sendable {
    var url: URL

    /// `~/.claude.json`, or the one inside `$CLAUDE_CONFIG_DIR` when that is set.
    public init(url: URL = ClaudePaths.accountFile(environment: ProcessInfo.processInfo.environment,
                                                   home: FileManager.default.homeDirectoryForCurrentUser)) {
        self.url = url
    }

    public init(environment: [String: String], home: URL) {
        self.url = ClaudePaths.accountFile(environment: environment, home: home)
    }

    public func currentOrg() -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["organizationUuid"] as? String
    }

    public func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
