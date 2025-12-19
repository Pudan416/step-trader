import Foundation
import UserNotifications

// MARK: - Notification Manager
final class NotificationManager: NotificationServiceProtocol {
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        
        if !granted {
            throw NotificationError.permissionDenied
        }
        
        print("📲 Notification permissions granted")
    }
    
    func sendTimeExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Steps Trader"
        content.body = "Time is up! Check whether you earned more time—walk additional steps to unlock."
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "timeExpired-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send time expired notification: \(error)")
            } else {
                print("📤 Sent time expired notification")
            }
        }
    }
    
    func sendTimeExpiredNotification(remainingMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Steps Trader"
        if remainingMinutes > 0 {
            content.body = "Time is up! You had \(remainingMinutes) min. Walk more steps to unlock."
        } else {
            content.body = "Time is up! Walk more steps to unlock."
        }
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "timeExpired-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send time expired notification: \(error)")
            } else {
                print("📤 Sent time expired notification with \(remainingMinutes) minutes")
            }
        }
    }
    
    func sendUnblockNotification(remainingMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Steps Trader"
        content.body = "Time restored! Available: \(remainingMinutes) minutes"
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "unblocked-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send unblock notification: \(error)")
            } else {
                print("📤 Sent unblock notification with \(remainingMinutes) minutes")
            }
        }
    }
    
    func sendRemainingTimeNotification(remainingMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "⏱️ Steps Trader"
        content.body = "Time remaining: \(remainingMinutes) min"
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "remainingTime-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send remaining time notification: \(error)")
            } else {
                print("📤 Sent remaining time notification: \(remainingMinutes) minutes")
            }
        }
    }
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🧪 Steps Trader Test"
        content.body = "Test notification to confirm the system works."
        content.sound = .default
        content.badge = 1
        
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error)")
            } else {
                print("📤 Sent test notification")
            }
        }
    }
}

// MARK: - Notification Errors
enum NotificationError: Error, LocalizedError {
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifications were denied by the user"
        }
    }
}
