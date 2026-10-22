import SwiftUI
import TidemarkCore

/// Settings' small repeated parts. Captions are `Palette.dim` and values `Palette.fg`, so both pass
/// 4.5:1 in light (macOS's own secondary grey doesn't).
struct Caption: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
    }
}

/// A row with a label, a caption under it, and a control at the trailing edge.
struct SettingRow<Control: View>: View {
    var title: String
    var caption: String?
    @ViewBuilder var control: Control

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption { Caption(caption) }
            }
        }
    }
}

/// A switch with a caption under its label.
struct CaptionedToggle: View {
    var title: String
    var caption: String?
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption { Caption(caption) }
            }
        }
    }
}

/// A value shown at a row's trailing edge, in the main text colour and even-width digits.
struct SettingValue: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).monospacedDigit().foregroundStyle(Palette.fg)
    }
}

/// A slider that rounds to whole points as it moves; with no `step:`, it draws no tick marks (S4.1).
struct PointSlider: View {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var set: (Double) -> Void

    var body: some View {
        HStack {
            Slider(value: Binding(get: { value }, set: { set(($0 / 2).rounded() * 2) }), in: range)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) points")
            SettingValue("\(Int(value)) pt").frame(width: 52, alignment: .trailing)
        }
    }
}
