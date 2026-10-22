import SwiftUI
import TidemarkCore

extension GlanceLimit {
    /// "84%": a window that hasn't started is a real "0%", never a dash.
    var percentText: String { "\(Int((used ?? 0).rounded()))%" }
    /// The number alone, for the gauges.
    var numberText: String { "\(Int((used ?? 0).rounded()))" }
    /// Numbers take the tone's ink when it's amber or red.
    var textColor: Color { tone >= .amber ? tone.ink : Palette.bright }
}

private struct GlanceTrackKey: EnvironmentKey { static let defaultValue = Palette.track }

extension EnvironmentValues {
    /// The empty part of the glance bars and gauges: the theme's track, or the notch's own.
    var glanceTrack: Color {
        get { self[GlanceTrackKey.self] }
        set { self[GlanceTrackKey.self] = newValue }
    }
}

/// Diagonal stripes over a full limit's fill.
private struct Hatch: View {
    var spacing: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: max(spacing / 4, 0.6))
        }
    }
}

/// A limit's cell, `fill` (0...1) of it filled in the tone colour, hatched when `hatched`.
struct GlanceCell: View {
    let shape: RoundedRectangle
    let track: Color
    let color: Color
    let fill: CGFloat
    let hatched: Bool
    let k: CGFloat
    var vertical = false

    var body: some View {
        shape.fill(track)
            .overlay {
                GeometryReader { proxy in
                    Rectangle().fill(color)
                        .overlay { if hatched { Hatch(spacing: 3 * k) } }
                        .frame(width: vertical ? proxy.size.width : proxy.size.width * fill,
                               height: vertical ? proxy.size.height * fill : proxy.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
                }
                .clipShape(shape)
            }
    }
}

/// What the widget says when it has no plans to draw: signed out, loading, no plans, or why nothing
/// could be read. Full contrast, never dimmed, with a shape.
struct MessageCard: View {
    let message: GlanceMessage
    let k: CGFloat
    var actions: AppActions
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        VStack(alignment: .leading, spacing: 4 * k) {
            HStack(spacing: 6 * k) {
                StateShape(nil, size: 11 * k)
                Text(message.title).font(Theme.font(12.5 * k, .bold)).foregroundStyle(p.fg)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if !message.detail.isEmpty {
                Text(message.detail).font(Theme.font(11.5 * k)).foregroundStyle(p.dim)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if let action = message.action { ActionChip(title: action, k: k, action: perform).padding(.top, 2 * k) }
        }
        .padding(.horizontal, 14 * k)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func perform() {
        switch message.actionKind {
        case .retry: actions.refresh()
        case .signIn: actions.signIn()
        case .signInAnother: actions.signOut(); actions.signIn()
        }
    }
}

/// One plan in the side strip: its tide slot, narrow (or XS in a thin strip), stacked with the others.
struct StripGlanceView: View {
    @ObservedObject var model: AppModel
    let org: Org
    /// The strip's width in points at text size 1.
    let width: CGFloat
    let k: CGFloat
    let open: (CGRect) -> Void

    var body: some View {
        TideSlotView(model: model, org: org, form: TideSlotLayout.stripForm(width: Double(width)), slot: width, k: k, open: open)
            .frame(height: 86 * k)
    }
}

/// The strip's message: one word when narrow (the sentence is its tooltip and VoiceOver label), the
/// words and the button when wide. Side padding 8 pt.
struct StripMessage: View {
    let message: GlanceMessage
    let size: StripSize
    let k: CGFloat
    var actions: AppActions

    var body: some View {
        Group {
            if size == .narrow {
                VStack(spacing: 3 * k) {
                    StateShape(nil, size: 9 * k)
                    Text(message.narrow).font(Theme.font(10 * k, .semibold)).foregroundStyle(Palette.bright)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8 * k)
                    .help(message.sentence)
                    .accessibilityLabel(message.sentence)
            } else {
                MessageCard(message: message, k: k, actions: actions)
                    .padding(.horizontal, -6 * k)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14 * k)
    }
}

/// The switch band, Claude Code's status, a card per plan (or a message), and the week band side by
/// side: the widget's bar, and the notch's open card. The caller sets the frame.
struct GlanceRow: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    let layout: WidgetSizing.Layout
    let k: CGFloat
    /// What a slot's card is opened from: the widget bar, or the notch.
    var anchor: DetailsAnchor = .slot

    var body: some View {
        HStack(spacing: 0) {
            if let advice = model.advice, layout.band != .none {
                SwitchBandView(advice: advice, tone: model.adviceTone, wide: layout.band == .wide, stacked: true, k: k, actions: actions)
                    .frame(width: CGFloat(layout.bandWidth) * k)
                    .frame(maxHeight: .infinity)
                    .background(model.adviceTone.color.opacity(0.16))
                    .contentShape(Rectangle())
                    .onTapGesture { actions.openWindow(.usage, nil) }
            }
            if layout.statusWidth > 0, let mood = model.leftStatusMood {
                StatusSlot(mood: mood, width: CGFloat(layout.statusWidth) * k, k: k)
                    .overlay(alignment: .trailing) { TideDivider() }
            }
            if let message = model.widgetMessage {
                MessageCard(message: message, k: k, actions: actions)
            } else {
                ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                    TideSlotView(model: model, org: org, form: TideSlotLayout.form(for: layout.size), slot: CGFloat(layout.slot), k: k,
                                 open: { actions.openDetails(org.id, $0, anchor) })
                        .overlay(alignment: .leading) { if index > 0 { TideDivider() } }
                }
            }
            if layout.weekWidth > 0, let week = model.week {
                WeekBandView(week: week, now: model.now, k: k, open: { actions.openWindow(.week, nil) })
                    .frame(width: CGFloat(layout.weekWidth) * k)
                    .overlay(alignment: .leading) { GlanceDivider(vertical: false, k: k) }
            }
        }
    }
}

/// The switch band view: "⇄" alone, or with the plan to move to. Stacked ("harbor / first") beside the
/// plans; on one line atop the side strip. The arrow takes the tone of the advice glow.
struct SwitchBandView: View {
    let advice: Advice
    var tone: GlanceTone = .amber
    let wide: Bool
    var stacked = true
    let k: CGFloat
    var actions: AppActions

