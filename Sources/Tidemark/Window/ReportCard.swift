import AppKit
import SwiftUI
import TidemarkCore

/// What the report card is doing and which text it shows.
@MainActor
final class ReportModel: ObservableObject {
    enum Tab { case plain, claude }
    enum Phase: Equatable { case idle, writing, failed(String) }

    let week: WeekModel
    let settings: Settings
    let store: CalendarStoring
    let actions: AppActions
    let now: () -> Date
    var onSaved: () -> Void = {}

    @Published var tab: Tab
    @Published var phase: Phase
    @Published private(set) var report: WeekReport?
    @Published var showConsent = false
    @Published var editing = false
    @Published var draft: [String] = []
    /// Why saving an edit failed; the edit stays open.
    @Published private(set) var saveError: String?
    private var token = UUID()
    private var task: Task<Void, Never>?

    init(week: WeekModel, settings: Settings, store: CalendarStoring, actions: AppActions, now: @escaping () -> Date,
         tab: Tab? = nil, phase: Phase = .idle) {
        self.week = week
        self.settings = settings
        self.store = store
        self.actions = actions
        self.now = now
        report = week.report
        self.tab = tab ?? (week.report != nil && (week.report?.author == .claudeCode || settings.reportMode == .claudeCode) ? .claude : .plain)
        self.phase = phase
    }

    var lines: [String] { tab == .plain ? week.plainReport : report?.lines ?? [] }

    /// The first time asks; after that it runs.
    func requestWrite() {
        if settings.claudeCodeReportConsented { run() } else { showConsent = true }
    }

    func consentAndWrite() {
        settings.claudeCodeReportConsented = true
        showConsent = false
        run()
    }

    func run() {
        phase = .writing
        let mine = UUID()
        token = mine
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.actions.writeReport(self.week)
            guard self.token == mine else { return }
            switch result {
            case .success(let written): self.keep(written)
            case .failure(let failure): self.phase = .failed(WindowCopy.reportFailure(failure))
            }
        }
    }

    func cancel() {
        token = UUID()
        task?.cancel()
        phase = .idle
    }

    private func keep(_ written: WeekReport) {
        do {
            try store.save(written)
            report = written
            tab = .claude
            phase = .idle
            onSaved()
        } catch {
            phase = .failed("Couldn’t save: \(error.localizedDescription)")
        }
    }

    func startEditing() {
        draft = report?.lines ?? []
        editing = true
    }

    func saveEdit() {
        guard let current = report else { return }
        // The author stays: an imported report is still the old calendar's.
        let edited = WeekReport(weekStart: current.weekStart, lines: draft, days: current.days, author: current.author, written: now())
        do {
            try store.save(edited)
            report = edited
            editing = false
            saveError = nil
            onSaved()
        } catch {
            // Stay in edit mode, so the typed text isn't lost.
            saveError = PanesCopy.saveError(error)
        }
    }

    func copyLines() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

/// A week's three report lines: plain from the numbers, or written by Claude Code and kept.
struct ReportCard: View {
    @StateObject private var model: ReportModel
    var onClose: (() -> Void)?
    private let calendar = Calendar.current

    init(model: @autoclosure @escaping () -> ReportModel, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: model())
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Report · \(WindowCopy.range(model.week, calendar: calendar))")
                    .font(Theme.font(16, .bold)).foregroundStyle(Palette.bright)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                tabs
                Button("Copy") { model.copyLines() }
                    .buttonStyle(TidemarkWeekButtonStyle())
                    .disabled(model.lines.isEmpty)
            }
            lines
            footer
            if let onClose {
                // Esc closes the sheet, except while editing, where Cancel takes it.
                HStack {
                    Spacer()
                    if model.editing {
                        Button("Done", action: onClose).buttonStyle(TidemarkWeekButtonStyle())
                    } else {
                        Button("Done", action: onClose).buttonStyle(TidemarkWeekButtonStyle()).keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
        .padding(14)
        .background(Palette.tile)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $model.showConsent) {
            ReportConsentSheet(onCancel: { model.showConsent = false }, onWrite: { model.consentAndWrite() })
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab("Plain", .plain)
            Rectangle().fill(Palette.line).frame(width: 1)
            tab("By Claude Code", .claude)
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func tab(_ title: String, _ value: ReportModel.Tab) -> some View {
        let on = model.tab == value
        return Button { model.tab = value; model.editing = false } label: {
            Text(title)
                .font(Theme.font(12, on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.blueInk : Palette.fg)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(on ? Palette.selection : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    @ViewBuilder private var lines: some View {
        if model.editing {
            VStack(spacing: 6) {
                ForEach(model.draft.indices, id: \.self) { i in
                    TextField("Line \(i + 1)", text: $model.draft[i], axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.font(13.5))
                        .accessibilityLabel("Report line \(i + 1)")
                }
            }
        } else if model.lines.isEmpty {
            if model.tab == .plain {
                Text(WindowCopy.emptyWeek).font(Theme.font(13.5)).foregroundStyle(Palette.dim)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(i + 1).").foregroundStyle(Palette.dim).frame(width: 18, alignment: .trailing)
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Theme.font(13.5)).foregroundStyle(Palette.bright).lineSpacing(2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .writing:
            HStack(spacing: 8) {
                Spinner()
                Text("Writing with Claude Code…").font(Theme.font(12)).foregroundStyle(Palette.dim)
                Spacer()
                Button("Cancel") { model.cancel() }.buttonStyle(TidemarkWeekButtonStyle())
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(Theme.font(12.5)).foregroundStyle(Palette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); writeButton("Write it with Claude Code…") }
            }
        case .idle:
            idleFooter
        }
    }

    @ViewBuilder private var idleFooter: some View {
        if model.editing {
            if let message = model.saveError {
                Text(message).font(Theme.font(12.5)).foregroundStyle(Palette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.editing = false }.buttonStyle(TidemarkWeekButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { model.saveEdit() }.buttonStyle(TidemarkWeekButtonStyle(primary: true))
            }
        } else if model.tab == .claude, let report = model.report {
            HStack(spacing: 6) {
                Text("\(WindowCopy.writtenBy(report, calendar: calendar)) ·")
                    .font(Theme.font(11.5)).foregroundStyle(Palette.dim)
                Button("Edit") { model.startEditing() }.buttonStyle(TidemarkWeekButtonStyle())
                Button("Write again") { model.requestWrite() }.buttonStyle(TidemarkWeekButtonStyle())
                Spacer(minLength: 0)
            }
        } else if model.tab == .plain {
            Text(WindowCopy.plainReportNote).font(Theme.font(11.5)).foregroundStyle(Palette.dim)
            HStack { Spacer(); writeButton("Write it with Claude Code…") }
        } else {
            HStack { Spacer(); writeButton("Write it with Claude Code…") }
        }
    }

    private func writeButton(_ title: String) -> some View {
        Button(title) { model.requestWrite() }.buttonStyle(TidemarkWeekButtonStyle())
    }
}

/// A small spinning arc, drawn so the render shows it (a system progress view doesn't draw offscreen).
private struct Spinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // Reduce Motion: a still arc, the words beside it say the rest.
            Circle().trim(from: 0, to: 0.75)
                .stroke(Palette.dim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        } else {
            spinning
        }
    }

    private var spinning: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            Circle().trim(from: 0, to: 0.75)
                .stroke(Palette.dim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(turn))
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}
