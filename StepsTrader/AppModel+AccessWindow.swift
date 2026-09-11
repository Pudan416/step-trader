import Foundation
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Access Window Management
extension AppModel {

    // MARK: - Group Usage Budget Helpers
    func isGroupUsageBudgetActive(_ groupId: String) -> Bool {
        unspentUsageBudgetMatchingShield(for: groupId) > 0
    }

    func remainingUsageBudget(for groupId: String) -> Int {
        unspentUsageBudgetMatchingShield(for: groupId)
    }

    /// Remaining purchased time, including the final partial minute, bounded by
    /// the same wall-clock deadline that closes the access window.
    func unspentUsageBudgetMatchingShield(for groupId: String) -> Int {
        Self.unspentUsageBudgetMatchingShield(for: groupId, defaults: UserDefaults.stepsTrader())
    }

    static func unspentUsageBudgetMatchingShield(for groupId: String, defaults: UserDefaults) -> Int {
        ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId)
    }

    /// Seconds until the custom day boundary fires and all unused budgets are wiped.
    var secondsUntilDayReset: TimeInterval {
        let next = DayBoundary.nextBoundary(
            after: Date.now,
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
