import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let category = "SOUNDGUARD_ALARM"
    private let center = UNUserNotificationCenter.current()
    private var enabled = true

    override init() {
        super.init()
        // Set before the first lock-screen tap. A missing delegate drops the
        // response that should bring the alarm page forward.
        center.delegate = self
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { cancelAll() }
    }

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let ack = UNNotificationAction(identifier: "ACK", title: "Open SoundGuard", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.category, actions: [ack], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func startRepeating(snapshot: AlarmSnapshot) {
        cancelAll()
        guard enabled else { return }
        for index in 0..<12 {
            let content = UNMutableNotificationContent()
            content.title = "SOUNDGUARD ALARM"
            content.body = "\(snapshot.soundName) detected. Unlock and open SoundGuard to acknowledge. The alarm stays on until you do."
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["eventId": snapshot.id.uuidString]
            let delay = max(0.05, Double(index) * 30)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: "sg-alarm-\(snapshot.id.uuidString)-\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
