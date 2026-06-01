import SwiftUI

/// The Odin Eye — the product's functional mark.
///
/// A stylized, modern eye drawn entirely with vector paths. Renders cleanly
/// from 12pt to 96pt. The iris is amber when the agent is "watching" and
/// muted when idle. The surrounding halo breathes with `OdinMotion.breathe`
/// when active.
struct OdinEye: View {
    enum State {
        case idle
        case watching
        case awaiting
        case done
        case error

        var iris: Color {
            switch self {
            case .idle:     return OdinTokens.Color.ink3
            case .watching: return OdinTokens.Color.amber
            case .awaiting: return OdinTokens.Color.amberBright
            case .done:     return OdinTokens.Color.success
            case .error:    return OdinTokens.Color.danger
            }
        }

        var glow: Color {
            switch self {
            case .idle:     return .clear
            case .watching: return OdinTokens.Color.amberHalo
            case .awaiting: return OdinTokens.Color.amberBright.opacity(0.30)
            case .done:     return OdinTokens.Color.success.opacity(0.22)
            case .error:    return OdinTokens.Color.danger.opacity(0.22)
            }
        }
    }

    let state: State
    var size: CGFloat = 28
    var animated: Bool = true

    @SwiftUI.State private var pulse: CGFloat = 0
    @SwiftUI.State private var glowOpacity: Double = 0.0

    var body: some View {
        ZStack {
            if state != .idle {
                Circle()
                    .fill(state.glow)
                    .frame(width: size * 1.55, height: size * 1.55)
                    .blur(radius: size * 0.10)
                    .opacity(glowOpacity)
                    .scaleEffect(pulse == 0 ? 1.0 : 1.15)
            }

            EyeShape()
                .fill(OdinTokens.Color.surfaceRaised)
                .overlay(
                    EyeShape()
                        .stroke(state == .idle ? OdinTokens.Color.ink5 : state.iris.opacity(0.35), lineWidth: 0.75)
                )
                .frame(width: size, height: size * 0.62)

            Circle()
                .fill(state.iris)
                .frame(width: size * 0.30, height: size * 0.30)

            Circle()
                .fill(OdinTokens.Color.surfaceInverse)
                .frame(width: size * 0.11, height: size * 0.11)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Odin")
        .accessibilityValue(accessibilityValue)
        .onAppear { startAnimatingIfNeeded() }
        .onChange(of: state) { _, _ in startAnimatingIfNeeded() }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle:     return "Idle"
        case .watching: return "Working"
        case .awaiting: return "Awaiting approval"
        case .done:     return "Done"
        case .error:    return "Needs attention"
        }
    }

    private func startAnimatingIfNeeded() {
        guard animated else { return }
        switch state {
        case .idle:
            pulse = 0
            glowOpacity = 0
        case .watching, .awaiting:
            withAnimation(OdinMotion.current.breathe.repeatForever(autoreverses: true)) {
                pulse = 1
            }
            withAnimation(OdinMotion.current.breathe.repeatForever(autoreverses: true)) {
                glowOpacity = state == .awaiting ? 0.9 : 0.6
            }
        case .done, .error:
            pulse = 0
            withAnimation(OdinMotion.current.snap) {
                glowOpacity = 0.4
            }
        }
    }
}

/// Almond shape used as the eye outline. Slight curve asymmetry gives the
/// mark its character.
struct EyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.5))
        p.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control: CGPoint(x: w * 0.5, y: -h * 0.12)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.5),
            control: CGPoint(x: w * 0.5, y: h * 1.12)
        )
        p.closeSubpath()
        return p
    }
}
