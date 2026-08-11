import Foundation

/// Everything Me computes, as pure functions over values. Lives outside the
/// view so the week's numbers can be tested without a SwiftUI host, and so the
/// (non-trivial) aggregation runs once per data load rather than per body pass.
enum MeWeekStats {

    struct Summary: Equatable {
        var avgSteps: Int = 0
        var avgSleepHours: Double = 0
        var topHappeningIds: [String] = []
    }

    /// Averages over the days that actually have a snapshot — a day with no
    /// recorded data is absent, not a zero, so it must not drag the mean down.
    /// Happenings are ranked by how often they came up across the whole window.
    ///
    /// Counted from the week's snapshots rather than from `Happening.useCount`:
    /// that counter is lifetime, and this screen reports the last seven days.
    static func summary(snapshots: [PastDaySnapshot], topCount: Int = 3) -> Summary {
        guard !snapshots.isEmpty else { return Summary() }
        let count = snapshots.count

        let totalSteps = snapshots.reduce(0) { $0 + $1.steps }
        let totalSleep = snapshots.reduce(0.0) { $0 + $1.sleepHours }

        var counts: [String: Int] = [:]
        for snapshot in snapshots {
            for id in snapshot.happeningIds { counts[id, default: 0] += 1 }
        }

        // Count descending, then id ascending: Dictionary order is randomised
        // per process, so the tie-break has to be total or the list reshuffles
        // between launches.
        let ranked = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(topCount)
            .map(\.key)

        return Summary(
            avgSteps: totalSteps / count,
            avgSleepHours: totalSleep / Double(count),
            topHappeningIds: Array(ranked)
        )
    }

    /// Exact per-app color spend over `dayKeys`, summed from the persisted
    /// per-day ledger. Colors, not minutes: minutes per app are not readable by
    /// an app, and the payment log only knows what was bought.
    static func appSpend(byDay: [String: [String: Int]], dayKeys: [String]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for dayKey in dayKeys {
            guard let perApp = byDay[dayKey] else { continue }
            for (key, value) in perApp { totals[key, default: 0] += value }
        }
        return totals
    }

    /// The history days a user may open. Dormant today —
    /// `SubscriptionGate.allFeaturesUnlocked` makes `isPro` unconditionally
    /// true — but the constant is a documented kill-switch, so the rule stays
    /// live and tested. `sortedKeys` must be newest first.
    static func unlockedKeys(sortedKeys: [String], isPro: Bool, freeCount: Int) -> Set<String> {
        if isPro { return Set(sortedKeys) }
        return Set(sortedKeys.prefix(freeCount))
    }
}
