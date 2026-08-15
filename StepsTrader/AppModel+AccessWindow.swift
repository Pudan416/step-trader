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

    /// Minutes left on `groupId`'s window, **floored by wall clock** — never
    /// more than `initial - minutes since purchase`, whether or not the user
    /// spent them.
    ///
    /// There are deliberately two of these; see
    /// `unspentUsageBudgetMatchingShield(for:)` below for why, and do not
    /// merge them. This one is for the monitor-recovery paths in
    /// `AppModel+PayGate`, which need a pessimistic bound on how much of a
    /// window may already be gone when the DeviceActivity monitor is missing
    /// and its per-minute ticks never arrived. It must not be shown to the
    /// user: for an idle phone it under-reports time the user still owns.
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
        let wallClockElapsed = Int(Date.now.timeIntervalSince(started) / 60)
        let wallClockRemaining = max(0, initial - wallClockElapsed)
        return min(stored, wallClockRemaining)
    }

    /// Minutes left on `groupId`'s window **as the shield sees them** — the
    /// number every user-facing surface must show.
    ///
    /// The window is spent, not elapsed. `usageBudget_<id>` is stamped at
    /// purchase and decremented only by real usage ticks, and
    /// `ShieldRebuildHelper` decides whether to keep the apps unshielded from
    /// that raw value plus the window's wall-clock expiry — nothing else. So
    /// this asks exactly the shield's question: is the window still open, and
    /// if so, how much of it is unspent?
    ///
    /// Why not just use `remainingUsageBudget(for:)`: its wall-clock floor
    /// makes an idle hour look like a spent hour. A user who buys 60 minutes
    /// and puts the phone down would come back to a Feeds tab reading 0 and
    /// offering to sell the same window again, while the apps are in fact
    /// still open with 60 unspent minutes on them — charged twice for time
    /// they already own. That floor is a recovery heuristic and belongs only
    /// in the recovery paths.
    func unspentUsageBudgetMatchingShield(for groupId: String) -> Int {
        AppModel.unspentUsageBudgetMatchingShield(
            for: groupId,
            defaults: UserDefaults.stepsTrader()
        )
    }

    /// Testable core of `unspentUsageBudgetMatchingShield(for:)`.
    static func unspentUsageBudgetMatchingShield(for groupId: String, defaults: UserDefaults) -> Int {
        guard ShieldRebuildHelper.isUsageBudgetWallClockActive(
            defaults: defaults,
            groupId: groupId
        ) else { return 0 }
        return max(0, defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId)))
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
