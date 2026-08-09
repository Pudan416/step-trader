import Foundation

/// Turns observed usage-budget readings into what the timer draws.
///
/// The window is spent, not elapsed: the honest signal is the per-minute
/// `usageBudgetTick_<groupId>_<m>` event the monitor extension writes to the app
/// group. This type therefore has no clock and performs no interpolation — the arc
/// steps a minute at a time. A stepping arc that is correct beats a flowing arc
/// that is not.
struct UnlockTimerModel: Sendable {

    struct State: Equatable, Sendable {
        let remainingMinutes: Int
        let fraction: Double
        let digits: String
    }

    private(set) var initialMinutes: Int
    private var lastShownMinutes: Int?

    init(initialMinutes: Int) {
        self.initialMinutes = max(0, initialMinutes)
    }

    /// Call when the user buys more time. This is the only path along which the
    /// displayed remaining time is allowed to increase.
    mutating func reset(initialMinutes: Int) {
        self.initialMinutes = max(0, initialMinutes)
        self.lastShownMinutes = nil
    }

    mutating func observe(remainingMinutes: Int) -> State {
        var value = min(max(0, remainingMinutes), initialMinutes)

        // Ticks can arrive late, and the wall-clock floor in
        // `AppModel.remainingUsageBudget(for:)` can disagree with the last tick.
        // Either way the arc must not jump forward and then fall back.
        if let last = lastShownMinutes {
            value = min(value, last)
        }
        lastShownMinutes = value

        let fraction = initialMinutes > 0 ? Double(value) / Double(initialMinutes) : 0
        return State(
            remainingMinutes: value,
            fraction: fraction,
            digits: String(format: "%02d:00", value)
        )
    }
}
