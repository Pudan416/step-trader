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
        let defaults = UserDefaults.stepsTrader()
        let stored = defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId))
        guard stored > 0,
              let started = defaults.object(forKey: SharedKeys.usageBudgetStartedKey(groupId)) as? Date
        else { return stored }

        let initial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        guard initial > 0 else { return stored }

        // Wall-clock floor: never show more remaining than wall-clock allows.
        // DeviceActivity ticks may lag (e.g. monitoring not yet started after
        // widget unlock, or monitor lost and restarted), so use wall-clock as
        // a lower bound on elapsed time.
        let wallClockElapsed = Int(Date().timeIntervalSince(started) / 60)
        let wallClockRemaining = max(0, initial - wallClockElapsed)
        return min(stored, wallClockRemaining)
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
