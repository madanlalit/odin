import SwiftUI

// MARK: - Primary Button (amber)

/// The single primary action. Amber pill, dark text. Used once per surface.
struct OdinPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = OdinTokens.Size.buttonHeightLarge
    var fullWidth: Bool = true
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let textColor: Color = OdinTokens.Color.surfaceInverse
        let fill = OdinTokens.Color.amber
        return configuration.label
            .font(OdinTokens.Font.button)
            .foregroundStyle(textColor)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .stroke(OdinTokens.Color.amber.opacity(0.4), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(OdinMotion.current.snap, value: configuration.isPressed)
    }
}

// MARK: - Soft Button (neutral)

/// Secondary, non-destructive action. Quiet text on a raised surface.
struct OdinSoftButtonStyle: ButtonStyle {
    var height: CGFloat = OdinTokens.Size.buttonHeight
    var fullWidth: Bool = false
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OdinTokens.Font.bodyEm)
            .foregroundStyle(OdinTokens.Color.ink)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, compact ? OdinTokens.Space.s12 : OdinTokens.Space.s16)
            .background(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(OdinTokens.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(OdinMotion.current.snap, value: configuration.isPressed)
    }
}

// MARK: - Destructive Button

/// "Stop run" / "Quit" / "Remove". Red text on a subtle red-tinted surface.
struct OdinDestructiveButtonStyle: ButtonStyle {
    var height: CGFloat = OdinTokens.Size.buttonHeight
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OdinTokens.Font.bodyEm)
            .foregroundStyle(OdinTokens.Color.danger)
            .frame(height: height)
            .padding(.horizontal, OdinTokens.Space.s16)
            .background(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(OdinTokens.Color.danger.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .stroke(OdinTokens.Color.danger.opacity(0.22), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(OdinMotion.current.snap, value: configuration.isPressed)
    }
}

// MARK: - Text Button (quietest)

/// "Skip", "Cancel", "Reveal". No background. Hover lifts to secondaryInk.
struct OdinTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OdinTokens.Font.bodyEm)
            .foregroundStyle(configuration.isPressed ? OdinTokens.Color.ink : OdinTokens.Color.ink2)
            .padding(.horizontal, OdinTokens.Space.s10)
            .frame(height: OdinTokens.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: OdinTokens.Size.buttonHeight / 2, style: .continuous)
                    .fill(configuration.isPressed ? OdinTokens.Color.surfaceHover : .clear)
            )
            .animation(OdinMotion.current.snap, value: configuration.isPressed)
    }
}

// MARK: - Icon Circle Button

/// The 28pt circle used in the Command bar (send / stop) and elsewhere.
struct OdinIconCircleButtonStyle: ButtonStyle {
    enum Variant { case neutral, amber, danger }
    var variant: Variant = .neutral
    var size: CGFloat = OdinTokens.Size.circleButton

    func makeBody(configuration: Configuration) -> some View {
        let (fg, bg, stroke) = colors(configuration: configuration)
        return configuration.label
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(bg)
            )
            .overlay(
                Circle()
                    .stroke(stroke, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(OdinMotion.current.snap, value: configuration.isPressed)
    }

    private func colors(configuration: Configuration) -> (Color, Color, Color) {
        let active = configuration.isPressed
        switch variant {
        case .neutral:
            return (OdinTokens.Color.ink,
                    active ? OdinTokens.Color.surfacePress : OdinTokens.Color.surfaceRaised,
                    OdinTokens.Color.hairline)
        case .amber:
            return (OdinTokens.Color.surfaceInverse,
                    OdinTokens.Color.amber,
                    OdinTokens.Color.amberLine)
        case .danger:
            return (OdinTokens.Color.danger,
                    active ? OdinTokens.Color.danger.opacity(0.10) : OdinTokens.Color.danger.opacity(0.05),
                    OdinTokens.Color.danger.opacity(0.25))
        }
    }
}

// MARK: - Static helpers

extension ButtonStyle where Self == OdinPrimaryButtonStyle {
    static var odinPrimary: OdinPrimaryButtonStyle { .init() }
    static func odinPrimary(compact: Bool) -> OdinPrimaryButtonStyle { .init(compact: compact) }
}

extension ButtonStyle where Self == OdinSoftButtonStyle {
    static var odinSoft: OdinSoftButtonStyle { .init() }
}

extension ButtonStyle where Self == OdinDestructiveButtonStyle {
    static var odinDestructive: OdinDestructiveButtonStyle { .init() }
}

extension ButtonStyle where Self == OdinTextButtonStyle {
    static var odinText: OdinTextButtonStyle { .init() }
}

extension ButtonStyle where Self == OdinIconCircleButtonStyle {
    static var odinIconNeutral: OdinIconCircleButtonStyle { .init(variant: .neutral) }
    static var odinIconAmber: OdinIconCircleButtonStyle   { .init(variant: .amber) }
    static var odinIconDanger: OdinIconCircleButtonStyle  { .init(variant: .danger) }
}
