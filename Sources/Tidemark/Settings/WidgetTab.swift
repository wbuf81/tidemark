import SwiftUI
import TidemarkCore

/// Widget: where the widget or the notch sits and how big it is, and the in-use effect.
struct WidgetTab: View {
    @ObservedObject var hub: SettingsHub
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel

    init(hub: SettingsHub) {
        self.hub = hub
        settings = hub.settings
        model = hub.model
    }

    static let notchShapes: [(NotchLook, String)] = [(.hardware, "Hardware notch"), (.island, "Floating island")]
    static let notchPlaces: [(NotchPlace, String)] = [(.topRight, "Top right"), (.bottomRight, "Bottom right")]
    static let notchSizes: [(NotchOpenSize, String)] = [(.m, "Medium"), (.l, "Large")]
    static let layouts: [(LayoutChoice, String)] = [(.automatic, "Automatic (vertical on the sides)"),
                                                    (.horizontal, "Horizontal"), (.vertical, "Vertical")]
    /// Position's extra choice while the widget sits where it was dragged, between the snap points.
    static let draggedSpot = "Where you dragged it"

    var body: some View {
        Form {
            Section("Display") {
                if settings.displayMode == .notch { notch } else { widget }
            }
            if settings.displayMode != .notch {
                Section("In use") {
                    Picker("In-use effect", selection: $settings.effectStyle) {
                        ForEach(EffectStyle.allCases, id: \.self) { Text(WidgetView.title($0)).tag($0) }
                    }
                    Picker("Amount", selection: $settings.effectAmount) {
                        ForEach(EffectAmount.allCases, id: \.self) { Text(WidgetView.title($0)).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var notch: some View {
        Picker("Shape", selection: $settings.notchLook) {
            ForEach(Self.notchShapes, id: \.0) { Text($0.1).tag($0.0) }
        }
        Picker("Place", selection: $settings.notchPlace) {
            ForEach(Self.notchPlaces, id: \.0) { Text($0.1).tag($0.0) }
        }
        LabeledContent("Width") {
            PointSlider(title: "Width", value: shownNotchWidth, range: notchRange) { settings.notchWidth = $0 }
        }
        Picker("Opens to", selection: $settings.notchOpensTo) {
            ForEach(Self.notchSizes, id: \.0) { Text($0.1).tag($0.0) }
        }
        Toggle("Status rim", isOn: $settings.notchRim)
        tidePicker(note: "Or right-click the notch")
        textSizePicker
    }

    @ViewBuilder private var widget: some View {
        Picker("Position", selection: positionBinding) {
            if case .free? = settings.widgetSpot { Text(Self.draggedSpot).tag(SnapPoint?.none) }
            ForEach(SnapPoint.allCases, id: \.self) { Text(WidgetView.title($0)).tag(Optional($0)) }
        }
        Picker("Layout", selection: Binding(get: { settings.layoutChoice }, set: hub.setLayout)) {
            ForEach(Self.layouts, id: \.0) { Text($0.1).tag($0.0) }
        }
        LabeledContent("Width") {
            VStack(alignment: .trailing, spacing: 2) {
                PointSlider(title: "Width", value: shownWidth, range: widthRange, set: hub.setWidth)
                if let fitted = fittedWidth { Caption("Fitted to \(Int(fitted)) pt beside the Dock") }
            }
        }
        tidePicker(note: "Or right-click the widget")
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Show the week", isOn: $settings.showWeekBand)
            Caption("Or right-click the widget")
        }
        textSizePicker
        // Fitting and measuring only apply to the horizontal widget.
        if !model.vertical {
            Toggle("Fit beside the Dock", isOn: $settings.fitBesideDock)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Measure the Dock exactly", isOn: Binding(get: { settings.measureDock }, set: hub.setMeasureDock))
                if !settings.measureDock { Caption("Asks for Accessibility; reads only the Dock’s size") }
                if settings.measureDock {
                    if hub.dockAccessAllowed {
                        Caption("Reads only the Dock's size, so minimized windows count.")
                    } else {
                        HStack {
                            Caption("Needs Accessibility permission.")
                            Spacer()
                            Button("Allow in System Settings…", action: hub.askDockAccess)
                        }
                    }
                }
            }
        }
    }

    private func tidePicker(note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tide", selection: $settings.tideStyle) {
                ForEach(TideStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Caption(note)
        }
    }

    private var textSizePicker: some View {
        Picker("Text size", selection: Binding(
            get: { WidgetView.sizes.min { abs($0.1 - settings.sizeScale) < abs($1.1 - settings.sizeScale) }?.1 ?? 1 },
            set: hub.setSize)) {
            ForEach(WidgetView.sizes, id: \.1) { Text($0.0).tag($0.1) }
        }
    }

    /// The snap point the widget sits at (the bottom right until it has been moved), or nil when it
    /// was dragged somewhere between the points.
    private var positionBinding: Binding<SnapPoint?> {
        Binding(
            get: {
                switch settings.widgetSpot {
                case nil: SnapPoint.bottomRight
                case .snapped(let point)?: point
                case .free?: nil
                }
            },
            set: { if let point = $0 { hub.place(point) } })
    }

    private var widthRange: ClosedRange<Double> {
        model.vertical ? WidgetSizing.stripMin...WidgetSizing.stripMax
            : WidgetSizing.widthRange(orgs: model.orgs.count, advice: model.advice != nil)
    }

    private var notchRange: ClosedRange<Double> { NotchSizing.restRange(orgs: model.orgs.count) }

    private var shownNotchWidth: Double {
        min(max(settings.notchWidth, notchRange.lowerBound), notchRange.upperBound)
    }

    private var shownWidth: Double {
        min(max(model.vertical ? settings.stripWidth : settings.widgetWidth, widthRange.lowerBound), widthRange.upperBound)
    }

    /// The width the horizontal widget is drawn at when that's narrower than the saved one.
    private var fittedWidth: Double? {
        let drawn = Double(model.widgetLayoutWidth)
        return !model.vertical && drawn < shownWidth - 0.5 ? drawn : nil
    }
}
