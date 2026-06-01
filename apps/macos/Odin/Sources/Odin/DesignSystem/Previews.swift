import SwiftUI

#if DEBUG
/// SwiftUI previews for the new design system. Open in Xcode and the
/// canvas will show each surface in its canonical state.
@available(macOS 26.0, *)
struct DesignSystemPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            // The Eye, in all five states
            EyeStateGallery()
                .padding(40)
                .background(Color.black)
                .previewDisplayName("OdinEye · All States")

            // The Stage in each major state
            StageGallery()
                .padding(20)
                .background(Color.black)
                .previewDisplayName("StageHeader · States")

            // A composite panel mockup
            PanelMockup(state: .idle)
                .padding(40)
                .background(Color.black)
                .previewDisplayName("Chat Panel · Idle")

            PanelMockup(state: .working)
                .padding(40)
                .background(Color.black)
                .previewDisplayName("Chat Panel · Working")

            PanelMockup(state: .awaiting)
                .padding(40)
                .background(Color.black)
                .previewDisplayName("Chat Panel · Awaiting")
        }
        .preferredColorScheme(.dark)
    }
}

private struct EyeStateGallery: View {
    var body: some View {
        HStack(spacing: 32) {
            stateBox("idle",     .idle)
            stateBox("watching", .watching)
            stateBox("awaiting", .awaiting)
            stateBox("done",     .done)
            stateBox("error",    .error)
        }
    }
    private func stateBox(_ label: String, _ state: OdinEye.State) -> some View {
        VStack(spacing: 8) {
            OdinEye(state: state, size: 40)
            Text(label)
                .font(OdinTokens.Font.caption)
                .foregroundStyle(OdinTokens.Color.ink3)
        }
    }
}

private struct StageGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StageHeader(state: .idle())
                .odinPanelSurface()
                .frame(width: 560)
            StageHeader(state: .working(
                phase: "Working on it",
                currentAction: "Click \"Submit\" on the search form",
                step: 4, maxSteps: 100, elapsed: "12s", cost: "$0.043"
            ))
            .odinPanelSurface()
            .frame(width: 560)
            StageHeader(state: .awaiting(approval: .preview))
                .odinPanelSurface()
                .frame(width: 560)
            StageHeader(state: .done(headline: "Done", detail: "Sent the email and copied you on the reply."))
                .odinPanelSurface()
                .frame(width: 560)
        }
    }
}

private struct PanelMockup: View {
    enum MockState { case idle, working, awaiting }
    let state: MockState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
            Hairline()
            CommandBar(
                text: .constant(""),
                modelLabel: "MiniMax M3",
                costLabel: state == .working ? "$0.043" : nil,
                isRunning: state != .idle,
                canSubmit: false,
                onSubmit: {},
                onStop: {},
                onPickModel: {}
            )
            Hairline()
            LibraryStrip(
                pinned: ["Plan my week", "Summarize this tab"],
                recents: ["Find todos in Mail", "Open settings"],
                onSelect: { _ in },
                onPinToggle: { _ in }
            )
        }
        .frame(width: OdinTokens.Size.panelWidth)
        .odinPanelSurface(
            isAccented: state != .idle
        )
    }

    @ViewBuilder
    private var stage: some View {
        switch state {
        case .idle:
            StageHeader(state: .idle(suggestions: ["Plan my week", "Summarize this tab", "Find todos in Mail"]))
        case .working:
            StageHeader(state: .working(
                phase: "Working on it",
                currentAction: "Click the search field",
                step: 4, maxSteps: 100, elapsed: "12s", cost: "$0.043"
            ))
        case .awaiting:
            StageHeader(state: .awaiting(approval: .preview))
        }
    }
}

private extension PendingActionApproval {
    static var preview: PendingActionApproval {
        PendingActionApproval(
            id: "preview",
            step: 2,
            batchIndex: 1,
            batchCount: 3,
            thought: "I'll click the search field first, then type the query. Safer than coordinate-click since the layout just changed.",
            action: "click",
            actionTitle: "Click the search field",
            actionSubtitle: "Safari",
            detailChips: ["role: AXButton", "frame: 412,84"],
            focusOwnerProcessIdentifier: nil
        )
    }
}
#endif
