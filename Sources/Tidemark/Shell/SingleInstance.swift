import AppKit
import TidemarkCore

/// Only one Tidemark runs: a second copy hands over to the first and quits. Checked by `main.swift`
/// after `--render` has been handled, so a render never touches a running copy. A copy run from the
/// build folder has no bundle identifier and is never treated as a second copy.
enum SingleInstance {
    /// The other running copy of this app, if there is one.
    static func other() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Brings the first copy forward (a reopen, which shows its window) and says whether there was one.
    @discardableResult
    static func handOver() -> Bool {
        guard let first = other() else { return false }
        if let url = first.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            first.activate()
        }
        return true
    }
}
