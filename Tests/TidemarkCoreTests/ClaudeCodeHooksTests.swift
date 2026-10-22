import Foundation
import Testing
@testable import TidemarkCore

@Suite struct ClaudeCodeHooksTests {
    /// Another status app's hooks on some of the same events.
    let theirs: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "node other/update.js stop"]]]],
            "PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "node other/update.js pre"]]]],
        ],
    ]

    func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

    @Test func commandsWriteOnlyTheMoodAndTime() {
        let tool = ClaudeCodeHooks.command("tool")
        #expect(tool.hasPrefix("cat >/dev/null;"))
        #expect(tool.contains("printf '%s %s\\n' tool"))
        #expect(tool.contains("$PPID"))
        #expect(tool.hasSuffix(ClaudeCodeHooks.marker))
        // A failed write must never show as a hook error in Claude Code.
        #expect(tool.hasSuffix("|| true \(ClaudeCodeHooks.marker)"))
        #expect(tool.contains("Application Support/Tidemark/sessions"))
        #expect(!tool.contains("Claude"))
        #expect(ClaudeCodeHooks.command("end").contains("rm -f"))
        // Parallel hooks of one session must not share a temporary name.
        #expect(tool.contains(#""$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp""#))
    }

    @Test func installsIntoNothing() {
        let installed = ClaudeCodeHooks.install(into: [:])
        let hooks = installed["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                     "Notification", "PermissionRequest", "Stop", "SessionEnd"])
        let notification = (hooks["Notification"] as! [[String: Any]])[0]
        #expect(notification["matcher"] as? String == "permission_prompt")
        #expect(ClaudeCodeHooks.isInstalled(installed))
        #expect(!ClaudeCodeHooks.isInstalled([:]))
    }

    // Review focus: other apps' hooks stay, in order, and come back untouched.
    @Test func keepsOtherHooksAndRemovesCleanly() {
        let installed = ClaudeCodeHooks.install(into: theirs)
        let stop = (installed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "node other/update.js stop")
        #expect(installed["model"] as? String == "opus")
        #expect(same(ClaudeCodeHooks.remove(from: installed), theirs))
        #expect(same(ClaudeCodeHooks.remove(from: ClaudeCodeHooks.install(into: [:])), [:]))
    }

    @Test func installingTwiceAddsNothing() {
        let once = ClaudeCodeHooks.install(into: theirs)
        #expect(same(ClaudeCodeHooks.install(into: once), once))
    }

    // MARK: The file on disk

    func temp() -> (settings: URL, support: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir.appendingPathComponent("settings.json"), dir.appendingPathComponent("support"))
    }

    @Test func connectThenDisconnectIsByteIdentical() throws {
        let (settings, support) = temp()
        let original = Data("{\n    \"model\" : \"opus\",   \"hooks\": {}\n}\n".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try file.disconnect()
        #expect(!file.isConnected())
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func disconnectAfterOtherEditsKeepsThem() throws {
        let (settings, support) = temp()
        try Data("{}".utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        var edited = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        edited["model"] = "sonnet"
        try JSONSerialization.data(withJSONObject: edited).write(to: settings)
        try file.disconnect()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(after["model"] as? String == "sonnet")
        #expect(!ClaudeCodeHooks.isInstalled(after))
    }

    @Test func missingOrEmptyFileCountsAsEmpty() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try Data().write(to: settings)
        try file.connect()
        #expect(file.isConnected())
    }

    // Review focus: JSON with comments or trailing commas must not be overwritten.
    @Test func refusesAFileItCantRead() throws {
        let (settings, support) = temp()
        let original = Data("{ \"model\": \"opus\", // mine\n }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        #expect(throws: HookFileError.self) { try file.connect() }
        #expect(try Data(contentsOf: settings) == original)
        #expect(!file.isConnected())
    }

    // An unreadable file is not a missing one: never write over it, never delete it.
    @Test func leavesAnUnreadableFileAlone() throws {
        let (settings, support) = temp()
        let original = Data("{ \"model\": \"opus\" }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path) }
        guard (try? Data(contentsOf: settings)) == nil else { return }   // running as root: can't test
        #expect(throws: HookFileError.self) { try file.connect() }
        #expect(throws: HookFileError.self) { try file.disconnect() }
        #expect(!file.isConnected())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func disconnectingNeverConnectedChangesNothing() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.disconnect()
        #expect(!FileManager.default.fileExists(atPath: settings.path))
        let original = Data("{\n  \"model\":   \"opus\"\n}".utf8)
        try original.write(to: settings)
        try file.disconnect()
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func missingFileComesBackMissing() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(FileManager.default.fileExists(atPath: settings.path))
        try file.disconnect()
        #expect(!FileManager.default.fileExists(atPath: settings.path))
    }

    @Test func followsASymlinkedSettingsFile() throws {
        let (settings, support) = temp()
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let real = other.appendingPathComponent("real.json")
        let original = Data("{ \"model\": \"opus\" }".utf8)
        try original.write(to: real)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: real)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: settings.path)) != nil)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as! [String: Any]
        #expect(ClaudeCodeHooks.isInstalled(parsed))
        try file.disconnect()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: settings.path)) != nil)
        #expect(try Data(contentsOf: real) == original)
    }

    @Test func legacyMarkerIsStillOurs() {
        let legacy: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "cat >/dev/null; true # claude-dock"]]]]]]
        #expect(ClaudeCodeHooks.isInstalled(legacy))
        #expect(!ClaudeCodeHooks.isInstalled(theirs))
        let mixed: [String: Any] = ["hooks": ["Stop": [
            ["hooks": [["type": "command", "command": "node mine/own.js stop"]]],
            ["hooks": [["type": "command", "command": "true # claude-dock"]]],
        ]]]
        let cleaned = ClaudeCodeHooks.remove(from: mixed)
        let kept = ((cleaned["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? []
        #expect(kept.count == 1)
        #expect(!ClaudeCodeHooks.isInstalled(cleaned))
    }

    // MARK: State and update

    /// What the old app's install looked like: its folder, its marker.
    func legacyGroups() -> [String: Any] {
        var hooks: [String: Any] = [:]
        for entry in ClaudeCodeHooks.events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": "cat >/dev/null; d=\"$HOME/Library/Application Support/ClaudeDock/sessions\"; true # claude-dock"]]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = [group]
        }
        return ["hooks": hooks]
    }

    @Test func legacyMarkerIsOurs() {
        #expect(ClaudeCodeHooks.state(legacyGroups()) == .outdated)
        #expect(ClaudeCodeHooks.state(theirs) == .notConnected)
        #expect(ClaudeCodeHooks.state(ClaudeCodeHooks.install(into: theirs)) == .connected)
    }

    @Test func outdatedWhenTheFolderChanged() throws {
        var settings = ClaudeCodeHooks.install(into: [:])
        var hooks = settings["hooks"] as! [String: Any]
        var stop = hooks["Stop"] as! [[String: Any]]
        stop[0]["hooks"] = [["type": "command", "command": "mkdir -p ~/Library/Application\\ Support/OldName/sessions # tidemark"]]
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        #expect(ClaudeCodeHooks.state(settings) == .outdated)
        #expect(ClaudeCodeHooks.state(ClaudeCodeHooks.update(settings)) == .connected)
        // A ninth group of ours is not today's either.
        var extra = ClaudeCodeHooks.install(into: [:])
        var h = extra["hooks"] as! [String: Any]
        h["Stop"] = (h["Stop"] as! [[String: Any]]) + [["hooks": [["type": "command", "command": "true # tidemark"]]]]
        extra["hooks"] = h
        #expect(ClaudeCodeHooks.state(extra) == .outdated)
    }

    @Test func removeTakesLegacyToo() {
        let mixed = legacyGroups().merging(["model": "opus"]) { a, _ in a }
        let cleaned = ClaudeCodeHooks.remove(from: mixed)
        #expect(same(cleaned, ["model": "opus"]))
    }

    // Review focus: the user's own hooks, key order and spacing don't move.
    @Test func updateSwapsOnlyOurs() throws {
        let (settings, support) = temp()
        let legacyCommand = "cat >/dev/null; true # claude-dock"
        let original = """
        {
            "zeta": 1,   "model" : "opus",
            "hooks": {
                "Stop": [
                    {"hooks": [{"type":"command","command":"node other/update.js stop"}]},
                    {"hooks": [{"type": "command", "command": "\(legacyCommand)"}]}
                ],
                "Weird": [{"hooks": [{"type": "command", "command": "true # claude-dock"}]}],
                "Mine": [ {"x": 1} ]
            },
            "alpha": [1, 2,3]
        }

        """
        try Data(original.utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        #expect(file.state() == .outdated)
        try file.update()
        #expect(file.state() == .connected)
        let text = try String(contentsOf: settings, encoding: .utf8)
        // Everything outside the hooks block, and the user's own groups, are byte for byte as before.
        #expect(text.hasPrefix("{\n    \"zeta\": 1,   \"model\" : \"opus\",\n    \"hooks\": {"))
        #expect(text.hasSuffix("},\n    \"alpha\": [1, 2,3]\n}\n"))
        #expect(text.contains("{\"hooks\": [{\"type\":\"command\",\"command\":\"node other/update.js stop\"}]}"))
        #expect(text.contains("\"Mine\": [\n            {\"x\": 1}\n        ]"))
        #expect(!text.contains("claude-dock"))
        #expect(!text.contains("\"Weird\""))
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let hooks = parsed["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == ["Stop", "Mine", "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                     "Notification", "PermissionRequest", "SessionEnd"])
        let stop = hooks["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "node other/update.js stop")
        // Updating again changes nothing and makes no second backup.
        try file.update()
        #expect(try String(contentsOf: settings, encoding: .utf8) == text)
        let backups = try FileManager.default.contentsOfDirectory(atPath: support.path).filter { $0.hasPrefix("settings-before-update-") }
        #expect(backups.count == 1)
        #expect(try String(contentsOf: support.appendingPathComponent(backups[0]), encoding: .utf8) == original)
    }

    @Test func updateAddsAHooksKeyWhenOnlyAnOutdatedGroupIsElsewhere() throws {
        // Ours under an event that today's list doesn't use is removed, and its emptied event goes with it.
        let (settings, support) = temp()
        try Data(#"{"model":"opus","hooks":{"OldEvent":[{"hooks":[{"type":"command","command":"x # claude-dock"}]}]}}"#.utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.update()
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(parsed["model"] as? String == "opus")
        #expect((parsed["hooks"] as! [String: Any])["OldEvent"] == nil)
        #expect(file.state() == .connected)
    }

    @Test func updateIsOneWrite() throws {
        let (settings, support) = temp()
        try Data(try JSONSerialization.data(withJSONObject: legacyGroups())).write(to: settings)
        let before = try Data(contentsOf: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.update()
        // One backup of the file as it was, then the one new settings file: no connect/disconnect leftovers.
        let names = try FileManager.default.contentsOfDirectory(atPath: support.path).sorted()
        #expect(names.count == 1 && names[0].hasPrefix("settings-before-update-") && names[0].hasSuffix(".json"))
        #expect(try Data(contentsOf: support.appendingPathComponent(names[0])) == before)
        #expect(file.state() == .connected)
    }

    @Test func malformedSettingsIsNeverWritten() throws {
        let (settings, support) = temp()
        let original = Data("{ \"hooks\": {}, // mine\n \"x\": 1, }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        #expect(throws: HookFileError.self) { try file.update() }
        #expect(try Data(contentsOf: settings) == original)
        #expect(!FileManager.default.fileExists(atPath: support.path))
        #expect(file.state() == .notConnected)
    }

    // The first Add hooks: everything that isn't our groups stays as the user wrote it.
    @Test func connectKeepsTheUsersFileByteForByte() throws {
        let (settings, support) = temp()
        let original = """
        {
            "zeta": 1,   "model" : "opus",
            "hooks": {
                "Stop": [
                    {"hooks": [{"type":"command","command":"node other/update.js stop"}]}
                ],
                "Mine": [ {"x": 1} ]
            },
            "alpha": [1, 2,3]
        }

        """
        try Data(original.utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.state() == .connected)
        let text = try String(contentsOf: settings, encoding: .utf8)
        #expect(text.hasPrefix("{\n    \"zeta\": 1,   \"model\" : \"opus\",\n    \"hooks\": {"))
        #expect(text.hasSuffix("},\n    \"alpha\": [1, 2,3]\n}\n"))
        #expect(text.contains("{\"hooks\": [{\"type\":\"command\",\"command\":\"node other/update.js stop\"}]}"))
        #expect(text.contains("\"Mine\": [\n            {\"x\": 1}\n        ]"))
        // A copy of the file as it was is kept first.
        #expect(try String(contentsOf: support.appendingPathComponent("settings-before-connect.json"), encoding: .utf8) == original)
        // Unchanged since: removing puts the original bytes back.
        try file.disconnect()
        #expect(try String(contentsOf: settings, encoding: .utf8) == original)
    }

    @Test func connectWithNoHooksKeyAddsOneAtTheEnd() throws {
        let (settings, support) = temp()
        let original = "{\n  \"model\":   \"opus\"\n}\n"
        try Data(original.utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        let text = try String(contentsOf: settings, encoding: .utf8)
        #expect(text.hasPrefix("{\n  \"model\":   \"opus\",\n  \"hooks\": {"))
        #expect(file.state() == .connected)
    }

    // Remove hooks after something else touched the file: still only our groups go.
    @Test func removeAfterOtherEditsKeepsTheRestByteForByte() throws {
        let (settings, support) = temp()
        let original = "{\n    \"zeta\": 1,   \"hooks\": {\n        \"Stop\": [ {\"hooks\": [{\"type\":\"command\",\"command\":\"node other.js\"}]} ]\n    },\n    \"alpha\": [1, 2,3]\n}\n"
        try Data(original.utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        let edited = try String(contentsOf: settings, encoding: .utf8).replacingOccurrences(of: "[1, 2,3]", with: "[1, 2,3,4]")
        try Data(edited.utf8).write(to: settings)
        try file.disconnect()
        let text = try String(contentsOf: settings, encoding: .utf8)
        #expect(!ClaudeCodeHooks.isInstalled(try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]))
        #expect(text.hasPrefix("{\n    \"zeta\": 1,   \"hooks\": {"))
        #expect(text.contains("\"Stop\": [ {\"hooks\": [{\"type\":\"command\",\"command\":\"node other.js\"}]} ]") || text.contains("node other.js"))
        #expect(text.hasSuffix("\"alpha\": [1, 2,3,4]\n}\n"))
        #expect(file.state() == .notConnected)
    }

    @Test func removeWithOnlyOurGroupsLeavesNoOfOurs() throws {
        let (settings, support) = temp()
        try Data("{\n  \"hooks\": {}\n}\n".utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        let edited = try String(contentsOf: settings, encoding: .utf8).replacingOccurrences(of: "{\n  \"hooks\"", with: "{\n  \"zeta\": 1,\n  \"hooks\"")
        try Data(edited.utf8).write(to: settings)
        try file.disconnect()
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(!ClaudeCodeHooks.isInstalled(parsed))
        #expect(parsed["zeta"] as? Int == 1)
    }
}
