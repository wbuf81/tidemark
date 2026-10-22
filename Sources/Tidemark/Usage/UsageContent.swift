import AppKit
import SwiftUI
import TidemarkCore

/// What the Usage pane draws, without its scroll view (the window scrolls it; renders draw it as is).
struct UsageContent: View {
    @ObservedObject var model: AppModel
    /// Watched too, so the model-limits toggle redraws the pane.
    @ObservedObject private var settings: Settings
    var actions: AppActions
    @ObservedObject var chosen: UsageSelection

    init(model: AppModel, actions: AppActions, chosen: UsageSelection) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
        self.actions = actions
        self.chosen = chosen
    }

    private var summary: UsageSummary {
        let states = Dictionary(uniqueKeysWithValues: model.orgs.compactMap { org in model.state(for: org).map { (org.id, $0) } })
        return UsageSummary.make(UsageInput(
            orgs: model.orgs, latest: model.latest, history: model.history, states: states,
            claudeCodeOrg: model.claudeCodeOrg, adviceTarget: model.advice?.target, signedIn: model.signedIn,
            limitsOff: model.limitsOff, orgProblems: model.orgProblems, showModelLimits: settings.showModelRows,
            showSessionLimits: settings.showSessionRows, thresholds: settings.thresholds, now: model.now,
            formatting: model.formatting))
    }

    /// The plan the panels show: the one chosen, else the most urgent (out, then the first to run out).
    static func shownOrg(_ model: AppModel, chosen: String?) -> Org? {
        if let chosen, let org = model.orgs.first(where: { $0.id == chosen }) { return org }
        for state in [PlanState.out, .runsOutEarly] {
            if let org = model.orgs.first(where: { model.state(for: $0) == state }) { return org }
        }
        return model.orgs.first
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = summary
        let p = TidePalette.for(scheme)
        VStack(alignment: .leading, spacing: 16) {
            switch s.mode {
            case .limitsOff:
                title("Usage", p)
                UsageMessage(title: UsageCopy.limitsOff.title, detail: UsageCopy.limitsOff.detail,
                             button: UsageCopy.limitsOff.button, action: actions.turnOnPlanLimits)
            case .signedOut:
                title("Usage", p)
                UsageMessage(title: UsageCopy.signedOut.title, detail: UsageCopy.signedOut.detail,
                             button: UsageCopy.signedOut.button, action: actions.signIn)
            case .ready:
                hero(p)
                banners
                cards(s)
                detail(s)
                modelToggle(s, p)
            }
        }
        .font(Theme.font(12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ text: String, _ p: TidePalette) -> some View {
        Text(text).font(.system(size: 30, weight: .light)).foregroundStyle(p.fg).accessibilityAddTraits(.isHeader)
    }

    // MARK: Headline

    /// The most urgent plan's answer, from Core.
    private var headline: UsageHeadline? {
        let plans = model.orgs.compactMap { org -> UsageHeadline.Plan? in
            guard let raw = model.latest[org.id], let state = model.state(for: org) else { return nil }
            return UsageHeadline.Plan(name: org.name, reading: raw.adjusted(to: model.now), forecast: model.forecast(for: org), state: state)
        }
        return UsageHeadline.make(plans, now: model.now, formatting: model.formatting, thresholds: model.settings.thresholds)
    }

    private func hero(_ p: TidePalette) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let headline {
                    Text(headline.title).font(.system(size: 32, weight: .light)).foregroundStyle(p.fg)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    if !headline.detail.isEmpty {
                        Text(headline.detail).font(Theme.font(14)).foregroundStyle(p.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    title("Usage", p)
                }
            }
            .frame(maxWidth: 540, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text(model.readAge(now: model.now)).font(Theme.font(12.5)).foregroundStyle(p.dim)
                UsageButton(title: "Refresh", action: actions.refresh)
            }
        }
        .padding(.top, 6)
        // The cards start below the moon and the waves, as the mockup's scene (330 pt from the top).
        .frame(minHeight: 290, alignment: .top)
    }

    // MARK: Banners

    /// A refresh problem (with Copy details when claude.ai changed how it answers), and the plan
    /// Claude Code is on when it isn't shown here.
    @ViewBuilder private var banners: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = model.problem {
                UsageBanner(showsShape: true, text: problem, button: details.map { _ in "Copy details" }) {
                    if let details {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(details, forType: .string)
                    }
                }
            }
            if model.advice == nil, !model.statusLine.isEmpty, hiddenCodePlan {
                UsageBanner(neutral: true, text: model.statusLine, button: nil) {}
            }
        }
    }

    /// What claude.ai answered when Tidemark couldn't read it, for the Copy details button.
    private var details: String? {
        let problems = [model.refreshProblem].compactMap { $0 } + model.orgProblems.values
        for case .changedShape(let text) in problems { return text }
        return nil
    }

    private var hiddenCodePlan: Bool {
        guard let id = model.claudeCodeOrg else { return false }
        return !model.orgs.contains { $0.id == id }
    }

    // MARK: Cards

    /// A glass card per plan, then Claude Code's.
    private func cards(_ s: UsageSummary) -> some View {
        let shown = Self.shownOrg(model, chosen: chosen.org)?.id
        let code = model.orgs.first { $0.id == model.claudeCodeOrg }
        return CardGrid(minWidth: 210, spacing: 12) {
            ForEach(model.orgs) { org in
                if let plan = s.plans.first(where: { $0.id == org.id }) {
                    UsagePlanCard(model: model, org: org, plan: plan, selected: org.id == shown) {
                        if chosen.org != org.id { chosen.org = org.id; chosen.kind = .week; chosen.lastWeek = false }
                    }
                }
            }
            if let code { UsageCodeCard(model: model, org: code) }
        }
    }

    @ViewBuilder private func modelToggle(_ s: UsageSummary, _ p: TidePalette) -> some View {
        if !s.modelNames.isEmpty {
            Button { settings.showModelRows.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: settings.showModelRows ? "checkmark.square.fill" : "square")
                        .foregroundStyle(settings.showModelRows ? p.fg : p.dim)
                    Text(s.modelToggle).foregroundStyle(p.dim)
                }
                .font(Theme.font(12.5))
            }
            .buttonStyle(.plain)
            .accessibilityValue(settings.showModelRows ? "on" : "off")
            .accessibilityAddTraits(.isToggle)
        }
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ s: UsageSummary) -> some View {
        if let org = Self.shownOrg(model, chosen: chosen.org) {
            UsageDetail(model: model, org: org, summary: s, chosen: chosen)
        }
    }
}

/// A big message in place of the page: plan limits off, or signed out.
struct UsageMessage: View {
    let title: String
    let detail: String
    let button: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(15, .semibold)).foregroundStyle(p.fg)
            Text(detail).font(Theme.font(12.5)).foregroundStyle(p.dim)
                .fixedSize(horizontal: false, vertical: true)
            UsageButton(title: button, action: action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
    }
}

/// One band of glass with an edge: the same look for every problem and note on the page.
struct UsageBanner: View {
    /// A plain note, not a problem: the edge is grey, not red.
    var neutral = false
    /// Draws the couldn't-read mark before the text.
    var showsShape = false
    let text: String
    let button: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = TidePalette.for(scheme)
        HStack(spacing: 8) {
            if showsShape { StateShape(nil, size: 10) }
            Text(text).foregroundStyle(p.fg).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let button {
                UsageButton(title: button, action: action)
            }
        }
        .font(Theme.font(12))
        .padding(.vertical, 7).padding(.horizontal, 12)
        .background(p.glass)
        .overlay(alignment: .leading) { Rectangle().fill(neutral ? p.track : p.redMark).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
