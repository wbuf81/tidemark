import AppKit
import SwiftUI
import TidemarkCore

/// What a plan's tide slot needs besides its glance: the week as a chart, and the verdict in words.
/// The chart is nil until the plan's week has started (no reset known); the verdict then says so.
struct TideInfo {
    var chart: LeftChart?
    var verdict: PlanVerdict
}

/// What a cached tide piece was worked out from: the plan's newest reading, how much history there is, the
/// minute, and the thresholds. Every slot's body asks for these on each model change, and each is a pass
/// over 15 days of readings, so they are kept until one of these moves.
struct TideKey: Equatable {
    var readTime: Date?
    var history: Int
    var minute: Int
    var thresholds: Thresholds
}

/// The tide pieces worked out, by plan. Not published: a view reads it while drawing.
final class TideCache {
    var info: [String: (key: TideKey, value: TideInfo?)] = [:]
    var pie: [String: (key: TideKey, value: WeekPie?)] = [:]
}

extension AppModel {
    private func tideKey(_ org: Org) -> TideKey {
        TideKey(readTime: latest[org.id]?.time, history: history.count, minute: Int(now.timeIntervalSince1970 / 60),
                thresholds: settings.thresholds)
    }

    /// The plan's chart and verdict for the widget, notch and strip; nil when it has never been read.
    func tide(for org: Org) -> TideInfo? {
        let key = tideKey(org)
        if let hit = tideCache.info[org.id], hit.key == key { return hit.value }
        var value: TideInfo?
        if let reading = latest[org.id]?.adjusted(to: now), let state = state(for: org) {
            let verdict = PlanVerdict.make(reading: reading, forecast: forecast(for: org), state: state, now: now,
                                           formatting: formatting, thresholds: settings.thresholds)
            value = TideInfo(chart: LeftChart.make(reading: reading, history: history, now: now), verdict: verdict)
        }
        tideCache.info[org.id] = (key, value)
        return value
    }

    /// The plan's week as a pie: only the notch at rest draws it, so only it asks.
    func weekPie(for org: Org) -> WeekPie? {
        let key = tideKey(org)
        if let hit = tideCache.pie[org.id], hit.key == key { return hit.value }
        let value = latest[org.id].flatMap { WeekPie.make(reading: $0.adjusted(to: now), history: history, now: now) }
        tideCache.pie[org.id] = (key, value)
        return value
    }

    /// Claude Code's mood for the status slot at the start of the widget: only when no plan card carries it
    /// (plan limits off, a message in place of the plans, or its plan isn't shown). Plan limits off always
    /// shows one, idle when nothing reports a mood.
    var leftStatusMood: CodeMood? {
        if limitsOff { return codeMood ?? .idle }
        return WidgetSizing.leftStatus(codeMood, plansShown: widgetMessage == nil && !orgs.isEmpty,
                                       onShownPlan: orgs.contains { $0.id == claudeCodeOrg })
    }
}

/// Hands a slot's frame, in screen points, to its click.
final class ScreenFrameBox: ObservableObject {
    weak var view: NSView?

