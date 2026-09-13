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

    /// Remaining usage minutes reported by Screen Time, valid until day reset.
    /// Idle time does not change this value.
    func unspentUsageBudgetMatchingShield(for groupId: String) -> Int {
        Self.unspentUsageBudgetMatchingShield(for: groupId, defaults: UserDefaults.stepsTrader())
    }

    static func unspentUsageBudgetMatchingShield(for groupId: String, defaults: UserDefaults) -> Int {
        guard ShieldRebuildHelper.isUsageBudgetActive(defaults: defaults, groupId: groupId) else { return 0 }
        return ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: groupId)
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
