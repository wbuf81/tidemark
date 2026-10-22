import SwiftUI
import TidemarkCore

/// One stop in the sidebar: a section or a plan.
enum SidebarStop: Equatable {
    case section(MainSection)
    case plan(String)
}

/// The window's left column: the five sections, then Plans. One focusable column; ↑ and ↓ move
/// the selection, which opens at once.
struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Binding var section: MainSection
    @Binding var plan: String?
    @FocusState private var focused: Bool

    private var plans: [Org] { model.orgs }

    private var stops: [SidebarStop] {
        MainSection.allCases.map { .section($0) } + plans.map { .plan($0.id) }
    }

    private var current: SidebarStop {
        if section == .usage, let plan, plans.contains(where: { $0.id == plan }) { return .plan(plan) }
        return .section(section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MainSection.allCases, id: \.self) { item in
                row(selected: current == .section(item)) {
                    Image(systemName: item.symbol).font(.system(size: 12)).frame(width: 16)
                    Text(item.title)
                } action: {
                    if item == .usage { plan = nil }
                    section = item
                }
                .accessibilityLabel(item.title)
            }
            if !plans.isEmpty {
                Text("Plans")
                    .font(Theme.font(11, .semibold))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(plans) { org in
                    row(selected: current == .plan(org.id)) {
                        StateShape(model.state(for: org), hollow: model.isOld(org), size: 9).frame(width: 16)
                        Text(org.name).lineLimit(1).truncationMode(.tail)
                    } action: {
                        plan = org.id
                        section = .usage
                    }
                    .accessibilityLabel(model.summary(for: org))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 188)
        .frame(maxHeight: .infinity)
        .background(Palette.page)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .up: move(-1)
            case .down: move(1)
            default: break
            }
        }
        .onKeyPress(.return) { .handled }   // the selected stop is already open
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tidemark sections")
    }

    private func move(_ step: Int) {
        guard let i = stops.firstIndex(of: current) else { return }
        let next = min(max(i + step, 0), stops.count - 1)
        switch stops[next] {
        case .section(let s):
            if s == .usage { plan = nil }
            section = s
        case .plan(let id):
            plan = id
            section = .usage
        }
    }

    private func row<Label: View>(selected: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }
                .font(Theme.font(13, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.bright : Palette.fg)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.selection : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Palette.blue, lineWidth: selected && focused ? 2 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
