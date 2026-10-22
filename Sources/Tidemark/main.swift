import AppKit
import Foundation

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--render"), flag + 1 < arguments.count {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Renderer.render(to: URL(fileURLWithPath: arguments[flag + 1]))
        exit(0)
    }
    // A second copy hands over to the first and quits. After --render, so a render never touches a running copy.
    if SingleInstance.handOver() { exit(0) }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
