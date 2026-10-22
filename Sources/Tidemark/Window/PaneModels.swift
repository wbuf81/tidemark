import AppKit
import Combine
import SwiftUI
import TidemarkCore

// The view models behind Month, Trends and Names & tags, and the few views the three panes share.

// MARK: - Month

@MainActor
final class MonthPaneModel: ObservableObject {
    let store: CalendarStoring
    let settings: Settings
    let now: () -> Date

    /// The first day of the month shown.
    @Published private(set) var shown: Date
    @Published private(set) var month: MonthModel

    private var calendar: Calendar { .current }

    init(store: CalendarStoring, settings: Settings, now: @escaping () -> Date) {
        self.store = store
        self.settings = settings
        self.now = now
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: now())?.start ?? now()
        shown = start
        month = store.month(containing: start, weekStart: settings.weekStart, now: now())
    }

    func reload() {
        month = store.month(containing: shown, weekStart: settings.weekStart, now: now())
    }

    func previous() { move(-1) }
    func next() { move(1) }

    private func move(_ months: Int) {
        shown = calendar.date(byAdding: .month, value: months, to: shown) ?? shown
        reload()
    }
}

// MARK: - Trends

@MainActor
final class TrendsPaneModel: ObservableObject {
    let store: CalendarStoring
    let settings: Settings
    let now: () -> Date

    /// 8 weeks or 13 (a quarter).
    @Published var count = 8 { didSet { reload() } }
    @Published var grouping = TrendGrouping.project { didSet { reload() } }
    @Published private(set) var trends: TrendModel
    /// The row whose chart is open.
    @Published var open: String?

    init(store: CalendarStoring, settings: Settings, now: @escaping () -> Date) {
        self.store = store
        self.settings = settings
        self.now = now
        trends = store.trends(endingWith: now(), count: 8, grouping: .project, weekStart: settings.weekStart, now: now())
    }

    func reload() {
        trends = store.trends(endingWith: now(), count: count, grouping: grouping, weekStart: settings.weekStart, now: now())
        if let open, !trends.rows.contains(where: { $0.name == open }) { self.open = nil }
    }

    var openRow: TrendRow? { open.flatMap { name in trends.rows.first { $0.name == name } } }

    /// The tallest week in any row: every row is drawn on this one scale.
    var scale: TimeInterval { max(trends.rows.flatMap(\.seconds).max() ?? 0, 1) }
}

// MARK: - Names

@MainActor
final class NamesPaneModel: ObservableObject {
    let store: CalendarStoring
    let now: () -> Date
    /// Where every edit is registered for Undo; owned by the window's view model, not by this pane.
    let undo: NameUndo

    @Published var kind = NameKind.sessions { didSet { reload() } }
    @Published private(set) var rows: [NameRow] = []
    @Published private(set) var book: NameBook
    /// Every project the calendar knows, for the project field's menu. Worked out once per load.
    @Published private(set) var knownProjects: [String] = []
    /// Row id → "Couldn’t save: <reason>".
    @Published private(set) var errors: [String: String] = [:]
    /// Why the last "+ Rule" couldn’t be saved, shown under the rule bar.
    @Published private(set) var ruleError: String?
    /// The "+ Rule" field: open, and what has been typed.
    @Published var addingRule = false
    @Published var rulePrefix = ""
    private var sinks: [AnyCancellable] = []

    init(store: CalendarStoring, now: @escaping () -> Date, undo: NameUndo? = nil) {
        self.store = store
        self.now = now
        self.undo = undo ?? NameUndo(store: store)
        book = store.names
        rows = store.nameRows(.sessions, now: now())
        knownProjects = computeKnownProjects()
        sinks = [
            self.undo.restored.sink { [weak self] in self?.errors = [:]; self?.reload() },
            self.undo.failed.sink { [weak self] in self?.errors["names"] = $0 },
        ]
    }

    func reload() {
        book = store.names
        rows = store.nameRows(kind, now: now())
        knownProjects = computeKnownProjects()
    }

    private func computeKnownProjects() -> [String] {
        var names = Set(book.projects.keys)
        for entry in book.sessions.values.compactMap(\.project) { names.insert(entry) }
        for entry in book.folders.values.compactMap(\.project) { names.insert(entry) }
        for entry in book.projects.values.compactMap(\.project) { names.insert(entry) }
        for name in store.nameRows(.projects, now: now()).map(\.key) { names.insert(name) }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// One edit, one undo step. A rule's own row edits the rule.
    func apply(_ change: NameChange, row: NameRow, actionName: String = "Edit Name") {
        do {
            try undo.apply(change, actionName: actionName)
            errors[row.id] = nil
        } catch {
            errors[row.id] = PanesCopy.saveError(error)
        }
        reload()
    }

    /// The key an edit of `row` goes to: its rule when a rule matched, else its own title.
    func key(for row: NameRow) -> String { row.ruleKey ?? row.key }

    func setName(_ text: String, row: NameRow) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        apply(NameChange(kind: row.kind, key: key(for: row), name: .some(trimmed.isEmpty ? nil : trimmed)), row: row, actionName: "Rename")
    }

    func setTags(_ tags: [String], row: NameRow) {
        apply(NameChange(kind: row.kind, key: key(for: row), tags: tags), row: row, actionName: "Change Tags")
    }

    func setProject(_ text: String, row: NameRow) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        apply(NameChange(kind: row.kind, key: key(for: row), project: .some(trimmed.isEmpty ? nil : trimmed)), row: row, actionName: "Move to Project")
    }

    func setHideTitles(_ hide: Bool, row: NameRow) {
        apply(NameChange(kind: row.kind, key: key(for: row), hideTitles: hide), row: row, actionName: "Hide Titles")
    }

    /// Adds a "starts with" rule for `prefix` that names its sessions after the prefix.
    func addRule(prefix: String) {
        guard let key = PanesCopy.ruleKey(for: prefix) else { return }
        do {
            try undo.apply(NameChange(kind: .sessions, key: key, name: .some(String(key.dropLast()))), actionName: "Add Rule")
            ruleError = nil
        } catch {
            ruleError = PanesCopy.saveError(error)
        }
        reload()
    }

    /// Test and render hook: show an error under a row without a failing store.
    func showError(_ message: String, row: NameRow) { errors[row.id] = message }

    /// Test and render hook: show a rule error without a failing store.
    func showRuleError(_ message: String) { ruleError = message }
}

// MARK: - Shared chrome

/// A pane's title and the buttons on its right (mockup: `.mhead`).
struct PaneHeader<Buttons: View>: View {
    let title: String
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Palette.bright)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            HStack(spacing: 6) { buttons }
        }
    }
}

/// One of the mockup's `.btn`s; `primary` is the selected one of a segmented set.
struct PaneButton: View {
    let title: String
    var primary = false
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(primary ? Color(nsColor: NSColor(name: nil) { a in
                    a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x0B / 255, green: 0x16 / 255, blue: 0x24 / 255, alpha: 1) : .white
                }) : Palette.fg)
                .padding(.horizontal, 11)
                .frame(minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Palette.blue : Palette.tile))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Palette.blue : Palette.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(primary ? [.isSelected] : [])
    }
}

/// The note under a pane (mockup: 11.5 px, dim).
struct PaneNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A value a view keeps for itself (the SDK this builds with has no usable `@State`).
@MainActor
final class PaneBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
