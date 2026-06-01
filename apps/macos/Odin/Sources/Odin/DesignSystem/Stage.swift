import SwiftUI

/// The top zone of the chat panel. Always visible. Its job is to answer
/// "what is Odin doing right now?" in a single calm glance.
struct StageHeader: View {
    enum State {
        case idle(suggestions: [String] = [])
        case working(phase: String, currentAction: String?, step: Int, maxSteps: Int, elapsed: String, cost: String?)
        case awaiting(approval: PendingActionApproval)
        case done(headline: String, detail: String?)
        case error(headline: String, detail: String?)

        var eyeState: OdinEye.State {
            switch self {
            case .idle:                       return .idle
            case .working:                    return .watching
            case .awaiting:                   return .awaiting
            case .done:                       return .done
            case .error:                      return .error
            }
        }
    }

    let state: State
    var onSuggestion: ((String) -> Void)? = nil
    var onAllow: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onExpand: (() -> Void)? = nil

    @SwiftUI.State private var expanded: Bool = false
    @SwiftUI.State private var showErrorPopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: OdinTokens.Space.s14) {
                EyeRuneMark(state: state.eyeState)
                VStack(alignment: .leading, spacing: 4) {
                    headline
                    subhead
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, OdinTokens.Space.s20)
            .padding(.vertical, OdinTokens.Space.s16)

            if case let .awaiting(approval) = state {
                Hairline()
                TakeoverDetails(approval: approval)
                    .padding(.horizontal, OdinTokens.Space.s20)
                    .padding(.top, OdinTokens.Space.s12)
                    .padding(.bottom, OdinTokens.Space.s16)
            }

            if case let .idle(suggestions) = state, !suggestions.isEmpty {
                Hairline()
                suggestionRow(suggestions)
                    .padding(.horizontal, OdinTokens.Space.s20)
                    .padding(.vertical, OdinTokens.Space.s12)
            }
        }
        .background(
            // Subtle progress fill when working.
            GeometryReader { geo in
                Rectangle()
                    .fill(OdinTokens.Color.amberWash)
                    .frame(width: geo.size.width * progressFraction, height: geo.size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var headline: some View {
        switch state {
        case .idle:
            // Quiet in idle. The eye alone communicates "ready".
            // The actual question lives in the Command bar placeholder
            // so it sits right where the user types.
            Text("Ready")
                .font(OdinTokens.Font.title)
                .foregroundStyle(OdinTokens.Color.ink)
        case .working(let phase, _, _, _, _, _):
            Text(phase)
                .font(OdinTokens.Font.title)
                .foregroundStyle(OdinTokens.Color.ink)
        case .awaiting:
            Text("Odin wants to \(verb.lowercased())")
                .font(OdinTokens.Font.title)
                .foregroundStyle(OdinTokens.Color.ink)
        case .done(let headline, _):
            Text(headline)
                .font(OdinTokens.Font.title)
                .foregroundStyle(OdinTokens.Color.ink)
        case .error(let headline, _):
            Text(headline)
                .font(OdinTokens.Font.title)
                .foregroundStyle(OdinTokens.Color.ink)
        }
    }

    @ViewBuilder
    private var subhead: some View {
        switch state {
        case .idle:
            // A short, warm line under "Ready" so the Stage has
            // context. Mirrors the Command bar placeholder so the
            // two zones feel like a pair.
            Text("Awaiting your command")
                .font(OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink3)
                .lineLimit(1)
        case .working(_, let currentAction, let step, let maxSteps, let elapsed, let cost):
            HStack(spacing: OdinTokens.Space.s8) {
                Text("Step \(step) of \(maxSteps) · \(elapsed)")
                    .font(OdinTokens.Font.mono)
                    .foregroundStyle(OdinTokens.Color.ink2)
                if let cost, !cost.isEmpty {
                    OdinChip(text: cost, style: .amber, mono: true, height: 18)
                }
            }
            if let currentAction, !currentAction.isEmpty {
                Text(currentAction)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink3)
                    .lineLimit(1)
            }
        case .awaiting(let approval):
            HStack(spacing: OdinTokens.Space.s8) {
                Text("Step \(approval.step) · \(approval.batchIndex) of \(approval.batchCount)")
                    .font(OdinTokens.Font.mono)
                    .foregroundStyle(OdinTokens.Color.ink2)
                if let target = approval.actionSubtitle {
                    Text("· \(target)")
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink2)
                }
            }
        case .done(_, let detail):
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .lineLimit(2)
            }
        case .error(_, let detail):
            if let detail, !detail.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail)
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.danger)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // The full refusal is often a paragraph. After
                    // 4 lines the Stage starts to crowd the Command
                    // bar, so the user can pop the rest out into a
                    // small scrollable sheet.
                    if detail.count > 200 {
                        Button {
                            showErrorPopover = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Show full message")
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(.odinText)
                        .popover(isPresented: $showErrorPopover, arrowEdge: .top) {
                            ScrollView {
                                Text(detail)
                                    .font(OdinTokens.Font.body)
                                    .foregroundStyle(OdinTokens.Color.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(OdinTokens.Space.s16)
                            }
                            .frame(width: 420, height: 280)
                            .background(OdinTokens.Color.surface)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working:
            // No action button here — the Command bar carries the stop.
            // The Stage's job is to show status, not to host controls.
            EmptyView()
        case .awaiting:
            // The Allow button stays here because it is the primary
            // focus during a takeover. The Command bar still has Stop.
            Button(action: { onAllow?() }) {
                Text("Allow")
                    .font(OdinTokens.Font.button)
            }
            .buttonStyle(.odinPrimary)
            .frame(width: 96)
            .keyboardShortcut(.return, modifiers: [])
        case .done, .error:
            EmptyView()
        }
    }

    private func suggestionRow(_ suggestions: [String]) -> some View {
        HStack(spacing: OdinTokens.Space.s6) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    onSuggestion?(suggestion)
                } label: {
                    Text(suggestion)
                        .font(OdinTokens.Font.caption)
                        .foregroundStyle(OdinTokens.Color.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, OdinTokens.Space.s10)
                        .frame(height: 24)
                        .background(
                            Capsule()
                                .fill(OdinTokens.Color.surfaceRaised)
                        )
                        .overlay(
                            Capsule()
                                .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var verb: String {
        if case let .awaiting(approval) = state {
            return approval.actionTitle
        }
        return ""
    }

    private var progressFraction: CGFloat {
        if case let .working(_, _, step, maxSteps, _, _) = state, maxSteps > 0 {
            let base = CGFloat(step) / CGFloat(maxSteps)
            return min(max(base, 0.04), 1.0)
        }
        return 0
    }
}

private struct TakeoverDetails: View {
    let approval: PendingActionApproval

    var body: some View {
        VStack(alignment: .leading, spacing: OdinTokens.Space.s8) {
            if let thought = approval.thought, !thought.isEmpty {
                Text(thought)
                    .font(OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink2)
                    .padding(OdinTokens.Space.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: OdinTokens.R.card)
                            .fill(OdinTokens.Color.surfaceRaised)
                    )
            }
            if !approval.detailChips.isEmpty {
                HStack(spacing: OdinTokens.Space.s6) {
                    ForEach(approval.detailChips, id: \.self) { chip in
                        OdinChip(text: chip, style: .neutral, mono: true, height: 20)
                    }
                }
            }
            HStack(spacing: OdinTokens.Space.s8) {
                Spacer()
                // Only Skip lives here. Stop is the Command bar's job,
                // so it lives in exactly one place everywhere in the panel.
                Button("Skip step", role: .cancel) {}
                    .buttonStyle(.odinText)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}
