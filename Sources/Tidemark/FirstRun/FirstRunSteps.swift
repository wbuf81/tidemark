import AppKit
import SwiftUI
import TidemarkCore

/// Where first run is: the step, 1 to 4.
@MainActor
final class FirstRunState: ObservableObject {
    @Published var step = 1
    /// Step 2 on its own (from Week or Settings): no step label, Continue chooses and closes, no Back.
    @Published var sourcesOnly = false
}

/// What first run asks the app to do.
struct FirstRunActions {
    /// "Turn on and sign in…": turns plan limits on and opens the sign-in window.
    var turnOnAndSignIn: () -> Void = {}
    /// The last step's Done, or closing the window (which counts as Not now for any step left).
    var finish: () -> Void = {}
    /// Leaving "What Tidemark reads" with the switches as chosen: the calendar may read from now on.
    var sourcesChosen: () -> Void = {}
}

/// The four steps of first run, in one 520 × 560 window. Copy is the mockups' `#firstrun`.
struct FirstRunView: View {
    @ObservedObject var state: FirstRunState
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel
    var actions: FirstRunActions

    static let size = NSSize(width: 520, height: 560)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !state.sourcesOnly {
                Text(ShellCopy.firstRunStepLabel(state.step)).font(.system(size: 12)).foregroundStyle(Palette.faint)
            }
            switch state.step {
            case 1: welcome
            case 2: reads
            case 3: limits
            default: done
            }
            Spacer(minLength: 0)
            buttons
            // Escape and ⌘W close first run as Not now for what's left.
            Button("", action: actions.finish).keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true).focusable(false)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Palette.tile)
        .onChange(of: state.step) { _, step in announce(step) }
    }

    /// Says the new step's title aloud for VoiceOver, since the old one is gone.
    private func announce(_ step: Int) {
        let titles = [ShellCopy.firstRunWelcomeTitle, ShellCopy.firstRunReadsTitle, ShellCopy.firstRunLimitsTitle, ShellCopy.firstRunDoneTitle]
        guard titles.indices.contains(step - 1) else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(ShellCopy.firstRunStepLabel(step)). \(titles[step - 1])"])
    }

    // MARK: Steps

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.bright).accessibilityAddTraits(.isHeader)
    }

    private func body(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Palette.fg).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppIconTile(size: 64)
            title(ShellCopy.firstRunWelcomeTitle)
            body(ShellCopy.firstRunWelcomeBody)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ShellCopy.firstRunBullets, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.dim)
                        Text(line).font(.system(size: 14)).foregroundStyle(Palette.fg)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var reads: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(ShellCopy.firstRunReadsTitle)
            body(ShellCopy.firstRunReadsBody)
            VStack(alignment: .leading, spacing: 12) {
                source(0, isOn: $settings.sources.claudeCode)
                source(1, isOn: $settings.sources.firstMessages)
                source(2, isOn: $settings.sources.git)
                source(3, isOn: .constant(false), enabled: false)
            }
            .padding(.top, 2)
            Text(ShellCopy.firstRunReadsNote).font(.system(size: 12)).foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func source(_ index: Int, isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        let entry = ShellCopy.firstRunSources[index]
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 14)).foregroundStyle(enabled ? Palette.fg : Palette.dim)
                Text(entry.detail).font(.system(size: 12)).foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(ShellCopy.firstRunLimitsTitle)
            body(ShellCopy.firstRunLimitsBody)
            ClaudeAIWarning()
            Text(ShellCopy.planLimitsPassword).font(.system(size: 12)).foregroundStyle(Palette.dim)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(ShellCopy.firstRunDoneTitle)
            FirstRunPreview(model: model)
            body(ShellCopy.firstRunDoneBody)
            Text(ShellCopy.firstRunDoneNote).font(.system(size: 12)).foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Buttons

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            switch state.step {
            case 1:
                Button("Get started") { state.step = 2 }.keyboardShortcut(.defaultAction)
            case 2 where state.sourcesOnly:
                Button("Continue") { actions.sourcesChosen(); actions.finish() }.keyboardShortcut(.defaultAction)
            case 2:
                Button("Back") { state.step = 1 }
                Button("Continue") { actions.sourcesChosen(); state.step = 3 }.keyboardShortcut(.defaultAction)
            case 3:
                // Neither is the default: the choice is the user's, not Return's.
                Button("Not now") { state.step = 4 }
                Button("Turn on and sign in…") { actions.turnOnAndSignIn(); state.step = 4 }
            default:
                Button("Done", action: actions.finish).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The app's icon at `size`: the real one in the bundled app, a drawn stand-in in a build-folder run.
struct AppIconTile: View {
    var size: CGFloat

    var body: some View {
        if Bundle.main.bundleIdentifier != nil {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Palette.blue, Palette.blueInk], startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .overlay(Image(nsImage: MenuBarIcon.image(size: size * 0.62)).renderingMode(.template)
                    .foregroundStyle(.white))
                .accessibilityHidden(true)
        }
    }
}

/// Step 4's preview: Claude Code's status and the week band, as the widget will show them.
struct FirstRunPreview: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let mood = model.codeMood ?? .idle
        let week = model.week
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                StatusGlyph(mood, size: 18)
                Text(mood.word).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.bright)
                Text("Claude Code").font(.system(size: 12)).foregroundStyle(Palette.dim)
            }
            HStack(spacing: 10) {
                Text("Week").font(.system(size: 12)).foregroundStyle(Palette.dim)
                Text(week.map { hours($0.week.seconds) } ?? "0m").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.bright)
                days(week)
                Text(week?.week.projects.first?.name ?? "No sessions yet").font(.system(size: 12)).foregroundStyle(Palette.fg)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.page))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: Claude Code \(mood.word.lowercased()), \(week.map { hours($0.week.seconds) } ?? "0m") this week")
    }

    private func hours(_ seconds: Double) -> String { WeekSummary.shortHours(seconds) }

    private func days(_ week: WeekSummary?) -> some View {
        let values = (0..<7).map { i in week.flatMap { $0.week.days.indices.contains(i) ? $0.week.days[i].seconds : nil } ?? 0 }
        let top = max(values.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5).fill(Palette.track)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Palette.blue).frame(height: max(14 * values[i] / top, values[i] > 0 ? 2 : 0))
                    }
                    .frame(width: 7, height: 14)
            }
        }
        .accessibilityHidden(true)
    }
}
