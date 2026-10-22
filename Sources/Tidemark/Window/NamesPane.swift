import SwiftUI
import TidemarkCore

/// Names & tags: rename sessions, tag them, move sessions between projects, hide a project's titles.
/// Every edit is one undo step, on the window's undo manager (Edit → Undo).
struct NamesPane: View {
    @ObservedObject private var model: NamesPaneModel

    /// The model belongs to the window, so it, and its undo steps, outlast the pane.
    init(model: NamesPaneModel) {
        self.model = model
    }

    var body: some View {
        NamesView(model: model)
            .onAppear { model.reload() }
    }
}

private struct NamesView: View {
    @ObservedObject var model: NamesPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: "Names & tags") {
                PaneButton(title: "Sessions", primary: model.kind == .sessions) { model.kind = .sessions }
                PaneButton(title: "Projects", primary: model.kind == .projects) { model.kind = .projects }
                PaneButton(title: "Cowork folders", primary: model.kind == .folders) { model.kind = .folders }
            }
            if model.kind == .sessions { ruleBar }
            if let message = model.ruleError {
                Text(message).font(.system(size: 11.5)).foregroundStyle(Palette.redInk)
            }
            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 0) {
                    GridRow {
                        heading("Name")
                        heading("Tags")
                        heading("In project")
                        heading("Hours").gridColumnAlignment(.trailing)
                    }
                    Divider().gridCellColumns(4).overlay(Palette.line)
                    ForEach(model.rows) { row in
                        NameRowView(model: model, row: row)
                        if let message = model.errors[row.id] {
                            GridRow {
                                Text(message)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.redInk)
                                    .gridCellColumns(4)
                                    .accessibilityLabel(message)
                            }
                        }
                        Divider().gridCellColumns(4).overlay(Palette.line)
                    }
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            if let message = model.errors["names"] {
                                Text(message).font(.system(size: 11.5)).foregroundStyle(Palette.redInk)
                            }
                            PaneNote("Rename by title or by a \"starts with\" rule, tag, move sessions between projects, and hide a project’s titles.")
                        }
                        .padding(.top, 10)
                        .gridCellColumns(4)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tile)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.faint)
            .padding(.horizontal, 4).padding(.vertical, 5)
    }

    @ViewBuilder private var ruleBar: some View {
        if model.addingRule {
            HStack(spacing: 8) {
                Text("Titles starting with").font(.system(size: 12)).foregroundStyle(Palette.dim)
                CommitField(text: model.rulePrefix, placeholder: "Email Brief Daily", label: "Start of the titles",
                            startFocused: true, onChange: { model.rulePrefix = $0 }) { model.rulePrefix = $0 }
                    .frame(maxWidth: 260)
                PaneButton(title: "Add rule") {
                    model.addRule(prefix: model.rulePrefix)
                    model.rulePrefix = ""
                    model.addingRule = false
                }
                PaneButton(title: "Cancel") { model.rulePrefix = ""; model.addingRule = false }
            }
        } else {
            HStack { PaneButton(title: "+ Rule", label: "Add a starts-with rule") { model.addingRule = true }; Spacer() }
        }
    }
}

private struct NameRowView: View {
    @ObservedObject var model: NamesPaneModel
    let row: NameRow

    var body: some View {
        GridRow(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                CommitField(text: row.entry.name ?? "", placeholder: row.key,
                            label: PanesCopy.label(.name, for: row)) { model.setName($0, row: row) }
                if let line = PanesCopy.subline(row, book: model.book) {
                    Text(line).font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                }
            }
            .frame(minWidth: 230, maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 5)

            TagsField(tags: row.entry.tags ?? [], label: PanesCopy.label(.tags, for: row)) { model.setTags($0, row: row) }
                .frame(width: 190, alignment: .topLeading)
                .padding(.vertical, 5)

            VStack(alignment: .leading, spacing: 4) {
                ProjectField(row: row, known: model.knownProjects) { model.setProject($0, row: row) }
                if row.kind == .projects {
                    Toggle("Hide titles", isOn: Binding(get: { row.entry.hideTitles == true },
                                                         set: { model.setHideTitles($0, row: row) }))
                        .font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
                        .accessibilityLabel(PanesCopy.label(.hideTitles, for: row))
                }
            }
            .frame(width: 170, alignment: .topLeading)
            .padding(.vertical, 5)

            Text(PanesCopy.hours(row.seconds))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Palette.fg)
                .frame(width: 44, alignment: .trailing)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - Fields

/// The mockup's `.fld`: a bordered text field that commits on Return or when it loses focus.
struct CommitField: View {
    let text: String
    let placeholder: String
    let label: String
    var startFocused = false
    /// Called on every keystroke, for fields whose text is read before they commit.
    var onChange: ((String) -> Void)?
    let commit: (String) -> Void
    @StateObject private var box: PaneBox<String>
    @FocusState private var focused: Bool

    init(text: String, placeholder: String, label: String, startFocused: Bool = false,
         onChange: ((String) -> Void)? = nil, commit: @escaping (String) -> Void) {
        self.text = text
        self.placeholder = placeholder
        self.label = label
        self.startFocused = startFocused
        self.onChange = onChange
        self.commit = commit
        _box = StateObject(wrappedValue: PaneBox(text))
    }

    private var draft: Binding<String> {
        Binding(get: { box.value }, set: { box.value = $0; onChange?($0) })
    }

    var body: some View {
        TextField("", text: draft, prompt: Text(placeholder).foregroundColor(Palette.faint))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Palette.bright)
            .lineLimit(1)
            .focused($focused)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.tile))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused ? Palette.blue : Palette.line, lineWidth: 1))
            .accessibilityLabel(label)
            .onSubmit(save)
            .onChange(of: focused) { _, now in if !now { save() } }
            .onChange(of: text) { _, new in if !focused { box.value = new } }
            .onAppear { if startFocused { focused = true } }
    }

    private func save() {
        guard box.value != text else { return }
        commit(box.value)
    }
}

/// Tag chips with "add tags" after them.
private struct TagsField: View {
    let tags: [String]
    let label: String
    let commit: ([String]) -> Void
    @StateObject private var box = PaneBox("")

    var body: some View {
        FlowRow(spacing: 2) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text(tag)
                    Button { commit(tags.filter { $0 != tag }) } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(tag)")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.blueInk)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.blue.opacity(0.14)))
            }
            TextField("", text: $box.value, prompt: Text("add tags").foregroundColor(Palette.faint))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.bright)
                .frame(minWidth: 60, maxWidth: 110)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.tile))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line, lineWidth: 1))
                .accessibilityLabel(label)
                .onSubmit {
                    let added = PanesCopy.parseTags(box.value)
                    box.value = ""
                    guard !added.isEmpty else { return }
                    commit(tags + added.filter { !tags.contains($0) })
                }
        }
    }
}

/// The project field: type a name or pick one the calendar already knows.
private struct ProjectField: View {
    let row: NameRow
    let known: [String]
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            CommitField(text: row.entry.project ?? "", placeholder: row.kind == .projects ? "itself" : row.currentProject,
                        label: PanesCopy.label(.project, for: row), commit: commit)
            Menu {
                ForEach(known.filter { $0 != row.key }, id: \.self) { name in
                    Button(name) { commit(name) }
                }
                if row.entry.project != nil {
                    Divider()
                    Button(row.kind == .projects ? "Itself" : "Back to \(row.currentProject)") { commit("") }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Known projects for \(PanesCopy.displayTitle(row))")
        }
    }
}

/// Lays children out left to right and wraps them.
private struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
