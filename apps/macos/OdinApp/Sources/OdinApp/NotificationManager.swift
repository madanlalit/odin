import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter?
    private var ready = false

    private override init() {
        super.init()
    }

    func requestPermission() {
        guard let c = tryCenter() else { return }
        center = c
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.ready = granted
        }
    }

    func notifyTaskCompleted(success: Bool, message: String?) {
        guard let c = center, ready else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? "Task completed" : "Task stopped"
        content.body = message ?? (success ? "The agent finished successfully." : "The agent was stopped.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        c.add(request)
    }

    func notifyError(detail: String?) {
        guard let c = center, ready else { return }
        let content = UNMutableNotificationContent()
        content.title = "Agent error"
        content.body = detail ?? "An unexpected error occurred."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        c.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }


    private func tryCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
}
