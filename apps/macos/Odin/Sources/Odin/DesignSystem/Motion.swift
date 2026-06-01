import SwiftUI

/// The four named animations used throughout Odin. Every `withAnimation`
/// and `.animation` call site should use one of these — no ad-hoc springs.
///
/// - `rise`:   elements entering the view hierarchy.
/// - `settle`: elements leaving the view hierarchy.
/// - `breathe`: ambient idle motion (eye pulse, status dot).
/// - `snap`:   tactile press / hover feedback.
enum OdinMotion {
    static let reduceMotionKey = "OdinReduceMotion"

    /// Whether ambient/breathing motion is suppressed for the current user.
    /// macOS does not expose a public "reduce motion" preference, so we
    /// expose a manual UserDefaults toggle (also settable from Settings).
    static var reduceMotion: Bool {
        get { UserDefaults.standard.bool(forKey: reduceMotionKey) }
        set { UserDefaults.standard.set(newValue, forKey: reduceMotionKey) }
    }

    struct Set {
        let rise:    Animation
        let settle:  Animation
        let breathe: Animation
        let snap:    Animation
    }

    static let standard = Set(
        rise:    .spring(response: 0.32, dampingFraction: 0.86),
        settle:  .easeOut(duration: 0.22),
        breathe: .easeInOut(duration: 1.6),
        snap:    .spring(response: 0.12, dampingFraction: 0.78)
    )

    static let reduced = Set(
        rise:    .spring(response: 0.16, dampingFraction: 0.92),
        settle:  .easeOut(duration: 0.10),
        breathe: .linear(duration: 0.0),
        snap:    .spring(response: 0.06, dampingFraction: 0.86)
    )

    /// The active set chosen for the current accessibility setting.
    static var current: Set { reduceMotion ? reduced : standard }
}
