import Combine
import Foundation
import TidemarkCore

/// Everything the widget and Insights show: orgs, readings, and what's derived from them.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var orgs: [Org] = []
    @Published private(set) var latest: [String: Reading] = [:]
    @Published private(set) var history: [Reading] = []
    @Published private(set) var claudeCodeOrg: String?
    @Published private(set) var advice: Advice?
    @Published var signedIn = true
    /// The plan list has been read at least once (so an empty one means "no plans", not "loading").
    @Published private(set) var orgListLoaded = false
    /// What went wrong on the last refresh, for Insights; nil when it all worked.
    @Published private(set) var problem: String?
    /// Why an org has no reading, for the widget's caption.
    @Published private(set) var orgProblems: [String: RefreshProblem] = [:]
    /// Why nothing could be read at all, for the widget's placeholder.
    @Published private(set) var refreshProblem: RefreshProblem?
    @Published var now = Date()
    /// The widget's contents are drawn for a 60 pt height and scaled by this to match the
    /// Dock's icon size; the widget itself is `widgetHeight` tall, matching the Dock bar.
    @Published var widgetScale: CGFloat = 1
    @Published var widgetHeight: CGFloat = 60
    /// Stacked as a narrow strip, for the left and right edges.
    @Published var vertical = false

    /// The width the live widget is laid out at, as `DockController` set it.
    var layoutWidth: CGFloat { vertical ? stripLayoutWidth : widgetLayoutWidth }

    /// The widths the widget is laid out at, in points at text size 1, after fitting beside
    /// the Dock; `DockController` sets them.
    @Published var widgetLayoutWidth: CGFloat = 280
    @Published var stripLayoutWidth: CGFloat = 68
    /// When Claude Code last wrote a transcript; it writes every few seconds while it works.
    private var claudeCodeActiveAt: Date?
    /// Live Claude Code sessions, from Tidemark's hooks.
    @Published private var liveSessions: [LiveSession] = []
    /// Tidemark's hooks are in Claude Code's settings.
    @Published var hooksConnected = false
    /// The week from the calendar; nil until the calendar is wired in.
    @Published private(set) var week: WeekSummary?
    /// Claude Code's mood in a demo scenario.
    private var demoCode: CodeMood?
    private var codeCheck: Timer?
    /// Each org's reading before its newest, to tell whether its usage just went up.
    private var previous: [String: Reading] = [:]
    private var settingsChanges: AnyCancellable?
    private var claudeCodeQuietChecks: [Timer] = []

    let settings: Settings
    let formatting = Formatting()
    /// The tide pieces worked out per plan (see `TideKey`).
    let tideCache = TideCache()
    /// Claude Code's plan is nearly out, or will run out well before it resets: the notice to post.
    var onOut: ((Notice) -> Void)?
    /// Claude Code's 5-hour window is nearly full: the notice to post.
    var onSessionNearlyFull: ((Notice) -> Void)?
    /// The switch advice got a new target: the notice to post.
    var onAdvice: ((Notice) -> Void)?
    /// claude.ai ended the session on its own (not a sign-out from the menu).
    var onSignedOut: (() -> Void)?

    private let store: HistoryStore
    private var gate = AdviceGate()
    private var primaryOverride: String?
    private var session = SessionWatch()
    /// The notices already posted, once per plan, kind and window; saved in the settings (`noticeLog`) so a
    /// relaunch doesn't post them again.
    var noticeLog: NoticeLog {
        get { settings.noticeLog }
        set { settings.noticeLog = newValue }
    }
    /// Demo data is on screen: real account details must stay out of it.
    private var showingDemo: Bool { primaryOverride != nil }
    private static let keep: TimeInterval = 35 * 24 * 3600
    /// The pace looks back 3 days and the charts show this week and last, so only the last 15 days are
    /// kept in memory (and filtered on every redraw); the file keeps all 35.
    private static let inMemory: TimeInterval = 15 * 24 * 3600

    init(settings: Settings, store: HistoryStore) {
        self.settings = settings
        self.store = store
        try? store.prune(olderThan: Date().addingTimeInterval(-Self.keep))
        history = Self.recent(store.load(), now: Date())
        // The widget redraws when the in-use effect or its amount changes.
        settingsChanges = settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private static func recent(_ readings: [Reading], now: Date) -> [Reading] {
        readings.filter { now.timeIntervalSince($0.time) < inMemory }
    }

    /// When the newest reading of a shown plan was taken; a hidden plan's reading doesn't count for these.
    var lastUpdated: Date? { orgs.compactMap { latest[$0.id]?.time }.max() }

    /// Signed out, or nothing newer than 10 minutes.
    var isStale: Bool { !signedIn || (lastUpdated.map { now.timeIntervalSince($0) > 600 } ?? true) }

    func role(of org: Org) -> Role { org.id == (primaryOverride ?? settings.primaryOrg) ? .primary : .overflow }
    private func reading(for org: Org) -> Reading? { latest[org.id]?.adjusted(to: now) }
    func forecast(for org: Org) -> WeekForecast? {
        reading(for: org).flatMap { Pace.forecast($0, history: history, now: now) }
    }
    /// What the widget says in place of plans, or nil when it draws them: signed out, loading, no plans,
    /// or why nothing could be read (B20).
    var widgetMessage: GlanceMessage? {
        if limitsOff { return nil }
        if !signedIn { return GlanceCopy.signedOut }
        if orgs.isEmpty {
            if let problem = refreshProblem { return GlanceCopy.problem(problem) }
            return orgListLoaded ? GlanceCopy.noPlans : GlanceCopy.loading
        }
        guard orgs.allSatisfy({ latest[$0.id] == nil }) else { return nil }
        return refreshProblem.map(GlanceCopy.problem) ?? GlanceCopy.loading
    }

    /// The tone of the switch advice's glow and arrow: red while Claude Code's own 5-hour window is full.
    var adviceTone: GlanceTone {
        let full = orgs.first { $0.id == claudeCodeOrg }.flatMap { glance(for: $0)?.session.used }.map { $0 >= 100 } ?? false
        return full ? .red : .amber
    }

    /// The org's 5-hour window and week at a glance; nil when it has never been read.
    func glance(for org: Org) -> Glance? {
        latest[org.id].map { Glance.make($0, history: history, now: now, thresholds: settings.thresholds) }
    }

    /// When the org's newest reading was taken; nil when it has never been read.
    func readTime(for org: Org) -> Date? { latest[org.id]?.time }

    /// The reading is old (over 10 minutes): its shape draws hollow, its numbers dim and it says "as of".
    func isOld(_ org: Org) -> Bool {
        latest[org.id].map { !$0.isFresh(now: now) } ?? false
    }


    /// The first day of the org's current week that Tidemark has a reading for (0 = the week's first day),
    /// or nil when it has read since the week began: the ring draws earlier days as track (S1.6).
    func firstReadDay(for org: Org) -> Int? {
        guard let reset = latest[org.id]?.weekResetsAt else { return nil }
        let start = reset.addingTimeInterval(-Pace.window)
        guard let first = history.filter({ $0.org == org.id && $0.weekResetsAt == reset }).map(\.time).min() else { return nil }
        let day = Int(first.timeIntervalSince(start) / 86_400)
        // A reading within the first hour or so of the week counts as the whole week.
        return first.timeIntervalSince(start) < 3600 || day <= 0 ? nil : min(day, 6)
    }

    /// The note beside a limit's bar, in the current look.
    func glanceNote(_ limit: GlanceLimit) -> String {
        Copy.glanceNote(limit, now: now, formatting: formatting, capitalized: true)
    }

    /// The org as one sentence, for VoiceOver and the tooltip; says when its reading is old.
    func summary(for org: Org) -> String {
        if glance(for: org) == nil, let problem = orgProblems[org.id] {
            return "\(org.name): couldn’t read, \(UsageCopy.short(problem))."
        }
        return Copy.widgetSummary(org.name, glance: glance(for: org), readAt: isOld(org) ? readTime(for: org) : nil,
                           now: now, formatting: formatting)
    }

    /// Claude Code's mood, from the hooks or (without them) from its transcripts; nil when neither
    /// reports one. It doesn't depend on claude.ai: it shows while signed out and with plan limits off.
    private func currentMood() -> CodeMood? {
        if showingDemo { return demoCode }
        guard hooksConnected else { return CodeStatus.fallbackMood(claudeCodeActiveAt: claudeCodeActiveAt, now: now) }
        // With hooks connected, no live session is "Idle", not an absent status.
        return CodeStatus.settle(CodeStatus.mood(liveSessions, isAlive: LiveSessions.isAlive, now: now),
                           sessions: liveSessions, claudeCodeActiveAt: claudeCodeActiveAt, now: now) ?? .idle
    }

    /// Claude Code's mood on this org, or nil: it is the org Claude Code is signed into.
    func codeMood(for org: Org) -> CodeMood? {
        org.id == claudeCodeOrg ? currentMood() : nil
    }

    /// How `org` stands: fine, runs out early, or out; nil when it has never been read.
    func state(for org: Org) -> PlanState? {
        reading(for: org).map { PlanStates.state($0, forecast(for: org), settings.thresholds) }
    }

    /// How `org` stands by its week alone (what a menu bar battery shows); nil when it has never been read.
    func weekState(for org: Org) -> PlanState? {
        reading(for: org).map { PlanStates.weekState($0, forecast(for: org), settings.thresholds) }
    }

    /// Claude Code's mood; nil while neither hooks nor transcripts report one (the widget shows no status).
    var codeMood: CodeMood? { currentMood() }

    /// Plan limits are off: the widget shows the week and Claude Code's status only.
    var limitsOff: Bool { !settings.planLimits && !showingDemo }

    /// "Read just now", "Read 2 min ago", "Read 1 h ago", or "Read at 9:14 AM" past 6 hours.
    func readAge(now: Date) -> String {
        guard let last = lastUpdated else { return "Not read yet" }
        return GlanceCopy.readAge(seconds: now.timeIntervalSince(last), at: last, now: now, formatting: formatting)
    }

    /// The plans to read: those shown, plus the hidden one Claude Code is on, so it still gets its
    /// warnings and its notification (B23). The poller reads these; only `orgs` are drawn.
    var orgsToRead: [Org] {
        showingDemo ? orgs : Notices.toRead(shown: orgs, known: settings.knownOrgs, claudeCodeOrg: claudeCodeOrg)
    }

    /// Whether an org is being used right now; it gets the in-use effect (a rise in usage, or
    /// Claude Code working on it).
    func inUse(for org: Org) -> Bool {
        InUse.isInUse(org: org.id, latest: latest[org.id], previous: previous[org.id], claudeCodeOrg: claudeCodeOrg,
                      claudeCodeActiveAt: claudeCodeActiveAt, stale: isStale, now: now)
    }

    /// The hooks wrote, or the sessions were re-read. Redraws now and when the mood next
    /// changes by itself ("done" ending, a stuck mood resting).
    func sessionsChanged(_ sessions: [LiveSession]) {
        liveSessions = sessions
        guard !showingDemo else { return }
        now = Date()
        codeCheck?.invalidate()
        if let next = CodeStatus.nextChange(sessions, now: now) {
            codeCheck = commonModeTimer(after: next.timeIntervalSince(now) + 0.2)
        }
    }

    /// Every plan the switch rules weigh: the shown ones, and the hidden one Claude Code is on, so it still
    /// gets advice (B23). Only `orgs` are drawn.
    var statuses: [OrgStatus] {
        orgsToRead.compactMap { org in
            guard let r = reading(for: org), let state = state(for: org) else { return nil }
            return OrgStatus(org: org, role: role(of: org), reading: r, state: state)
        }
    }

    var statusLine: String {
        SwitchAdvisor.statusLine(statuses, claudeCodeOrg: claudeCodeOrg, advice: advice, now: now,
                                 formatting: formatting, settings.thresholds,
                                 hidden: showingDemo ? [] : settings.knownOrgs.filter { org in !orgs.contains { $0.id == org.id } })
    }

    /// The org list from claude.ai: show the selected orgs, primary first. The first time,
    /// the org Claude Code is signed into becomes the primary org.
    func setAvailableOrgs(_ all: [Org], claudeCodeOrg: String?) {
        settings.knownOrgs = all
        orgListLoaded = true
        let shown = OrgFilter.shown(all, choices: settings.orgChoices)
        if !shown.contains(where: { $0.id == settings.primaryOrg }) {
            settings.primaryOrg = shown.first(where: { $0.id == claudeCodeOrg })?.id ?? shown.first?.id
        }
        guard !showingDemo else { return }
        orgs = DisplayNames.short(shown).sorted { role(of: $0) == .primary && role(of: $1) != .primary }
    }

    /// A refresh round: keeps every reading it got, and says which orgs it couldn't read.
    func ingest(_ outcome: UsageRound.Outcome, claudeCodeOrg: String?, at time: Date) {
        now = time
        self.claudeCodeOrg = claudeCodeOrg
        for r in outcome.readings {
            if let old = latest[r.org] { previous[r.org] = old }
            latest[r.org] = r
        }
        history = Self.recent(history + outcome.readings, now: time)
        try? store.append(outcome.readings)
        signedIn = true
        session.worked()
        problem = UsageCopy.problem(outcome.failures, shown: orgs.count)
        orgProblems = Dictionary(outcome.failures.map { ($0.org.id, $0.problem) }, uniquingKeysWith: { a, _ in a })
        // Only the plans shown count: a hidden plan's reading doesn't hide that the shown ones failed.
        let shownIDs = Set(orgs.map(\.id))
        let shownRead = outcome.readings.contains { shownIDs.contains($0.org) }
        refreshProblem = shownRead ? nil : (outcome.failures.first { shownIDs.contains($0.org.id) } ?? outcome.failures.first)?.problem
        updateAdvice()
        raiseNotices()
    }

    /// Builds the notices that are due for the plan Claude Code is on, shown or not (B23); B4 posts them
    /// (gated by its settings). Each is due once per window (`noticeLog`).
    private func raiseNotices() {
        guard !showingDemo else { return }
        let due = Notices.due(claudeCodeOrg: claudeCodeOrg, orgs: orgs + settings.knownOrgs.filter { k in !orgs.contains { $0.id == k.id } },
                              latest: latest, history: history, now: now, formatting: formatting,
                              thresholds: settings.thresholds, log: &noticeLog)
        if let notice = due.week { onOut?(notice) }
        if let notice = due.sessionFull { onSessionNearlyFull?(notice) }
    }

    /// Nothing could be read this time (not even the org list).
    func refreshFailed(_ problem: RefreshProblem) {
        self.problem = UsageCopy.problem(problem)
        refreshProblem = problem
    }

    /// claude.ai says the session is over. Worth a notification only if it worked earlier in
    /// this run, not when launching signed out.
    func sessionEnded() {
        signedIn = false
        clearProblems()
        if session.ended() { onSignedOut?() }
    }

    /// The owner signed out from the menu.
    func signedOut() {
        signedIn = false
        clearProblems()
        session = SessionWatch()
    }

    private func clearProblems() {
        problem = nil
        orgProblems = [:]
        refreshProblem = nil
    }

    func setClaudeCodeOrg(_ id: String?) {
        guard id != claudeCodeOrg, !showingDemo else { return }
        claudeCodeOrg = id
        updateAdvice()
    }

    /// Claude Code wrote a transcript. Publishes only when that starts its org's in-use
    /// effect (writes come every second or so while it works); a check just after the quiet
    /// period ends the effect on time.
    func claudeCodeWorked(at time: Date) {
        guard !showingDemo else { return }
        let wasWorking = claudeCodeActiveAt.map { time.timeIntervalSince($0) < InUse.claudeCodeQuiet } ?? false
        claudeCodeActiveAt = time
        if !wasWorking { now = time }
        claudeCodeQuietChecks.forEach { $0.invalidate() }
        // One just after the quiet period (the mood goes from tool to done), one after the
        // fallback "done" has ended too (the mood ends).
        claudeCodeQuietChecks = [InUse.claudeCodeQuiet + 0.5, InUse.claudeCodeQuiet + CodeStatus.doneLasts + 0.5].map(commonModeTimer(after:))
    }

    /// A one-shot timer that ticks the model, in common run-loop modes so it still fires
    /// while a menu is open.
    private func commonModeTimer(after delay: TimeInterval) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func tick() { now = Date() }

    /// The plan Claude Code is on is out (a read of the newest reading, shown or not).
    private var currentOrgIsOut: Bool {
        guard let id = claudeCodeOrg, let r = latest[id]?.adjusted(to: now) else { return false }
        return PlanStates.state(r, Pace.forecast(r, history: history, now: now), settings.thresholds) == .out
    }

    private func updateAdvice() {
        let candidate = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                             formatting: formatting, settings.thresholds)
        let previous = advice
        advice = gate.update(candidate, claudeCodeOrg: claudeCodeOrg, currentIsRed: currentOrgIsOut, now: now)
        if !showingDemo, let advice, advice.target != previous?.target,
           let notice = Notices.adviceDue(advice, claudeCodeOrg: claudeCodeOrg, weekResetsAt: claudeCodeOrg.flatMap { latest[$0]?.weekResetsAt },
                                          log: &noticeLog) {
            onAdvice?(notice)
        }
    }

    // MARK: Week calendar

    /// Sets the week directly, for the showcase's pictures (nil leaves it out of them).
    func showWeek(_ summary: WeekSummary?) {
        week = summary
    }

    // MARK: Demo mode

    func apply(_ scenario: DemoScenario) {
        primaryOverride = scenario.primary
        demoCode = scenario.codeMood
        clearProblems()
        orgs = scenario.orgs
        latest = Dictionary(uniqueKeysWithValues: scenario.readings.map { ($0.org, $0) })
        previous = [:]
        claudeCodeActiveAt = scenario.claudeCodeWorking ? scenario.now : nil
        history = DemoData.history(for: scenario) + scenario.readings
        claudeCodeOrg = scenario.claudeCodeOrg
        now = scenario.now
        signedIn = true
        week = DemoData.week(now: scenario.now)
        advice = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                      formatting: formatting, settings.thresholds)
    }

    func leaveDemo() {
        primaryOverride = nil
        demoCode = nil
        clearProblems()
        orgs = []
        orgListLoaded = false
        latest = [:]
        previous = [:]
        claudeCodeActiveAt = nil
        advice = nil
        history = Self.recent(store.load(), now: Date())
        now = Date()
        week = nil
    }
}
