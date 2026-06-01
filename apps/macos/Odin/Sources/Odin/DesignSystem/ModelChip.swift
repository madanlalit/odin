import SwiftUI

/// The model pill used in both the chat Command bar and the status
/// menu popover. An amber status dot, the model name, a chevron, and
/// a soft chip-style surface — matches the rest of the design system.
struct ModelChip: View {
    var label: String
    var action: (() -> Void)? = nil
    var showsChevron: Bool = true

    var body: some View {
        let content = HStack(spacing: 6) {
            Circle()
                .fill(OdinTokens.Color.amber)
                .frame(width: 5, height: 5)
            Text(label)
                .font(OdinTokens.Font.caption)
                .foregroundStyle(OdinTokens.Color.ink2)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(OdinTokens.Color.ink4)
            }
        }
        .padding(.horizontal, OdinTokens.Space.s10)
        .frame(height: 26)
        .background(
            Capsule()
                .fill(OdinTokens.Color.surfaceRaised)
        )
        .overlay(
            Capsule()
                .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
        )

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .help("Choose model")
        } else {
            content
        }
    }
}
