import SwiftUI
import AppKit

/// The Odin design system foundation.
///
/// Every color, type, spacing, and radius value used by the app routes
/// through these tokens. Nothing in feature code should reference raw
/// hex values, `.primary.opacity(0.X)`, or hard-coded font sizes.
enum OdinTokens {

    // MARK: - Color

    enum Color {
        /// Adaptive amber accent — the only chromatic color in the system.
        /// Reads as warm Norse gold in dark mode, slightly lighter in light.
        static let amber = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(calibratedRed: isDark ? 0.941 : 0.910,
                           green:      isDark ? 0.706 : 0.640,
                           blue:       isDark ? 0.322 : 0.239,
                           alpha: 1.0)
        })

        /// Brighter amber for use on dark accents and the brand halo.
        static let amberBright = SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(calibratedRed: isDark ? 0.965 : 0.949,
                           green:      isDark ? 0.769 : 0.722,
                           blue:       isDark ? 0.404 : 0.337,
                           alpha: 1.0)
        })

        /// Halo glow color for the eye and active surfaces.
        static let amberHalo = amber.opacity(0.22)
        static let amberLine = amber.opacity(0.40)
        static let amberSoft = amber.opacity(0.10)
        static let amberWash = amber.opacity(0.06)

        /// Ink scale — ramps from primary to ghost.
        static let ink  = SwiftUI.Color.primary
        static let ink2 = SwiftUI.Color.primary.opacity(0.66)
        static let ink3 = SwiftUI.Color.primary.opacity(0.40)
        static let ink4 = SwiftUI.Color.primary.opacity(0.20)
        static let ink5 = SwiftUI.Color.primary.opacity(0.10)

        /// Surfaces — glass-friendly monochrome fills.
        static let surface        = SwiftUI.Color.primary.opacity(0.035)
        static let surfaceRaised  = SwiftUI.Color.primary.opacity(0.055)
        static let surfaceHover   = SwiftUI.Color.primary.opacity(0.085)
        static let surfacePress   = SwiftUI.Color.primary.opacity(0.115)
        static let surfaceInverse = SwiftUI.Color.primary.opacity(0.92)

        /// Hairline / divider — single source of truth for separators.
        static let hairline = SwiftUI.Color.primary.opacity(0.075)

        /// Semantic status — green for success, red for danger.
        /// Amber is reserved for the brand / active accent; it is NOT a status color.
        static let success = SwiftUI.Color(red: 0.20, green: 0.82, blue: 0.38)
        static let danger  = SwiftUI.Color(red: 1.00, green: 0.30, blue: 0.27)
        static let warning = amberBright
    }

    // MARK: - Typography

    /// Seven canonical sizes, four weights, two families. Use these instead
    /// of raw `Font.system(size:weight:)` calls. No 12.5, no 10.5, no 13.5.
    enum Font {
        /// 10pt small-caps, used for eyebrow labels and section tags.
        static let micro: SwiftUI.Font = .system(size: 10, weight: .semibold, design: .default)
            .smallCaps()

        /// 11pt medium — captions, chips, metadata.
        static let caption: SwiftUI.Font = .system(size: 11, weight: .medium)

        /// 11pt regular monospaced — IDs, paths, cost, code.
        static let mono: SwiftUI.Font = .system(size: 11, weight: .regular, design: .monospaced)

        /// 13pt regular — body text in the panel.
        static let body: SwiftUI.Font = .system(size: 13, weight: .regular)

        /// 13pt medium — emphasized body, list rows.
        static let bodyEm: SwiftUI.Font = .system(size: 13, weight: .medium)

        /// 15pt semibold — section titles, takeover headline.
        static let title: SwiftUI.Font = .system(size: 15, weight: .semibold)

        /// 17pt semibold — primary CTA labels.
        static let button: SwiftUI.Font = .system(size: 13, weight: .semibold)

        /// 22pt semibold — hero idle headline, settings title.
        static let hero: SwiftUI.Font = .system(size: 22, weight: .semibold)

        /// 28pt bold — onboarding hero.
        static let display: SwiftUI.Font = .system(size: 28, weight: .bold)
    }

    // MARK: - Spacing

    /// 4pt grid. Use these constants instead of magic numbers.
    enum Space {
        static let s2:  CGFloat = 2
        static let s4:  CGFloat = 4
        static let s6:  CGFloat = 6
        static let s8:  CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        static let s48: CGFloat = 48
    }

    // MARK: - Radius

    enum R {
        static let chip:   CGFloat = 8
        static let card:   CGFloat = 12
        static let input:  CGFloat = 18
        static let panel:  CGFloat = 22
        static let window: CGFloat = 16
    }

    // MARK: - Sizing

    enum Size {
        static let panelWidth:         CGFloat = 560
        static let panelMinHeight:     CGFloat = 200
        static let stageMinHeight:     CGFloat = 56
        static let commandHeight:      CGFloat = 56
        static let libraryHeight:      CGFloat = 48
        static let whisperLineHeight:  CGFloat = 22
        static let whisperMaxLines:    Int    = 5
        static let chipHeight:         CGFloat = 24
        static let buttonHeight:       CGFloat = 32
        static let buttonHeightLarge:  CGFloat = 44
        static let circleButton:       CGFloat = 28
    }
}
