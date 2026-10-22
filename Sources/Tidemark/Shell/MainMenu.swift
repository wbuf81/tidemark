import AppKit
import TidemarkCore

/// Builds the menu bar's menus from `ShellCopy`'s tables. Items whose id is an AppKit selector
/// (Edit's, Window's) go to the responder chain; the rest call `run` with their id.
@MainActor
final class MainMenu: NSObject {
    private let run: (String) -> Void

    init(run: @escaping (String) -> Void) {
        self.run = run
        super.init()
    }

    /// The whole menu bar. Also sets the app's Window and Help menus, so macOS fills those in.
    func build() -> NSMenu {
        let bar = NSMenu()
        for (title, entries) in ShellCopy.mainMenus {
            let menu = NSMenu(title: title)
            fill(menu, entries)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = menu
            bar.addItem(top)
            if title == "Window" { NSApp.windowsMenu = menu }
            if title == "Help" { NSApp.helpMenu = menu }
        }
        return bar
    }

    /// Fills `menu` from `entries`; also used for the menu bar icon's menu.
    func fill(_ menu: NSMenu, _ entries: [ShellCopy.MenuEntry]) {
        for entry in entries {
            switch entry {
            case .separator: menu.addItem(.separator())
            case .item(let spec): menu.addItem(makeItem(spec))
            }
        }
    }

    func makeItem(_ spec: ShellCopy.MenuItemSpec) -> NSMenuItem {
        let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: spec.key)
        item.keyEquivalentModifierMask = Self.mask(spec.modifiers)
        switch spec.id {
        case "about":
            item.target = NSApp
            item.action = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        case "hide":
            item.target = NSApp
            item.action = #selector(NSApplication.hide(_:))
        case "hideOthers":
            item.target = NSApp
            item.action = #selector(NSApplication.hideOtherApplications(_:))
        case "showAll":
            item.target = NSApp
            item.action = #selector(NSApplication.unhideAllApplications(_:))
        case "close":
            item.action = #selector(NSWindow.performClose(_:))
        case let id where id.hasSuffix(":"):
            item.action = Selector(id)
        default:
            item.target = self
            item.action = #selector(choose(_:))
            item.representedObject = spec.id
        }
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { run(id) }
    }

    static func mask(_ modifiers: Set<ShellCopy.KeyModifier>) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}
