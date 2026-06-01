import Foundation

/// Notification names that the design system uses to communicate with
/// the rest of the app. Centralized so both producers and consumers
/// stay in sync.
extension Notification.Name {
    /// Posted by the chat panel to request that the Command input grab focus.
    /// Handled by `CommandBar` in its own view body.
    static let odinFocusCommand = Notification.Name("OdinFocusCommand")
}
