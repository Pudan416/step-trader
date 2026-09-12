import Foundation

/// The daily energy readout behind the Canvas status pill.
///
/// It carries two moving numbers and one fixed one: what the day earned, how
/// much of that is still unspent, and the product's daily ceiling. Both bars
/// measure the ceiling, so a half-full pill means a half-full day rather than
/// "half of whatever happened to be earned so far".
struct CanvasEnergyStatus: Equatable {
    /// Unspent energy from today's earnings, clamped into `0...earned`.
    let remaining: Int
    /// Energy gained today, clamped into `0...maximum`.
    let earned: Int
    /// The product's daily maximum — the static number in the pill.
    let maximum: Int

    /// - Parameters:
    ///   - stepsBalance: `model.userEconomyStore.stepsBalance` — the daily
    ///     balance without bonuses.
    ///   - baseEnergyToday: `model.healthStore.baseEnergyToday`.
    ///   - maximum: `EnergyDefaults.maxBaseEnergy`.
    init(stepsBalance: Int, baseEnergyToday: Int, maximum: Int) {
        self.maximum = maximum
        // The formula already caps earnings at the ceiling, but the pill draws
        // a bar: a value past the track would render outside it.
        let earned = min(max(0, baseEnergyToday), max(0, maximum))
        self.earned = earned
        // A recalculation can land before a HealthKit refresh, leaving a
        // balance that outruns today's earnings. The stale side loses.
        self.remaining = min(max(0, stepsBalance), earned)
    }

    /// Fill fraction for the unspent portion.
    var progress: Double { fraction(of: remaining) }

    /// Fill fraction for everything earned today — drawn as a tick, so the
    /// user can see how far the day got even after spending some of it.
    var earnedProgress: Double { fraction(of: earned) }

    private func fraction(of value: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return Double(value) / Double(maximum)
    }
}
