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
        content.title = "Proof"
        content.body = "An app is closed. Open Proof to spend exp."
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
        content.title = "Proof"
        content.body = "An app is closed. Open Proof to spend exp."
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
        content.title = "Proof"
        content.body = "Exp restored. \(remainingMinutes) min."
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
        content.title = "Proof"
        content.body = "Exp left: \(remainingMinutes) min."
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

    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int) {
        guard minutesUsed > 0 || stepsCharged > 0 else { return }
        
        let content = UNMutableNotificationContent()
        let displayName = TargetResolver.displayName(for: bundleId)
        content.title = "⏱️ \(displayName)"
        
        if minutesUsed > 0 && stepsCharged > 0 {
            content.body = "Used: \(minutesUsed) min · Charged: \(stepsCharged) exp."
        } else if minutesUsed > 0 {
            content.body = "Used: \(minutesUsed) min."
        } else {
            content.body = "Charged: \(stepsCharged) exp."
        }
        
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "minuteModeSummary-\(bundleId)-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send minute mode summary notification: \(error)")
            } else {
                print("📤 Sent minute mode summary for \(bundleId): \(minutesUsed)m, \(stepsCharged) fuel")
            }
        }
    }
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Proof"
        content.body = "Test notification."
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
        
        // Reminder schedules for different windows: 5 min, 1 hour, day
        let patterns: [[Int]]
        switch remainingSeconds {
        case ..<360: // ~5 minutes
            patterns = [[60], [240]] // at 1 and 4 minutes
        case ..<4000: // ~1 hour
            patterns = [[60], [1800], [3300]] // at 1, 30, and 55 minutes
        default: // day or longer
            patterns = [[max(0, remainingSeconds - 3600)]] // 1 hour before expiry
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
