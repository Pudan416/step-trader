import Foundation

/// The daily energy readout behind the Canvas status pill.
///
/// It answers exactly one question — how much of what was *earned today* is
/// still unspent — so the two numbers can never disagree with the bar between
/// them. Deliberately excluded: `bonusSteps`, `totalStepsBalance`, and the
/// product-wide 100 ceiling. Those describe the wallet, not the day.
struct CanvasEnergyStatus: Equatable {
    /// Unspent energy from today's earnings, clamped into `0...earned`.
    let remaining: Int
    /// Energy gained today. The progress track represents this, not 100.
    let earned: Int

    /// - Parameters:
    ///   - stepsBalance: `model.userEconomyStore.stepsBalance` — the daily
    ///     balance without bonuses.
    ///   - baseEnergyToday: `model.healthStore.baseEnergyToday`.
    init(stepsBalance: Int, baseEnergyToday: Int) {
        let earned = max(0, baseEnergyToday)
        self.earned = earned
        // A recalculation can land before a HealthKit refresh, leaving a
        // balance that outruns today's earnings. Showing `90 / 72` would read
        // as a bug, so the stale side loses.
        self.remaining = min(max(0, stepsBalance), earned)
    }

    /// Fill fraction of the progress track. Zero when nothing was earned —
    /// an empty day shows an empty bar, not a full one.
    var progress: Double {
        guard earned > 0 else { return 0 }
        return Double(remaining) / Double(earned)
    }
}