    var screenRect: CGRect {
        guard let view, let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// Only reports a frame: clicks and right clicks go to what is drawn over or under it, never to this view.
private final class FrameReaderView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ScreenFrameReader: NSViewRepresentable {
    let box: ScreenFrameBox

    func makeNSView(context: Context) -> NSView {
        let view = FrameReaderView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

/// A plan as a tide (the mockups' `tide_slot`): `TideWater` behind, the name in small caps with Claude Code's
/// status when it is signed in to this plan, the big used %, the verdict and the 5-hour line. XS is the %
/// over the water and the shape with the plan's first letter; narrow is the short verdict and no reset time;
/// full has the verdict in full, the chip beside the name and the reset time when there is room. Clicking it
/// opens the plan's details card from the slot's frame.
struct TideSlotView: View {
    @ObservedObject var model: AppModel
    let org: Org
    let form: TideSlotLayout.Form
    /// The slot's width in points at text size 1.
    let slot: CGFloat
    let k: CGFloat
    /// Opens the details with the slot's frame on screen.
    let open: (CGRect) -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var frame = ScreenFrameBox()
    @Environment(\.renderStyle) private var renderStyle

    var body: some View {
        let tide = model.tide(for: org)
        let old = model.isOld(org)
        let mood = model.codeMood(for: org)
        ZStack(alignment: .topLeading) {
            if let chart = tide?.chart {
                TideWater(chart: chart, style: model.settings.tideStyle, locked: chart.lockedFrom != nil, isOld: old,
                          planID: org.id)
                    .equatable()
            }
            // The room is measured, not assumed: a big Dock icon size or an auto-hiding Dock makes the bar shorter
            // than the slot's content, which would be cut off.
            GeometryReader { geo in
                content(tide, old: old, mood: mood, room: geo.size.height / k)
            }
        }
        .frame(width: slot * k)
        .frame(maxHeight: .infinity)
        .clipped()
        // Image renders can't draw an AppKit view (they'd show a "prohibited" sign), and have no window to click in.
        .background { if renderStyle == .live { ScreenFrameReader(box: frame) } }
        .orgButton(label(mood)) { open(frame.screenRect) }
    }

    private func label(_ mood: CodeMood?) -> String {
        model.summary(for: org) + (mood.map { " Claude Code: \($0.word)." } ?? "")
    }

    @ViewBuilder
    private func content(_ tide: TideInfo?, old: Bool, mood: CodeMood?, room: CGFloat) -> some View {
        let p = TidePalette.for(scheme)
        let state = model.state(for: org)
        let fit = TideSlotLayout.fit(form, room: Double(room))
        if let glance = model.glance(for: org), let tide {
            switch form {
            case .xs: xs(glance, state, old, mood, p, fit)
            case .narrow: narrow(glance, tide, state, old, mood, p, fit)
            case .full: full(glance, tide, state, old, mood, p, fit)
            }
        } else {
            missing(state, old, mood, p, fit)
        }
    }

    private func percent(_ glance: Glance, _ size: CGFloat, _ old: Bool, _ p: TidePalette) -> some View {
        let used = Int((glance.week.used ?? 0).rounded())
        return (Text("\(used)").font(.system(size: size * k, weight: .light)).foregroundColor(old ? p.dim : p.fg)
                + Text("%").font(.system(size: size * 0.48 * k, weight: .regular)).foregroundColor(p.dim))
            .monospacedDigit().lineLimit(1).fixedSize()
    }

    private func nameRow(_ state: PlanState?, _ old: Bool, _ mood: CodeMood?, initialOnly: Bool = false, _ p: TidePalette) -> some View {
        HStack(spacing: 5 * k) {
            StateShape(state, hollow: old, size: 7 * k)
            Text((initialOnly ? String(org.name.prefix(1)) : org.name).uppercased())
                .font(Theme.font(10 * k, .semibold)).tracking(0.7 * k)
                .foregroundStyle(p.dim).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if let mood, !initialOnly {
                StatusChip(mood: mood, compact: !(form == .full && TideSlotLayout.chipInline(slot: Double(slot))), scale: k)
            }
        }
    }

    private func verdictInk(_ state: PlanState?, _ old: Bool, _ p: TidePalette) -> Color {
        old ? p.dim : (state == .fine || state == nil ? p.fg : p.red)
    }

    private func fiveHour(_ glance: Glance, _ old: Bool, _ p: TidePalette, reset: Bool) -> some View {
        let session = glance.session
        // A week that's full leaves nothing to count in the 5 hours: a dash and an empty line, as the mockup draws it.
        let weekOut = (glance.week.used ?? 0) >= 100
        return HStack(spacing: 5 * k) {
            Text("5h").foregroundStyle(p.faint).fixedSize()
            FiveHourLine(used: weekOut ? nil : session.used)
                .inUseEffect(model.inUse(for: org), .line(fill: (session.used ?? 0) / 100), settings: model.settings,
                             color: Palette.blue, under: true)
            Text(weekOut ? "—" : session.percentText).fontWeight(.semibold)
                .foregroundStyle(old ? p.dim : (session.tone == .red && !weekOut ? p.red : p.fg)).fixedSize()
            if reset, !weekOut { Text(model.glanceNote(session)).foregroundStyle(p.dim).lineLimit(1).fixedSize() }
        }
        .font(Theme.font(10.5 * k))
        .lineLimit(1)
    }

    private func full(_ glance: Glance, _ tide: TideInfo, _ state: PlanState?, _ old: Bool, _ mood: CodeMood?, _ p: TidePalette,
                      _ fit: TideSlotLayout.Fit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow(state, old, mood, p)
            Spacer(minLength: 2 * k)
            HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                percent(glance, 25, old, p)
                Text(TideSlotLayout.showsReset(slot: Double(slot)) ? tide.verdict.line : tide.verdict.short.joined(separator: " "))
                    .font(Theme.font(13 * k, state == .fine ? .regular : .semibold))
                    .foregroundStyle(verdictInk(state, old, p)).lineLimit(1).truncationMode(.tail)
            }
            if fit.fiveHour {
                Spacer(minLength: 2 * k)
                fiveHour(glance, old, p, reset: TideSlotLayout.showsReset(slot: Double(slot)))
            }
        }
        .padding(.horizontal, 12 * k).padding(.vertical, fit.padding * k)
    }

    private func narrow(_ glance: Glance, _ tide: TideInfo, _ state: PlanState?, _ old: Bool, _ mood: CodeMood?, _ p: TidePalette,
                        _ fit: TideSlotLayout.Fit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow(state, old, mood, p)
            Spacer(minLength: 2 * k)
            VStack(alignment: .leading, spacing: 2 * k) {
                percent(glance, 20, old, p)
                Text(tide.verdict.short.joined(separator: " ")).font(Theme.font(11 * k, state == .fine ? .regular : .semibold))
                    .foregroundStyle(verdictInk(state, old, p)).lineLimit(1).minimumScaleFactor(0.75)
            }
            if fit.fiveHour {
                Spacer(minLength: 2 * k)
                fiveHour(glance, old, p, reset: false)
            }
        }
        .padding(.horizontal, 9 * k).padding(.vertical, fit.padding * k)
    }

    private func xs(_ glance: Glance, _ state: PlanState?, _ old: Bool, _ mood: CodeMood?, _ p: TidePalette,
                    _ fit: TideSlotLayout.Fit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow(state, old, nil, initialOnly: true, p)
            Spacer(minLength: 2 * k)
            percent(glance, 20, old, p)
        }
        .padding(.horizontal, 7 * k).padding(.vertical, fit.padding * k)
        .overlay(alignment: .topTrailing) {
            if let mood { StatusChip(mood: mood, compact: true, scale: k).padding(.top, 5 * k).padding(.trailing, 4 * k) }
        }
    }

