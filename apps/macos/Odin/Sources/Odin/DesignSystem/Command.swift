import SwiftUI

/// The Command bar — the input field plus the controls that wrap it.
/// Sits at the bottom of the panel, above the Library strip. Animates
/// in focus and shows a keyboard hint when the input is empty.
struct CommandBar: View {
    @Binding var text: String
    var modelLabel: String
    var costLabel: String?
    var isRunning: Bool
    var canSubmit: Bool
    var onSubmit: () -> Void
    var onStop: () -> Void
    var onPickModel: () -> Void

    @FocusState private var focused: Bool
    @SwiftUI.State private var cursorVisible: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: OdinTokens.Space.s12) {
            input
            Spacer(minLength: 0)
            modelChip
            if let costLabel, !costLabel.isEmpty {
                OdinChip(text: costLabel, style: .neutral, mono: true, height: 24)
            }
            sendButton
        }
        .padding(.horizontal, OdinTokens.Space.s20)
        .frame(height: OdinTokens.Size.commandHeight)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .odinFocusCommand)) { _ in
            focused = true
        }
    }

    @ViewBuilder
    private var input: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                HStack(spacing: 6) {
                    if !focused {
                        BlinkingCursor()
                    }
                    Text(placeholder)
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink3)
                    Spacer(minLength: 0)
                    if !focused {
                        Text("↵")
                            .font(OdinTokens.Font.mono)
                            .foregroundStyle(OdinTokens.Color.ink4)
                    }
                }
                .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink)
                .tint(OdinTokens.Color.amber)
                .focused($focused)
                .lineLimit(1...4)
                .onSubmit { if canSubmit { onSubmit() } }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var placeholder: String {
        isRunning
            ? "Type to add a hint for the next step…"
            : "What should Odin do?"
    }

    private var modelChip: some View {
        ModelChip(label: modelLabel, action: onPickModel)
    }

    @ViewBuilder
    private var sendButton: some View {
        if isRunning {
            // Amber — same color as the running eye, same color as the
            // send button. Red is reserved for actual errors / destructive
            // confirmations, not for the routine stop action.
            Button(action: onStop) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.odinIconAmber)
            .help("Stop run (⌘.)")
        } else {
            Button(action: onSubmit) {
                Image(systemName: canSubmit ? "arrow.up" : "return")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.odinIconAmber)
            .disabled(!canSubmit)
            .help(canSubmit ? "Run (return)" : "Type a task to run")
        }
    }
}

private struct BlinkingCursor: View {
    @SwiftUI.State private var visible: Bool = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(OdinTokens.Color.amber)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(OdinMotion.current.breathe.repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
