import SwiftUI

/// A small chip used for keyboard shortcuts, model aliases, costs, and tags.
struct OdinChip: View {
    enum Style { case neutral, amber, success, danger }
    var text: String
    var style: Style = .neutral
    var leading: String? = nil
    var mono: Bool = false
    var height: CGFloat = OdinTokens.Size.chipHeight

    var body: some View {
        HStack(spacing: 5) {
            if leading != nil {
                Circle()
                    .fill(foreground)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(mono ? OdinTokens.Font.mono : OdinTokens.Font.caption)
                .foregroundStyle(foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, OdinTokens.Space.s10)
        .frame(height: height)
        .background(
            Capsule()
                .fill(backgroundFill)
        )
        .overlay(
            Capsule()
                .stroke(stroke, lineWidth: 0.5)
        )
    }

    private var foreground: Color {
        switch style {
        case .neutral: return OdinTokens.Color.ink2
        case .amber:   return OdinTokens.Color.amber
        case .success: return OdinTokens.Color.success
        case .danger:  return OdinTokens.Color.danger
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .neutral: return OdinTokens.Color.surfaceRaised
        case .amber:   return OdinTokens.Color.amberSoft
        case .success: return OdinTokens.Color.success.opacity(0.10)
        case .danger:  return OdinTokens.Color.danger.opacity(0.08)
        }
    }

    private var stroke: Color {
        switch style {
        case .neutral: return OdinTokens.Color.hairline
        case .amber:   return OdinTokens.Color.amberLine.opacity(0.6)
        case .success: return OdinTokens.Color.success.opacity(0.30)
        case .danger:  return OdinTokens.Color.danger.opacity(0.30)
        }
    }
}

/// A larger, tappable "library" card used for pinned tasks. Supports a
/// leading icon (the eye or a category symbol) and a trailing action.
struct OdinLibraryCard: View {
    var title: String
    var symbol: String? = nil
    var pinned: Bool = false
    var onTap: () -> Void
    var onPinToggle: (() -> Void)? = nil

    @SwiftUI.State private var hovering: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OdinTokens.Space.s8) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(OdinTokens.Color.ink3)
                        .frame(width: 14)
                }
                Text(title)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                    .lineLimit(1)
                if pinned, let onPinToggle {
                    Button(action: onPinToggle) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(OdinTokens.Color.amber)
                    }
                    .buttonStyle(.plain)
                    .help("Unpin")
                }
            }
            .padding(.horizontal, OdinTokens.Space.s12)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(hovering ? OdinTokens.Color.surfaceHover : OdinTokens.Color.surfaceRaised)
            )
            .overlay(
                Capsule()
                    .stroke(hovering ? OdinTokens.Color.amberLine : OdinTokens.Color.hairline,
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(OdinMotion.current.snap, value: hovering)
    }
}

/// A small dot indicator used in lists and status rows.
struct OdinDot: View {
    var color: Color = OdinTokens.Color.ink3
    var size: CGFloat = 6
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// A tappable, hover-aware row used in the status menu and popover lists.
struct OdinMenuRow: View {
    var label: String
    var symbol: String? = nil
    var trailing: String? = nil
    var role: ButtonRole? = nil
    var onTap: () -> Void

    @SwiftUI.State private var hovering: Bool = false

    var body: some View {
        Button(role: role, action: onTap) {
            HStack(spacing: OdinTokens.Space.s10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OdinTokens.Color.ink2)
                        .frame(width: 16)
                }
                Text(label)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(OdinTokens.Font.caption)
                        .foregroundStyle(OdinTokens.Color.ink3)
                        .padding(.horizontal, OdinTokens.Space.s6)
                        .frame(height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OdinTokens.Color.surfaceRaised)
                        )
                }
            }
            .padding(.horizontal, OdinTokens.Space.s10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? OdinTokens.Color.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(OdinMotion.current.snap, value: hovering)
    }
}
