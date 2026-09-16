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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent time expired notification")
            } catch {
                AppLogger.notifications.error("❌ Failed to send time expired notification: \(error.localizedDescription)")
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent unblock notification with \(remainingMinutes) minutes")
            } catch {
                AppLogger.notifications.error("❌ Failed to send unblock notification: \(error.localizedDescription)")
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent remaining time notification: \(remainingMinutes) minutes")
            } catch {
                AppLogger.notifications.error("❌ Failed to send remaining time notification: \(error.localizedDescription)")
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent minute mode summary for \(bundleId): \(minutesUsed)m, \(stepsCharged) fuel")
            } catch {
                AppLogger.notifications.error("❌ Failed to send minute mode summary notification: \(error.localizedDescription)")
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent test notification")
            } catch {
                AppLogger.notifications.error("❌ Failed to send test notification: \(error.localizedDescription)")
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent access window reminder for \(bundleId)")
            } catch {
                AppLogger.notifications.error("❌ Failed to send access window reminder: \(error.localizedDescription)")
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
            
            Task {
                do {
                    try await UNUserNotificationCenter.current().add(request)
                    AppLogger.notifications.debug("📤 Scheduled access window status for \(bundleId) in \(fireIn)s")
                } catch {
                    AppLogger.notifications.error("❌ Failed to schedule access window status: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Daily Scheduled Notifications

    func sendActivityDetectedNotification(for suggestion: ActivitySuggestion) {
        let defaults = UserDefaults.stepsTrader()
        let enabled = defaults.object(forKey: SharedKeys.notifyActivityDetected) as? Bool ?? true
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Nowhere", comment: "Notification – app name used as title")
        content.body = "\(suggestion.title) — \(suggestion.subtitle)"
        content.sound = .default
        content.badge = nil
        content.userInfo = ["activitySuggestionId": suggestion.id]

        let request = UNNotificationRequest(
            identifier: activityDetectedIdentifier(for: suggestion.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.notifications.debug("📤 Sent workout detected notification: \(suggestion.title)")
            } catch {
                AppLogger.notifications.error("❌ Failed to send workout detected notification: \(error.localizedDescription)")
            }
        }
    }

    func removeActivityDetectedNotifications(suggestionIds: [String]) {
        guard !suggestionIds.isEmpty else { return }
        let identifiers = suggestionIds.map(activityDetectedIdentifier(for:))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func activityDetectedIdentifier(for suggestionId: String) -> String {
        "activityDetected-\(suggestionId)"
    }

    func scheduleDailyCanvasReminder() {
        Task { @MainActor in EveningReflectionReminderScheduler.refresh() }
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
        Task {
            do {
                try await center.add(request)
                AppLogger.notifications.debug("📤 Scheduled day reset warning \(hoursBeforeReset)h before \(dayEndHour):\(String(format: "%02d", dayEndMinute))")
            } catch {
                AppLogger.notifications.error("❌ Failed to schedule day reset warning: \(error.localizedDescription)")
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


/// Serial reconciliation prevents an older async scheduling call from restoring
/// a reminder after an edit or opt-out has cancelled it.
@MainActor
private enum EveningReflectionReminderScheduler {
    private static var pendingRefresh: Task<Void, Never>?

    static func refresh() {
        let previous = pendingRefresh
        previous?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["dailyCanvasReminder"])
        center.removeDeliveredNotifications(withIdentifiers: ["dailyCanvasReminder"])

        let defaults = UserDefaults.stepsTrader()
        let now = Date.now
        // Do not wait on async authorization checks to cancel today's alert.
        if !defaults.bool(forKey: SharedKeys.notifyCanvasReminder)
            || !canvasIsEmpty(at: now, defaults: defaults)
            || defaults.string(forKey: SharedKeys.eveningReflectionDismissedDay) == EveningReflection.dayKey(for: now) {
            let id = EveningReflection.notificationPrefix + EveningReflection.dayKey(for: now)
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }

        pendingRefresh = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let pending = await center.pendingNotificationRequests()
            let settings = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            let oldIDs = pending.map(\.identifier).filter { $0.hasPrefix(EveningReflection.notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)

            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
            let dates = EveningReflection.reminderDates(
                after: .now,
                enabled: allowed && defaults.bool(forKey: SharedKeys.notifyCanvasReminder),
                dismissedDay: defaults.string(forKey: SharedKeys.eveningReflectionDismissedDay) ?? "",
                isCanvasEmpty: { canvasIsEmpty(at: $0, defaults: defaults) }
            )
            for date in dates {
                guard !Task.isCancelled else { return }
                let day = EveningReflection.dayKey(for: date)
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Nowhere")
                content.body = String(localized: "What would you like to keep from today?")
                content.sound = .default
                content.userInfo = ["eveningReflectionDay": day]
                // Floating local date components keep the 20:00 wall clock.
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let request = UNNotificationRequest(
                    identifier: EveningReflection.notificationPrefix + day,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                do { try await center.add(request) }
                catch { AppLogger.notifications.error("Evening reflection reminder failed: \(error.localizedDescription)") }
            }
        }
    }

    private static func canvasIsEmpty(at date: Date, defaults: UserDefaults) -> Bool {
        let boundary = AppModel.storedDayEnd()
        let key = DayBoundary.dayKey(for: date, dayEndHour: boundary.hour, dayEndMinute: boundary.minute)
        if let canvas = CanvasStorageService.shared.loadCanvas(for: key),
           !canvas.elements.isEmpty || canvas.needsRemoteHydration { return false }
        guard let data = defaults.data(forKey: SharedKeys.todayAdditions) else { return true }
        // Corrupt/unknown local data must not be advertised as an empty day.
        guard let additions = try? JSONDecoder().decode([OptionEntry].self, from: data) else { return false }
        return !additions.contains { $0.dayKey == key }
    }
}
