import Foundation
import UIKit
import UserNotifications

// MARK: - Notification Manager
final class NotificationManager: NotificationServiceProtocol, Sendable {
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])

        if !granted {
            throw NotificationError.permissionDenied
        }

        AppLogger.notifications.debug("📲 Notification permissions granted")

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    func sendTimeExpiredNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = String(localized: "An app is closed. Open Nowhere to unlock it.", comment: "Notification – app blocked body")
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "timeExpired-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("❌ Failed to send time expired notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent time expired notification")
            }
        }
    }
    
    func sendUnblockNotification(remainingMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = String(localized: "Colors restored. \(remainingMinutes) min.", comment: "Notification – budget restored body")
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "unblocked-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("❌ Failed to send unblock notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent unblock notification with \(remainingMinutes) minutes")
            }
        }
    }
    
    func sendRemainingTimeNotification(remainingMinutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = String(localized: "Colors left: \(remainingMinutes) min.", comment: "Notification – budget warning body")
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "remainingTime-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("❌ Failed to send remaining time notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent remaining time notification: \(remainingMinutes) minutes")
            }
        }
    }

    func sendMinuteModeSummary(bundleId: String, minutesUsed: Int, stepsCharged: Int) {
        guard minutesUsed > 0 || stepsCharged > 0 else { return }
        
        let content = UNMutableNotificationContent()
        let displayName = TargetResolver.displayName(for: bundleId)
        content.title = String(localized: "⏱️ \(displayName)", comment: "Notification – timer title with app name")
        
        if minutesUsed > 0 && stepsCharged > 0 {
            content.body = String(localized: "Used: \(minutesUsed) min · Charged: \(stepsCharged) colors.", comment: "Notification – usage summary body")
        } else if minutesUsed > 0 {
            content.body = String(localized: "Used: \(minutesUsed) min.", comment: "Notification – usage minutes only body")
        } else {
            content.body = String(localized: "Charged: \(stepsCharged) colors.", comment: "Notification – charged colors only body")
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
                AppLogger.notifications.error("❌ Failed to send minute mode summary notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent minute mode summary for \(bundleId): \(minutesUsed)m, \(stepsCharged) fuel")
            }
        }
    }
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = String(localized: "Test notification.", comment: "Notification – test notification body")
        content.sound = .default
        content.badge = nil
        
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("❌ Failed to send test notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent test notification")
            }
        }
    }
    
    func sendAccessWindowReminder(remainingSeconds: Int, bundleId: String) {
        let remainingMinutes = max(0, remainingSeconds / 60)
        let content = UNMutableNotificationContent()
        let displayName = TargetResolver.displayName(for: bundleId)
        content.title = String(localized: "⏱️ \(displayName)", comment: "Notification – timer title with app name")
        if remainingMinutes > 0 {
            content.body = String(localized: "\(displayName) off in \(remainingMinutes) min.", comment: "Notification – countdown minutes body")
        } else {
            content.body = String(localized: "\(displayName) off in \(remainingSeconds) sec.", comment: "Notification – countdown seconds body")
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
                AppLogger.notifications.error("❌ Failed to send access window reminder: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent access window reminder for \(bundleId)")
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
            content.title = String(localized: "⏱️ \(displayName)", comment: "Notification – timer title with app name")
            let minutesLeft = max(0, (remainingSeconds - fireIn) / 60)
            if minutesLeft > 0 {
                content.body = String(localized: "\(displayName) off in \(minutesLeft) min.", comment: "Notification – pre-expiry warning body")
            } else {
                content.body = String(localized: "\(displayName) off in \(remainingSeconds - fireIn) sec.", comment: "Notification – pre-expiry seconds body")
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
                    AppLogger.notifications.error("❌ Failed to schedule access window status: \(error.localizedDescription)")
                } else {
                    AppLogger.notifications.debug("📤 Scheduled access window status for \(bundleId) in \(fireIn)s")
                }
            }
        }
    }
    
    // MARK: - Daily Scheduled Notifications

    func sendActivityDetectedNotification(title: String, subtitle: String) {
        let defaults = UserDefaults.stepsTrader()
        let enabled = defaults.object(forKey: SharedKeys.notifyActivityDetected) as? Bool ?? true
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = "\(title) — \(subtitle)"
        content.sound = .default
        content.badge = nil

        let request = UNNotificationRequest(
            identifier: "activityDetected-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.notifications.error("❌ Failed to send workout detected notification: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Sent workout detected notification: \(title)")
            }
        }
    }

    func scheduleDailyCanvasReminder() {
        let defaults = UserDefaults.stepsTrader()
        let enabled = defaults.object(forKey: SharedKeys.notifyCanvasReminder) as? Bool ?? false
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["dailyCanvasReminder"])
        guard enabled else { return }

        let hour = defaults.object(forKey: SharedKeys.canvasReminderHour) as? Int ?? 21
        let minute = defaults.object(forKey: SharedKeys.canvasReminderMinute) as? Int ?? 0

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = String(localized: "Add the things that colored up your day to the canvas.", comment: "Notification – daily canvas reminder body")
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "dailyCanvasReminder", content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLogger.notifications.error("❌ Failed to schedule canvas reminder: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Scheduled daily canvas reminder at \(hour):\(String(format: "%02d", minute))")
            }
        }
    }

    func scheduleDayResetWarning(dayEndHour: Int, dayEndMinute: Int) {
        let defaults = UserDefaults.stepsTrader()
        let enabled = defaults.object(forKey: SharedKeys.notifyDayResetWarning) as? Bool ?? true
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["dayResetWarning"])
        guard enabled else { return }

        let hoursBeforeReset = defaults.object(forKey: SharedKeys.dayResetWarningHours) as? Int ?? 1

        var cal = Calendar.current
        cal.timeZone = .current
        var comps = DateComponents()
        comps.hour = dayEndHour
        comps.minute = dayEndMinute
        guard let pseudoDate = cal.date(from: comps) else { return }
        let fireDate = pseudoDate.addingTimeInterval(TimeInterval(-hoursBeforeReset * 3600))
        let fireComps = cal.dateComponents([.hour, .minute], from: fireDate)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        if hoursBeforeReset == 1 {
            content.body = String(localized: "Your canvas resets in 1 hour.", comment: "Notification – canvas reset 1 hour warning")
        } else {
            content.body = String(localized: "Your canvas resets in \(hoursBeforeReset) hours.", comment: "Notification – canvas reset hours warning")
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComps, repeats: true)
        let request = UNNotificationRequest(identifier: "dayResetWarning", content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLogger.notifications.error("❌ Failed to schedule day reset warning: \(error.localizedDescription)")
            } else {
                AppLogger.notifications.debug("📤 Scheduled day reset warning \(hoursBeforeReset)h before \(dayEndHour):\(String(format: "%02d", dayEndMinute))")
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
