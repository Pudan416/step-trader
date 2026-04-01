import Foundation
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Access Window Management
extension AppModel {

    // MARK: - Group Usage Budget Helpers
    func isGroupUsageBudgetActive(_ groupId: String) -> Bool {
        UserDefaults.stepsTrader().integer(forKey: SharedKeys.usageBudgetKey(groupId)) > 0
    }

    func remainingUsageBudget(for groupId: String) -> Int {
        UserDefaults.stepsTrader().integer(forKey: SharedKeys.usageBudgetKey(groupId))
    }

    /// Seconds until the custom day boundary fires and all unused budgets are wiped.
    var secondsUntilDayReset: TimeInterval {
        let next = DayBoundary.nextBoundary(
            after: Date(),
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute
        )
        return max(0, next.timeIntervalSinceNow)
    }

    /// Minutes until day reset, rounded down.
    var minutesUntilDayReset: Int {
        Int(secondsUntilDayReset / 60)
    }
}
