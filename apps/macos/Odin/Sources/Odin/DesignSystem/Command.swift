import SwiftUI

/// The Command bar — the input field plus the controls that wrap it.
/// Sits at the bottom of the panel, above the Library strip. Animates
/// in focus and shows a keyboard hint when the input is empty.
struct CommandBar: View {
    @Binding var text: String
    var suggestedModels: [AppSettings.ModelSuggestion]
    var selectedModelID: String
    var costLabel: String?
    var isRunning: Bool
    var canSubmit: Bool
    var onSubmit: () -> Void
    var onStop: () -> Void
    @Binding var isModelPickerPresented: Bool
    var onSelectModel: (String) -> Void

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

    private var modelChipLabel: String {
        if let match = suggestedModels.first(where: { $0.modelID == selectedModelID }) {
            return match.alias
        }
        let trimmed = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Choose model"
    }

    @ViewBuilder
    private var modelChip: some View {
        if suggestedModels.isEmpty {
            ModelChip(label: modelChipLabel, showsChevron: false)
        } else {
            ModelChip(label: modelChipLabel, action: { isModelPickerPresented.toggle() })
                .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
                    ModelPickerPopover(
                        models: suggestedModels,
                        selectedID: selectedModelID,
                        onSelect: { id in
                            onSelectModel(id)
                            isModelPickerPresented = false
                        }
                    )
                }
        }
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

/// The dropdown content for the model chip. One row per suggested model,
/// the selected one marked with an amber check, all rendered in the
/// shared Odin surface so the popover feels like part of the panel.
private struct ModelPickerPopover: View {
    let models: [AppSettings.ModelSuggestion]
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(models) { model in
                ModelPickerRow(
                    model: model,
                    isSelected: model.modelID == selectedID,
                    onTap: { onSelect(model.modelID) }
                )
            }
        }
        .padding(.vertical, OdinTokens.Space.s6)
        .frame(width: 280)
        .background(OdinTokens.Color.surface)
    }
}

private struct ModelPickerRow: View {
    let model: AppSettings.ModelSuggestion
    let isSelected: Bool
    let onTap: () -> Void

    @SwiftUI.State private var hovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OdinTokens.Space.s10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.alias)
                        .font(OdinTokens.Font.bodyEm)
                        .foregroundStyle(isSelected ? OdinTokens.Color.ink : OdinTokens.Color.ink2)
                    Text(model.modelID)
                        .font(OdinTokens.Font.mono)
                        .foregroundStyle(OdinTokens.Color.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(OdinTokens.Color.amber)
                }
            }
            .padding(.horizontal, OdinTokens.Space.s12)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? OdinTokens.Color.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(OdinMotion.current.snap, value: hovering)
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
