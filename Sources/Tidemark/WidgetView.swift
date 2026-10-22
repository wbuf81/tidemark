import SwiftUI
import TidemarkCore

/// The always-on widget: one glance per org at the size its width allows (see `WidgetSizing`),
/// plus the switch band when there's advice. A horizontal bar as tall as the Dock, or a strip on
/// the left and right edges. Contents scale with the Dock's icon size and the owner's text size.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var actions: AppActions
    /// The width to lay out at, in points at text size 1; nil uses the model's (what `DockController` set).
    var width: CGFloat? = nil

    var body: some View {
        Group { if model.vertical { strip } else { bar } }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in actions.dragChanged() }
            .onEnded { _ in actions.dragEnded() })
        .simultaneousGesture(MagnificationGesture()
            .onChanged { actions.pinch($0, false) }
            .onEnded { actions.pinch($0, true) })
        .onTapGesture { actions.openWindow(.usage, nil) }
        .contextMenu { WidgetMenu(model: model, actions: actions) }
    }

    private var k: CGFloat { model.widgetScale }

    private var layoutWidth: CGFloat { width ?? model.layoutWidth }

    @ViewBuilder
    private var bar: some View {
        if model.limitsOff {
            limitsOffBar
        } else {
            let layout = WidgetSizing.layout(width: Double(layoutWidth), orgs: model.orgs.count, advice: model.advice != nil,
                                             week: model.week != nil && !model.orgs.isEmpty && model.widgetMessage == nil,
                                             status: model.leftStatusMood)
            // A message (or no plans yet) needs room for its words beside the status slot.
            let wide = model.orgs.isEmpty || model.widgetMessage != nil
            let drawn = wide ? max(layout.width, layout.statusWidth + layout.bandWidth + 230) : layout.width
            GlanceRow(model: model, actions: actions, layout: layout, k: k)
                .frame(width: CGFloat(drawn) * k, height: model.widgetHeight)
                .widgetSky(moon: drawn >= 400)
        }
    }

    /// Plan limits off: Claude Code's status and the week, nothing else.
    private var limitsOffBar: some View {
        let mood = model.codeMood ?? .idle
        let status = WidgetSizing.statusWidth(for: .l, mood: mood)
        return HStack(spacing: 0) {
            StatusSlot(mood: mood, width: CGFloat(status) * k, k: k)
            if let week = model.week {
                WeekBandView(week: week, now: model.now, k: k, showsTopHours: true, open: { actions.openWindow(.week, nil) })
                    .frame(width: CGFloat(WidgetSizing.weekBand + 28) * k)
                    .overlay(alignment: .leading) { GlanceDivider(vertical: false, k: k) }
            }
        }
        .frame(height: model.widgetHeight)
        .widgetSky(moon: false)
    }

    private var strip: some View {
        let w = CGFloat(WidgetSizing.clampStrip(Double(layoutWidth)))
        let size = WidgetSizing.stripSize(width: Double(w))
        return VStack(spacing: 0) {
            if let advice = model.advice {
                SwitchBandView(advice: advice, tone: model.adviceTone, wide: size == .wide, stacked: false, k: k, actions: actions)
                    .padding(.vertical, 5 * k)
                    .frame(maxWidth: .infinity)
                    .background(model.adviceTone.color.opacity(0.16))
                    .contentShape(Rectangle())
                    .onTapGesture { actions.openWindow(.usage, nil) }
            }
            if let mood = model.leftStatusMood {
                StatusSlot(mood: mood, width: w * k, k: k).frame(height: 54 * k)
                GlanceDivider(vertical: true, k: k)
            }
            if model.limitsOff {
                if let week = model.week {
                    WeekBandView(week: week, now: model.now, k: k, showsTopHours: true, open: { actions.openWindow(.week, nil) })
                        .padding(.vertical, 10 * k)
                }
            } else if let message = model.widgetMessage {
                StripMessage(message: message, size: size, k: k, actions: actions)
            } else {
                ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                    if index > 0 { TideDivider(vertical: true) }
                    StripGlanceView(model: model, org: org, width: w, k: k, open: { actions.openDetails(org.id, $0, .stripSlot) })
                }
            }
        }
        .frame(width: w * k)
        .widgetSky(moon: false)
    }

    static let sizes: [(String, Double)] = [("Small", 0.8), ("Match Dock", 1), ("Large", 1.25), ("Extra large", 1.5)]

    static func title(_ style: EffectStyle) -> String {
        switch style {
        case .sparks: "Sparks"
        case .flow: "Flow"
        case .shimmer: "Shimmer"
        case .off: "Off"
        }
    }

    static func title(_ amount: EffectAmount) -> String {
        switch amount {
        case .subtle: "Subtle"
        case .normal: "Normal"
        case .lots: "Lots"
        }
    }

    static func title(_ point: SnapPoint) -> String {
        switch point {
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        case .topRight: "Top right"
        case .topLeft: "Top left"
        case .rightMiddle: "Right side"
        case .leftMiddle: "Left side"
        }
    }
}

extension View {
    /// An org reads as one button to VoiceOver, its sentence also the tooltip.
    func orgButton(_ summary: String, open: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityHint("Opens the details")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .help(summary)
    }
}
