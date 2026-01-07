import Foundation
import UserNotifications

// MARK: - Notification Manager
final class NotificationManager: NotificationServiceProtocol {
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        
        if !granted {
            throw NotificationError.permissionDenied
        }
        
        print("📲 Notification permissions granted")
    }
    
    func sendTimeExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = "⏰ Steps Trader"
        content.body = "Fuel empty. Earn more steps to unlock."
        content.sound = .default
        content.badge = nil
        
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
            content.body = "Fuel empty. You had \(remainingMinutes) min. Earn steps to unlock."
        } else {
            content.body = "Fuel empty. Earn steps to unlock."
        }
        content.sound = .default
        content.badge = nil
        
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
        content.body = "Fuel restored: \(remainingMinutes) min."
        content.sound = .default
        content.badge = nil
        
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
        content.body = "Fuel left: \(remainingMinutes) min."
        content.sound = .default
        content.badge = nil
        
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
        content.badge = nil
        
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
    
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String) {
        let remainingMinutes = max(0, remainingSeconds / 60)
        let content = UNMutableNotificationContent()
        let displayName = TargetResolver.displayName(for: bundleId)
        content.title = "⏱️ \(displayName)"
        if remainingMinutes > 0 {
            content.body = "\(displayName) off in \(remainingMinutes) min."
        } else {
            content.body = "\(displayName) off in \(remainingSeconds) sec."
        }
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "accessWindow-\(bundleId)-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send access window reminder: \(error)")
            } else {
                print("📤 Sent access window reminder for \(bundleId)")
            }
        }
    }
    
    func scheduleAccessWindowStatus(remainingSeconds: Int, bundleId: String) {
        guard remainingSeconds > 10 else { return }
        
        // Стоп-листы для разных окон: 5 минут, 1 час, день
        let patterns: [[Int]]
        switch remainingSeconds {
        case ..<360: // ~5 минут
            patterns = [[60], [240]] // через 1 и 4 минуты
        case ..<4000: // ~1 час
            patterns = [[60], [1800], [3300]] // через 1, 30 и 55 минут
        default: // день и больше
            patterns = [[max(0, remainingSeconds - 3600)]] // за час до окончания
        }
        
        for offsets in patterns {
            guard let fireIn = offsets.first else { continue }
            guard fireIn > 0, fireIn < remainingSeconds else { continue }
            
            let content = UNMutableNotificationContent()
            let displayName = TargetResolver.displayName(for: bundleId)
            content.title = "⏱️ \(displayName)"
            let minutesLeft = max(0, (remainingSeconds - fireIn) / 60)
            if minutesLeft > 0 {
                content.body = "\(displayName) off in \(minutesLeft) min."
            } else {
                content.body = "\(displayName) off in \(remainingSeconds - fireIn) sec."
            }
            content.sound = .default
            content.badge = nil
            
            let request = UNNotificationRequest(
                identifier: "accessWindow-status-\(bundleId)-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(fireIn), repeats: false)
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ Failed to schedule access window status: \(error)")
                } else {
                    print("📤 Scheduled access window status for \(bundleId) in \(fireIn)s")
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
}
