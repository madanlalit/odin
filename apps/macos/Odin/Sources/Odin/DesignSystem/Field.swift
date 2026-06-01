import SwiftUI
import AppKit

/// A custom text field that matches the Odin glass aesthetic. Replaces
/// SwiftUI's `.roundedBorder` everywhere in the app. The `OdinField` is
/// one of the most-used atoms — keep it dependency-free.
struct OdinField: View {
    var placeholder: String = ""
    @Binding var text: String
    var secure: Bool = false
    var mono: Bool = false
    var trailingIcon: String? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var hovering: Bool = false

    var body: some View {
        HStack(spacing: OdinTokens.Space.s8) {
            fieldContent
            if let icon = trailingIcon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OdinTokens.Color.ink3)
            }
        }
        .padding(.horizontal, OdinTokens.Space.s12)
        .frame(height: OdinTokens.Size.buttonHeight)
        .background(
            RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                .fill(OdinTokens.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                .stroke(
                    focused ? OdinTokens.Color.amberLine : OdinTokens.Color.hairline,
                    lineWidth: focused ? 1.0 : 0.5
                )
        )
        .animation(OdinMotion.current.snap, value: focused)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var fieldContent: some View {
        if secure {
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(mono ? OdinTokens.Font.mono : OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink)
                .tint(OdinTokens.Color.amber)
                .focused($focused)
                .onSubmit { onSubmit?() }
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(mono ? OdinTokens.Font.mono : OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink)
                .tint(OdinTokens.Color.amber)
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
    }
}

/// A multi-line variant of `OdinField` used in the custom-env editor.
struct OdinTextArea: View {
    var placeholder: String = ""
    @Binding var text: String
    var mono: Bool = true
    var minHeight: CGFloat = 80

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(mono ? OdinTokens.Font.mono : OdinTokens.Font.body)
                    .foregroundStyle(OdinTokens.Color.ink3)
                    .padding(.horizontal, OdinTokens.Space.s12)
                    .padding(.top, OdinTokens.Space.s10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(mono ? OdinTokens.Font.mono : OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink)
                .tint(OdinTokens.Color.amber)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, OdinTokens.Space.s8)
                .padding(.vertical, OdinTokens.Space.s6)
                .focused($focused)
        }
        .frame(minHeight: minHeight)
        .background(
            RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                .fill(OdinTokens.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OdinTokens.R.chip, style: .continuous)
                .stroke(
                    focused ? OdinTokens.Color.amberLine : OdinTokens.Color.hairline,
                    lineWidth: focused ? 1.0 : 0.5
                )
        )
        .animation(OdinMotion.current.snap, value: focused)
    }
}

/// A segmented picker styled to match the rest of the form.
struct OdinSegmentedPicker<Selection: Hashable, Label: View>: View {
    @Binding var selection: Selection
    let options: [Selection]
    let label: (Selection) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    withAnimation(OdinMotion.current.snap) { selection = option }
                } label: {
                    label(option)
                        .font(OdinTokens.Font.bodyEm)
                        .foregroundStyle(selection == option
                                         ? OdinTokens.Color.ink
                                         : OdinTokens.Color.ink2)
                        .padding(.horizontal, OdinTokens.Space.s12)
                        .frame(height: 24)
                        .background(
                            Capsule()
                                .fill(selection == option
                                      ? OdinTokens.Color.surfaceRaised
                                      : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(OdinTokens.Color.surface)
        )
        .overlay(
            Capsule()
                .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
        )
    }
}

/// A toggle row that fits the form aesthetic.
struct OdinToggle: View {
    var label: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(label)
                .font(OdinTokens.Font.body)
                .foregroundStyle(OdinTokens.Color.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(OdinTokens.Color.amber)
                .controlSize(.small)
        }
    }
}

/// A label + value row used in Settings.
struct OdinRowLabel: View {
    let text: String
    var width: CGFloat = 132
    var body: some View {
        Text(text)
            .font(OdinTokens.Font.body)
            .foregroundStyle(OdinTokens.Color.ink2)
            .frame(width: width, alignment: .leading)
    }
}
