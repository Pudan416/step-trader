import Foundation

// MARK: - Budget & Day Management
extension AppModel {
    func updateDayEnd(hour: Int, minute: Int) {
        dayEndHour = max(0, min(23, hour))
        dayEndMinute = max(0, min(59, minute))
        budgetEngine.updateDayEnd(hour: hour, minute: minute)
        checkDayBoundary()
        scheduleDayBoundaryTimer()
        syncUserPreferencesToSupabase()
        (notificationService as? NotificationManager)?
            .scheduleDayResetWarning(dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
    
}
