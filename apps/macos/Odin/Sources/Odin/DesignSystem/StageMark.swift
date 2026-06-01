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

/// The Stage mark — the visual that lives in the top-left of the panel
/// where the eye used to be. Four variants are provided so we can compare
/// them. The chosen one will replace `OdinEye` in `StageHeader`.
enum StageMarkVariant: String, CaseIterable, Identifiable {
    case wordmark   // "ODIN" full wordmark
    case monogram   // Single "O" rune
    case eyeRune    // Almond shape with a rune as the iris
    case lockup     // Wordmark + "Ready" stacked

    var id: String { rawValue }
    var label: String {
        switch self {
        case .wordmark: return "A · Wordmark"
        case .monogram: return "B · Monogram"
        case .eyeRune:  return "C · Eye + Rune"
        case .lockup:   return "D · Lockup"
        }
    }
}

/// A unified mark component. Renders one of the four variants and
/// respects the agent's current state by color-shifting.
struct StageMark: View {
    let variant: StageMarkVariant
    let state: OdinEye.State

    var body: some View {
        switch variant {
        case .wordmark:  WordmarkMark(state: state)
        case .monogram:  MonogramMark(state: state)
        case .eyeRune:   EyeRuneMark(state: state)
        case .lockup:    LockupMark(state: state)
        }
    }
}

// MARK: - Variant A — Wordmark

private struct WordmarkMark: View {
    let state: OdinEye.State

    var body: some View {
        Text("ODIN")
            .font(OdinRuneFont.font(size: 32))
            .foregroundStyle(irisColor)
            .tracking(2)
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

// MARK: - Variant B — Monogram

private struct MonogramMark: View {
    let state: OdinEye.State

    var body: some View {
        Text("O")
            .font(OdinRuneFont.font(size: 40))
            .foregroundStyle(irisColor)
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

// MARK: - Variant C — Almond eye with rune iris

/// The chosen mark. A narrower, taller almond than the generic
/// `EyeShape`, with a Starlight Rune "O" optically centered as the iris.
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

// MARK: - Variant D — Vertical lockup

private struct LockupMark: View {
    let state: OdinEye.State

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ODIN")
                .font(OdinRuneFont.font(size: 22))
                .foregroundStyle(irisColor)
                .tracking(3)
            Text("RUNE")
                .font(OdinTokens.Font.micro)
                .foregroundStyle(OdinTokens.Color.ink3)
                .tracking(4)
        }
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

// MARK: - Gallery

/// Side-by-side gallery of all four mark variants, rendered at idle.
/// Drop this in `Previews.swift` for visual comparison.
struct StageMarkGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OdinTokens.Space.s20) {
            HStack {
                Text("Stage mark — iteration")
                    .font(OdinTokens.Font.title)
                    .foregroundStyle(OdinTokens.Color.ink)
                Spacer()
                Text("Run with --mark-gallery")
                    .font(OdinTokens.Font.micro)
                    .foregroundStyle(OdinTokens.Color.ink3)
            }

            VStack(alignment: .leading, spacing: OdinTokens.Space.s12) {
                ForEach(StageMarkVariant.allCases) { variant in
                    galleryRow(variant: variant)
                }
            }
        }
        .padding(OdinTokens.Space.s24)
        .frame(width: 640)
        .background(Color(white: 0.98))  // light bg so the dark ink labels are readable
    }

    private func galleryRow(variant: StageMarkVariant) -> some View {
        HStack(alignment: .center, spacing: OdinTokens.Space.s20) {
            // The mark itself, sitting in a fixed-width slot. Each row
            // shows the mark rendered at the same height as it would
            // appear in the actual Stage header, so the comparison is
            // honest.
            StageMark(variant: variant, state: .idle)
                .frame(width: 160, height: 56, alignment: .leading)

            // The label and a one-line description
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.label)
                    .font(OdinTokens.Font.bodyEm)
                    .foregroundStyle(OdinTokens.Color.ink)
                Text(description(for: variant))
                    .font(OdinTokens.Font.caption)
                    .foregroundStyle(Color(white: 0.40))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OdinTokens.Space.s16)
        .padding(.vertical, OdinTokens.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: OdinTokens.R.card)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: OdinTokens.R.card)
                        .stroke(Color(white: 0.88), lineWidth: 0.5)
                )
        )
    }

    private func description(for variant: StageMarkVariant) -> String {
        switch variant {
        case .wordmark:  return "Full wordmark, 32pt rune"
        case .monogram:  return "Single rune glyph, 40pt"
        case .eyeRune:   return "Almond eye with rune iris"
        case .lockup:    return "Stacked wordmark + tag"
        }
    }
}

/// The chosen mark rendered in the actual Stage header context. Used
/// after the variant is picked, to see how it sits next to "Ready",
/// suggestions, and the rest of the panel chrome.
struct StageMarkInContext: View {
    let variant: StageMarkVariant
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: OdinTokens.Space.s14) {
                StageMark(variant: variant, state: .idle)
                    .frame(width: 44, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready")
                        .font(OdinTokens.Font.title)
                        .foregroundStyle(OdinTokens.Color.ink)
                    Text("Awaiting your command")
                        .font(OdinTokens.Font.body)
                        .foregroundStyle(OdinTokens.Color.ink3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OdinTokens.Space.s20)
            .padding(.vertical, OdinTokens.Space.s16)

            Hairline()
            HStack(spacing: OdinTokens.Space.s6) {
                suggestionPill("Plan my week")
                suggestionPill("Summarize this tab")
                suggestionPill("Find todos in Mail")
                Spacer()
            }
            .padding(.horizontal, OdinTokens.Space.s20)
            .padding(.vertical, OdinTokens.Space.s12)
        }
        .frame(width: OdinTokens.Size.panelWidth)
        .background(Color(white: 0.98))
    }

    private func suggestionPill(_ text: String) -> some View {
        Text(text)
            .font(OdinTokens.Font.caption)
            .foregroundStyle(Color(white: 0.35))
            .lineLimit(1)
            .padding(.horizontal, OdinTokens.Space.s10)
            .frame(height: 24)
            .background(
                Capsule().fill(Color(white: 0.92))
            )
    }
}
