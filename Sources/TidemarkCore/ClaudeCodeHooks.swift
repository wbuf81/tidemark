import Foundation

/// The hooks Tidemark adds to Claude Code's settings so Tidemark knows what Claude Code is
/// doing. Each writes only a mood and the time to a file named after the Claude Code process
/// (`$PPID` inside a hook), and never reads the hook's input or any transcript.
enum ClaudeCodeHooks {
    /// Marks our commands, so we find and remove exactly ours.
    static let marker = AppIdentity.hooksMarker

    /// (event, matcher, action) for every hook we add.
    static let events: [(event: String, matcher: String?, action: String)] = [
        ("SessionStart", nil, "idle"),
        ("UserPromptSubmit", nil, "thinking"),
        ("PreToolUse", "*", "tool"),
        ("PostToolUse", "*", "thinking"),
        ("Notification", "permission_prompt", "permission"),
        ("PermissionRequest", "*", "permission"),
        ("Stop", nil, "done"),
        ("SessionEnd", nil, "end"),
    ]

    /// The shell command for one action: a mood, or "end" to delete the session's file.
    static func command(_ action: String) -> String {
        let folder = #"d="$HOME/Library/Application Support/\#(AppIdentity.supportFolderName)/sessions""#
        let body = action == "end"
            ? #"rm -f "$d/$PPID" || true"#
            : #"mkdir -p "$d" && printf '%s %s\n' \#(action) "$(date +%s)" > "$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp" "$d/$PPID" || true"#
        return "cat >/dev/null; \(folder); \(body) \(marker)"
    }

    /// Today's group for one event.
    static func group(for entry: (event: String, matcher: String?, action: String)) -> [String: Any] {
        var group: [String: Any] = ["hooks": [["type": "command", "command": command(entry.action)]]]
        if let matcher = entry.matcher { group["matcher"] = matcher }
        return group
    }

    /// Ours (any of the markers, old or new) and whether it is exactly today's eight hooks.
    static func state(_ settings: [String: Any]) -> HookState {
        guard let hooks = settings["hooks"] as? [String: Any] else { return .notConnected }
        var found: [String] = []
        for (event, value) in hooks {
            for group in (value as? [[String: Any]] ?? []) where isOurs(group) { found.append("\(event)|\(canonical(group))") }
        }
        guard !found.isEmpty else { return .notConnected }
        let today = events.map { "\($0.event)|\(canonical(group(for: $0)))" }
        return found.sorted() == today.sorted() ? .connected : .outdated
    }

    /// `settings` with every group of ours (old markers too) swapped for today's eight, in one pass.
    static func update(_ settings: [String: Any]) -> [String: Any] { install(into: settings) }

    static func canonical(_ group: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: group, options: [.sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in (groups as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    /// `settings` with our hooks added after any already there. Installing twice changes nothing.
    static func install(into settings: [String: Any]) -> [String: Any] {
        var result = remove(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for entry in events {
            hooks[entry.event] = (hooks[entry.event] as? [[String: Any]] ?? []) + [group(for: entry)]
        }
        result["hooks"] = hooks
        return result
    }

    /// `settings` without our hooks; events and the "hooks" key we emptied are removed too.
    static func remove(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var result = settings
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]], groups.contains(where: isOurs) else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        result["hooks"] = hooks.isEmpty && !((settings["hooks"] as? [String: Any])?.isEmpty ?? false) ? nil : hooks
        return result
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String).map { command in ([marker] + AppIdentity.legacyHooksMarkers).contains { command.hasSuffix($0) } } == true }
    }
}
