import AppKit
import Combine
import CoreGraphics
import TidemarkCore

/// The menu bar: a battery per shown plan (the week left, name and %) while plan limits are on, or Tidemark's
/// icon and its menu (limits off, nothing read yet, or when chosen); nothing when `menuBarMode` is off. A left
/// click on a battery opens that plan's details card below it; a right click opens the icon's menu: one line per
/// plan (a state mark, then `UsageCopy.menuLine`), Claude Code's status, then Open, Refresh, Hide the widget,
/// Settings and Quit. The menu is built each time it opens, so it never shows old numbers.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Callbacks {
        var open: () -> Void = {}
        var refresh: () -> Void = {}
        var toggleWidget: () -> Void = {}
        var settings: () -> Void = {}
        var quit: () -> Void = {}
        /// A plan's battery was clicked: its id and the button's frame in screen points.
        var openDetails: (String, CGRect, DetailsAnchor) -> Void = { _, _, _ in }
    }

    private let model: AppModel
    private let callbacks: Callbacks
    private let widgetHidden: () -> Bool
    private var item: NSStatusItem?
    /// The batteries, in plan order (left to right), by plan id.
    private var batteries: [(id: String, item: NSStatusItem)] = []
    /// What the batteries show now, so an unchanged model doesn't redraw them.
    private var shownItems: [MenuBarBatteries.Item] = []
    /// The plan whose details card is open: its battery draws highlighted.
    private var highlighted: String?
    private var sinks: [AnyCancellable] = []
    /// Bubbles and the needs-you dot on the batteries.
    private let effects = BatteryEffects()
    private lazy var builder = MainMenu(run: { [weak self] id in self?.run(id) })

    init(model: AppModel, widgetHidden: @escaping () -> Bool, callbacks: Callbacks) {
        self.model = model
        self.widgetHidden = widgetHidden
        self.callbacks = callbacks
        super.init()
    }

    /// Shows or removes the items to match Settings and the readings, now and whenever either changes.
    func start() {
        apply()
        let settings = model.settings
        let changed = Publishers.MergeMany(
            settings.$menuBarMode.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$planNameStyle.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$planLimits.dropFirst().map { _ in }.eraseToAnyPublisher())
        sinks.append(changed.sink { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply() } }
        })
        // The batteries and the button's spoken label follow the readings, not only when something is chosen.
        sinks.append(model.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
    }

    /// The batteries to show now: none unless the mode is batteries and plan limits are on.
    private var wanted: [MenuBarBatteries.Item] {
        guard model.settings.menuBarMode == .batteries else { return [] }
        let plans = model.orgs.map { org in
            MenuBarBatteries.Plan(id: org.id, name: org.name, weekUsed: model.glance(for: org)?.week.used,
                                  state: model.weekState(for: org), isOld: model.isOld(org), codeMood: model.codeMood(for: org))
        }
        return MenuBarBatteries.make(plans, limitsOn: !model.limitsOff, names: model.settings.planNameStyle)
    }

    private func apply() {
        let mode = model.settings.menuBarMode
        let items = wanted
        setBatteries(items)
        // The icon: when chosen, or in place of batteries that have nothing to show (limits off, nothing read yet).
        if mode == .icon || (mode == .batteries && items.isEmpty) {
            if item == nil {
                let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                created.button?.image = MenuBarIcon.image()
                let menu = NSMenu()
                menu.delegate = self
                created.menu = menu
                item = created
            }
            item?.button?.setAccessibilityLabel(label)
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    /// The battery of the plan whose card is open looks pressed, as a system menu bar item does; nil clears it.
    func highlight(plan id: String?) {
        highlighted = id
        for entry in batteries { entry.item.button?.highlight(entry.id == id) }
    }

    private func setBatteries(_ items: [MenuBarBatteries.Item]) {
        if items == shownItems, batteries.map(\.id) == items.map(\.id) { return }
        shownItems = items
        if batteries.map(\.id) != items.map(\.id) {
            effects.removeAll()
            for old in batteries { NSStatusBar.system.removeStatusItem(old.item) }
            // A new item lands left of the others, so the last plan goes in first.
            batteries = items.reversed().map { entry in
                let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                created.button?.identifier = NSUserInterfaceItemIdentifier(entry.id)
                created.button?.target = self
                created.button?.action = #selector(batteryClicked(_:))
                created.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                return (entry.id, created)
            }.reversed()
        }
        for (entry, slot) in zip(items, batteries.map(\.item)) {
            slot.button?.attributedTitle = MenuBarIcon.batteryTitle(entry)
            slot.button?.setAccessibilityLabel(entry.accessibility)
            if let button = slot.button { effects.update(id: entry.id, button: button, item: entry) }
        }
        highlight(plan: highlighted)
    }

    @objc private func batteryClicked(_ sender: NSStatusBarButton) {
        guard let entry = batteries.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Today's menu, from this battery.
            let menu = NSMenu()
            menu.delegate = self
            entry.item.menu = menu
            sender.performClick(nil)
            entry.item.menu = nil
        } else if let window = sender.window {
            callbacks.openDetails(entry.id, window.convertToScreen(sender.convert(sender.bounds, to: nil)), .menuBar)
        }
    }

    /// "Tidemark, <first plan sentence>".
    private var label: String {
        ShellCopy.menuBarLabel(firstPlanSentence: model.orgs.first.map { model.summary(for: $0) })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        item?.button?.setAccessibilityLabel(label)
        for line in Self.infoLines(model) { menu.addItem(Self.infoItem(line)) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        builder.fill(menu, ShellCopy.statusMenu(widgetHidden: widgetHidden()))
    }

    private func run(_ id: String) {
        switch id {
        case "open": callbacks.open()
        case "refresh": callbacks.refresh()
        case "toggleWidget": callbacks.toggleWidget()
        case "settings": callbacks.settings()
        case "quit": callbacks.quit()
        default: break
        }
    }

    // MARK: Lines

    struct InfoLine {
        var text: String
        var image: NSImage?
    }

    /// The disabled lines above the actions. With plan limits off there are no plans to list, so the
    /// week stands in.
    static func infoLines(_ model: AppModel) -> [InfoLine] {
        var lines: [InfoLine] = []
        if model.limitsOff {
            if let week = model.week {
                lines.append(InfoLine(text: "This week  \(WeekSummary.shortHours(week.week.seconds))", image: nil))
            }
        } else {
            for org in model.orgs {
                let hollow = model.isOld(org)   // as in the widget, the notch and the sidebar
                let state = model.state(for: org)
                let image = MenuBarIcon.stateImage(state, hollow: hollow)
                // The mark carries the state; VoiceOver gets it in words.
                image.accessibilityDescription = Self.stateWords(state, hollow: hollow)
                lines.append(InfoLine(text: UsageCopy.menuLine(org, glance: model.glance(for: org), now: model.now, formatting: model.formatting), image: image))
            }
        }
        if let mood = model.codeMood, let text = ShellCopy.menuBarStatusLine(mood) {
            lines.append(InfoLine(text: text, image: MenuBarIcon.moodImage(mood)))
        }
        return lines
    }

    /// A plan's state in words, for the mark beside its line.
    static func stateWords(_ state: PlanState?, hollow: Bool) -> String {
        let word: String
        switch state {
        case .fine?: word = "fine"
        case .runsOutEarly?: word = "runs out early"
        case .out?: word = "out"
        case nil: return "no reading"
        }
        return hollow ? "\(word), old reading" : word
    }

    /// A line that reads normally (not greyed) and can't be chosen; the part before the double
    /// space (the plan's name) is bold, as in the mockups.
    static func infoItem(_ line: InfoLine) -> NSMenuItem {
        let item = NSMenuItem()
        let text = NSMutableAttributedString(string: line.text, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor,
        ])
        if let split = line.text.range(of: "  ") {
            text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                              range: NSRange(line.text.startIndex..<split.lowerBound, in: line.text))
        }
        item.attributedTitle = text
        item.image = line.image
        item.isEnabled = false
        return item
    }
}
