import SwiftUI
import TidemarkCore

/// The week's brief: the lede, four tiles, the project bar and its legend, and the days that have
/// time. Drawn with plain stacks so it can be copied as a picture.
struct BriefCard: View {
    let week: WeekModel
    let now: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !week.brief.isEmpty {
                Text(week.brief)
                    .font(Theme.font(15))
                    .foregroundStyle(Palette.bright)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tiles
            if week.sessions == 0 {
                Text(WindowCopy.emptyWeek).font(Theme.font(13)).foregroundStyle(Palette.dim)
            } else {
                if !week.projects.isEmpty {
                    ProjectBar(projects: week.projects).accessibilityHidden(true)
                    legend
                }
                days
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 1))
    }

    private var tiles: some View {
        HStack(spacing: 1) {
            tile("Hours", HoursText.format(week.total), "overlaps counted once")
            tile("Sessions", "\(week.sessions)", WindowCopy.sessionsDetail(week))
            tile("Commits", "\(week.commits)", WindowCopy.commitsDetail(week))
            tile("Projects", "\(week.projects.count)", label: WindowCopy.projectsDetail(week)) {
                if let parts = WindowCopy.projectsDetailParts(week) {
                    // A long name gives way; "took 44%" always shows.
                    HStack(spacing: 0) {
                        Text(parts.name).lineLimit(1).truncationMode(.tail)
                        Text(parts.rest).lineLimit(1).fixedSize()
                    }
                } else {
                    Text(WindowCopy.projectsDetail(week))
                }
            }
        }
        .background(Palette.line)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func tile(_ k: String, _ n: String, _ l: String) -> some View {
        tile(k, n, label: l) { Text(l).lineLimit(1).truncationMode(.tail) }
    }

    private func tile<Detail: View>(_ k: String, _ n: String, label l: String, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(Theme.font(11)).foregroundStyle(Palette.faint)
            Text(n).font(Theme.font(20, .bold)).foregroundStyle(Palette.bright)
            detail().font(Theme.font(11.5)).foregroundStyle(Palette.dim)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tile)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(k): \(n), \(l)")
    }

    private var legend: some View {
        WeekFlowLayout(spacing: 14, lineSpacing: 4) {
            ForEach(week.projects, id: \.name) { project in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.c[min(project.colorIndex, 6)]).frame(width: 8, height: 8)
                    Text(project.name).foregroundStyle(Palette.fg).lineLimit(1).truncationMode(.tail)
                    Text(HoursText.format(project.seconds)).foregroundStyle(Palette.dim)
                }
                .font(Theme.font(12))
                .frame(maxWidth: 320, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var days: some View {
        let shown = (0..<7).filter { week.perDay.indices.contains($0) && week.perDay[$0] > 0 }
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<7, id: \.self) { slot in
                if slot < shown.count {
                    day(shown[slot])
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func day(_ d: Int) -> some View {
        let today = calendar.isDate(week.days[d], inSameDayAs: now)
        let note = week.dayNotes.indices.contains(d) ? week.dayNotes[d] : ""
        return VStack(alignment: .leading, spacing: 0) {
            Text(WindowCopy.dayHeading(week, day: d, now: now, calendar: calendar))
                .font(Theme.font(12, .bold))
                .foregroundStyle(today ? Palette.blueInk : Palette.bright)
            Text(WindowCopy.dayHours(week, day: d, now: now, calendar: calendar))
                .font(Theme.font(11)).foregroundStyle(Palette.dim)
            if !note.isEmpty {
                Text(note).font(Theme.font(12)).foregroundStyle(Palette.fg).padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The bar of a week's projects, each as wide as its share, with 2 pt gaps.
struct ProjectBar: View {
    let projects: [ProjectTotal]

    var body: some View {
        let shown = projects.filter { $0.seconds > 0 }
        let total = shown.reduce(0) { $0 + $1.seconds }
        GeometryReader { geo in
            let room = max(geo.size.width - 2 * CGFloat(max(shown.count - 1, 0)), 0)
            HStack(spacing: 2) {
                ForEach(shown, id: \.name) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.c[min(p.colorIndex, 6)])
                        .frame(width: total > 0 ? room * p.seconds / total : 0)
                }
            }
        }
        .frame(height: 8)
    }
}

/// Wraps its children onto lines, as many to a line as fit.
struct WeekFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}
