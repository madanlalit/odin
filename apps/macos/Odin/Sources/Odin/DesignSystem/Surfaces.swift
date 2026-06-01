import SwiftUI
import AppKit

/// The single liquid-glass surface that hosts the chat panel. One rounded
/// rectangle, one hairline stroke, one material fill. Internal sections are
/// separated by `Hairline` dividers, not by their own rounded cards.
struct OdinPanelSurface: ViewModifier {
    var radius: CGFloat = OdinTokens.R.panel
    var isAccented: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OdinTokens.Color.surface)
            )
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        isAccented
                            ? OdinTokens.Color.amberLine
                            : OdinTokens.Color.hairline,
                        lineWidth: 0.75
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A 0.5pt hairline divider used between sections in the panel.
struct Hairline: View {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
    var color: Color = OdinTokens.Color.hairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
    }
}

/// A subtle raised card used inside the onboarding, settings, and
/// approval regions. Slightly larger radius than a chip; sits inside
/// the panel rather than acting as the panel.
struct OdinCard: ViewModifier {
    var radius: CGFloat = OdinTokens.R.card
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OdinTokens.Color.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(OdinTokens.Color.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// Wrap a view in the single liquid-glass panel surface.
    func odinPanelSurface(
        radius: CGFloat = OdinTokens.R.panel,
        isAccented: Bool = false
    ) -> some View {
        modifier(OdinPanelSurface(radius: radius, isAccented: isAccented))
    }

    /// Wrap a view in a raised, hairline-bordered card.
    func odinCard(radius: CGFloat = OdinTokens.R.card) -> some View {
        modifier(OdinCard(radius: radius))
    }
}
