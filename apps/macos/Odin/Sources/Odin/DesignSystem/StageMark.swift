import SwiftUI
import CoreText

/// Registers the bundled Starlight Rune font the first time any mark is
/// rendered. Idempotent — safe to call from many views.
///
/// Note: Starlight Rune is freeware for personal, non-commercial use.
/// A commercial license must be obtained before shipping a paid build.
enum OdinRuneFont {
    static let name = "StarlightRune"
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        guard let url = Bundle.module.url(forResource: "StarlightRune", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(size: CGFloat) -> Font {
        registerIfNeeded()
        return .custom(name, size: size, relativeTo: .title)
    }
}

/// The Odin mark. A narrower, taller almond than a generic eye shape,
/// with a Starlight Rune "O" optically centered as the iris. Used in
/// the Stage header and the menu bar; sizes gracefully down to ~16pt
/// by scaling the stroke and fill.
///
/// Color-shifts with the agent's state: amber when watching,
/// amberBright when awaiting, success on done, danger on error.
struct EyeRuneMark: View {
    let state: OdinEye.State
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RuneEyeShape()
                .fill(irisColor.opacity(fillOpacity))
                .overlay(
                    RuneEyeShape()
                        .stroke(irisColor.opacity(0.95), lineWidth: strokeWidth)
                )
                .frame(width: size, height: size * 0.82)

            // Rune as the iris. .position() guarantees geometric
            // centering; the +0.04 nudge compensates for the empty
            // descender of the "O" glyph so it reads optically centered.
            Text("O")
                .font(OdinRuneFont.font(size: size * 0.62))
                .foregroundStyle(irisColor)
                .position(x: size / 2, y: size * 0.82 / 2 + size * 0.04)
        }
        .frame(width: size, height: size * 0.82)
    }

    // Stroke and fill scale with size so the eye stays legible
    // down to menu-bar dimensions (16–20pt), where a fixed 0.9pt
    // stroke and 0.14 fill would otherwise fade to near-invisible.
    private var strokeWidth: CGFloat { max(1.2, size * 0.075) }
    private var fillOpacity: Double {
        // Stronger at small sizes (where the outline is fighting
        // the pixel grid), softer at large sizes (where the eye
        // already reads cleanly from the stroke alone).
        size < 24 ? 0.28 : 0.16
    }

    private var irisColor: Color {
        switch state {
        case .idle:     return OdinTokens.Color.amber
        case .watching: return OdinTokens.Color.amber
        case .awaiting: return OdinTokens.Color.amberBright
        case .done:     return OdinTokens.Color.success
        case .error:    return OdinTokens.Color.danger
        }
    }
}

/// A narrower, taller almond tuned for the rune mark. Wider in the
/// middle, gentler curves than the generic `EyeShape` so the rune "O"
/// has room to breathe without being distorted by sharp corners.
struct RuneEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.5))
        p.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control: CGPoint(x: w * 0.5, y: -h * 0.06)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h * 0.5),
            control: CGPoint(x: w * 0.5, y: h * 1.06)
        )
        p.closeSubpath()
        return p
    }
}
