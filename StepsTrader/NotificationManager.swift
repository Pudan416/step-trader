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
        content.body = "Время истекло! Проверьте, может еще есть время? Сделайте больше шагов для разблокировки."
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
            content.body = "Время истекло! У вас было \(remainingMinutes) мин. Сделайте больше шагов для разблокировки."
        } else {
            content.body = "Время истекло! Сделайте больше шагов для разблокировки."
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
        content.body = "Время восстановлено! Доступно: \(remainingMinutes) минут"
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
        content.body = "Осталось времени: \(remainingMinutes) мин"
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
