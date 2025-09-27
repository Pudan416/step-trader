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
        content.body = "Время для развлечений истекло! Сделайте больше шагов, чтобы разблокировать приложения."
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
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🧪 Steps Trader Test"
        content.body = "Тестовое уведомление для проверки работы системы."
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
            return "Уведомления отклонены пользователем"
        }
    }
}
