import Combine
import Foundation
import SwiftUI
import TidemarkCore

/// What the calendar panes share: the week being shown, the month around it, and the name edits
/// that can be undone. Reads from the store; never writes except through `apply`, `undo` and the
/// report card's `store.save`.
@MainActor
final class CalendarViewModel: ObservableObject {
    let store: CalendarStoring
    let settings: Settings
    let now: () -> Date

    @Published var shownDay: Date { didSet { reload() } }
    @Published private(set) var week: WeekModel
    @Published private(set) var month: MonthModel
    @Published var grouping = TrendGrouping.project
    /// The store's problems and the week's own, once each.
    @Published private(set) var problems: [CalendarProblem] = []
    /// The last name edit that failed, in words, until the next one works.
    @Published private(set) var lastError: String?
    @Published private(set) var canUndo = false

    /// Name edits and their undo. Owned here, so it lives as long as the window: an undo step
    /// registered from Names & tags still works after the pane is gone.
    let nameUndo: NameUndo
    private var sinks: [AnyCancellable] = []

    /// The panes' models live as long as the window too, so every one of them can be reloaded.
    private(set) lazy var monthPane = MonthPaneModel(store: store, settings: settings, now: now)
    private(set) lazy var trendsPane = TrendsPaneModel(store: store, settings: settings, now: now)
    private(set) lazy var namesPane = NamesPaneModel(store: store, now: now, undo: nameUndo)

    /// The window's undo manager (Edit → Undo goes there); set once the window exists.
    var undoManager: UndoManager? {
        get { nameUndo.windowManager }
        set { nameUndo.windowManager = newValue; canUndo = nameUndo.canUndo }
    }

    init(store: CalendarStoring, settings: Settings, now: @escaping () -> Date) {
        self.store = store
        self.settings = settings
        self.now = now
        nameUndo = NameUndo(store: store)
        let day = now()
        shownDay = day
        week = store.week(containing: day, weekStart: settings.weekStart, now: day)
        month = store.month(containing: day, weekStart: settings.weekStart, now: day)
        problems = Self.merged(store.problems, week.problems)
        sinks = [
            // An undo or redo from the Edit menu changes the store behind everyone's back.
            nameUndo.restored.sink { [weak self] in self?.reloadAll() },
            nameUndo.failed.sink { [weak self] in self?.lastError = $0 },
            // The week start is read when a model loads; the willSet value arrives before the change.
            settings.$weekStart.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.reloadAll() },
        ]
    }

    private var calendar: Calendar { .current }

    func previousWeek() { shownDay = calendar.date(byAdding: .day, value: -7, to: week.start) ?? shownDay }
    /// Stops at this week.
    func nextWeek() { guard !isThisWeek else { return }; shownDay = calendar.date(byAdding: .day, value: 7, to: week.start) ?? shownDay }
    func today() { shownDay = now() }

    func reload() {
        let at = now()
        week = store.week(containing: shownDay, weekStart: settings.weekStart, now: at)
        month = store.month(containing: shownDay, weekStart: settings.weekStart, now: at)
        problems = Self.merged(store.problems, week.problems)
        canUndo = nameUndo.canUndo
    }

    /// Reloads the week and every pane's data from the store.
    func reloadAll() {
        reload()
        monthPane.reload()
        trendsPane.reload()
        namesPane.reload()
    }

    /// Whether the shown week is the one `now` is in.
    var isThisWeek: Bool {
        let end = calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
        return week.start <= now() && now() < end
    }

    /// The week before the shown one's first day, for the "‹ 12 Oct" button.
    var previousWeekStart: Date { calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start }
    var nextWeekStart: Date { calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start }

    /// The week the Report button writes about: the shown week, except that this week is not over,
    /// so there it is last week (the mockup's "Report · 12 – 18 Oct" on 19 – 25 Oct).
    func reportWeek() -> WeekModel {
        guard isThisWeek else { return week }
        return store.week(containing: previousWeekStart, weekStart: settings.weekStart, now: now())
    }

    /// One name edit, one undo step (registered on the window's undo manager).
    func apply(_ change: NameChange) {
        do {
            try nameUndo.apply(change)
            lastError = nil
        } catch {
            lastError = PanesCopy.saveError(error)
        }
        reloadAll()
    }

    func undo() {
        nameUndo.undo()
        reloadAll()
    }

    private static func merged(_ a: [CalendarProblem], _ b: [CalendarProblem]) -> [CalendarProblem] {
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.id).inserted }
    }
}


/// Name edits and the way back. Registers on the window's undo manager (its own until the window
/// gives one), with itself as the target: it is owned by the window's view model, so the target
/// is never gone when Edit → Undo arrives.
@MainActor
final class NameUndo {
    let store: CalendarStoring
    /// Sent after an undo or redo changed the store.
    let restored = PassthroughSubject<Void, Never>()
    /// Sent with the words when an undo or redo couldn’t be saved.
    let failed = PassthroughSubject<String, Never>()
    var windowManager: UndoManager?
    private let ownManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false   // no run loop event closes a group for it
        return manager
    }()
    private var manager: UndoManager { windowManager ?? ownManager }

    init(store: CalendarStoring) { self.store = store }

    var canUndo: Bool { manager.canUndo }
    var canRedo: Bool { manager.canRedo }

    /// Applies `change` and registers one undo step for it; throws when it can't be saved.
    @discardableResult
    func apply(_ change: NameChange, actionName: String = "Edit Name") throws -> NameBook {
        let before = store.names
        let after = try store.apply(change)
        register(restoring: before, from: after, actionName: actionName)
        return after
    }

    func undo() { manager.undo() }
    func redo() { manager.redo() }

    /// Puts `book` back with `replaceNames`; the way back is registered, so Redo works too.
    private func restore(_ book: NameBook, replacing current: NameBook, actionName: String) {
        do {
            try store.replaceNames(book)
            register(restoring: current, from: book, actionName: actionName)
        } catch {
            failed.send(PanesCopy.saveError(error))
        }
        restored.send()
    }

    private func register(restoring before: NameBook, from after: NameBook, actionName: String) {
        guard before != after else { return }
        let manager = manager
        let grouped = windowManager == nil && !manager.isUndoing && !manager.isRedoing
        if grouped { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { target in
            target.restore(before, replacing: after, actionName: actionName)
        }
        manager.setActionName(actionName)
        if grouped { manager.endUndoGrouping() }
    }
}