    /// No reading yet, or why not.
    private func missing(_ state: PlanState?, _ old: Bool, _ mood: CodeMood?, _ p: TidePalette, _ fit: TideSlotLayout.Fit) -> some View {
        let problem = model.orgProblems[org.id]
        let title = problem == nil ? "No reading yet" : "Couldn’t read"
        return VStack(alignment: .leading, spacing: 0) {
            nameRow(state, old, mood, initialOnly: form == .xs, p)
            Spacer(minLength: 2 * k)
            if form != .xs {
                Text(title).font(Theme.font(11 * k, .semibold)).foregroundStyle(p.fg).lineLimit(1)
                if let problem, form == .full {
                    let text = UsageCopy.short(problem)
                    Text(text.prefix(1).uppercased() + text.dropFirst()).font(Theme.font(10.5 * k))
                        .foregroundStyle(p.dim).lineLimit(2)
                }
            }
            Spacer(minLength: 2 * k)
        }
        .padding(.horizontal, (form == .xs ? 7 : form == .narrow ? 9 : 12) * k).padding(.vertical, fit.padding * k)
        .overlay(alignment: .topTrailing) {
            // At XS the name row has no room for the chip: Claude Code's status is a badge on the corner.
            if form == .xs, let mood { StatusChip(mood: mood, compact: true, scale: k).padding(.top, 5 * k).padding(.trailing, 4 * k) }
        }
    }
}

/// A 1 pt line between slots, the sky's own.
struct TideDivider: View {
    var vertical = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        if vertical { Rectangle().fill(p.line).frame(height: 1) } else { Rectangle().fill(p.line).frame(width: 1) }
    }
}

/// The widget's background: the sky, in the same rounded shape and edge the frosted glass had.
struct WidgetSky: ViewModifier {
    let moon: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content
            .background(TideSky(.widget(moon: moon)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: Theme.borderWidth))
    }
}

extension View {
    func widgetSky(moon: Bool) -> some View { modifier(WidgetSky(moon: moon)) }
}