    var body: some View {
        Group {
            if stacked {
                VStack(spacing: 1 * k) {
                    Text("⇄").font(Theme.font(14 * k)).foregroundStyle(tone.ink == Palette.bright ? tone.color : tone.ink)
                    if wide {
                        Text("\(advice.target.name)\nfirst")
                            .font(Theme.font(max(9.5 * k, 9), .bold)).foregroundStyle(Palette.bright)
                            .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.8)
                    }
                }
            } else {
                HStack(spacing: 4 * k) {
                    Text("⇄").font(Theme.font(13 * k)).foregroundStyle(tone.ink)
                    if wide {
                        Text(advice.target.name).font(Theme.font(10 * k, .bold)).foregroundStyle(Palette.bright)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .help(summary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { actions.openWindow(.usage, nil) }
    }

    private var summary: String { "Move Claude Code to \(advice.target.name): \(advice.reason). \(Copy.howToSwitch(to: advice.target))" }
}

/// A 1 px line between plans, inset from the window's edges.
struct GlanceDivider: View {
    let vertical: Bool
    let k: CGFloat

    var body: some View {
        if vertical {
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 14 * k)
        } else {
            Rectangle().fill(Palette.line).frame(width: 1).padding(.vertical, 14 * k)
        }
    }
}

/// The context menu of the widget and the notch.
struct WidgetMenu: View {
    let model: AppModel
    let actions: AppActions

    var body: some View {
        let items = Self.items(signedIn: model.signedIn, calendar: model.week != nil, tide: model.settings.tideStyle,
                               setTide: { model.settings.tideStyle = $0 }, actions: actions)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            if let title = item.title {
                if item.children.isEmpty {
                    Button(title, action: item.action)
                } else {
                    Menu(title) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            Toggle(child.title ?? "", isOn: Binding(get: { child.checked }, set: { _ in child.action() }))
                        }
                    }
                }
            } else { Divider() }
        }
    }

    /// One entry: a button, a divider when `title` is nil, or a submenu when it has `children` (each
    /// with a check mark when `checked`).
    struct Item {
        var title: String?
        var action: () -> Void = {}
        var checked = false
        var children: [Item] = []

        static let divider = Item(title: nil)
    }

    /// The entries in order. Open week calendar shows once there is a week to open, Sign in… only while signed out,
    /// Tide when `tide` (the current style) is given. `--render` lists them in menus.md.
    static func items(signedIn: Bool, calendar: Bool, tide: TideStyle? = nil, setTide: @escaping (TideStyle) -> Void = { _ in },
                      actions: AppActions) -> [Item] {
        var items = [Item(title: "Refresh now", action: actions.refresh), Item(title: "Hide for 1 hour", action: actions.hideForAnHour)]
        if calendar { items.append(Item(title: "Open week calendar", action: { actions.openWindow(.week, nil) })) }
        if let tide {
            items.append(Item(title: "Tide", children: TideStyle.allCases.map { style in
                Item(title: style.label, action: { setTide(style) }, checked: style == tide)
            }))
        }
        items += [.divider, Item(title: "Settings…", action: { actions.openSettings(.general) })]
        if !signedIn { items.append(Item(title: "Sign in…", action: actions.signIn)) }
        items += [.divider, Item(title: "Quit Tidemark", action: actions.quit)]
        return items
    }
}
