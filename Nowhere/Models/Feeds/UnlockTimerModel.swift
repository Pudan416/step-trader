import Foundation

/// Turns the latest wall-clock pass reading into the minute display and fill state.
///
/// The app polls the saved deadline and reports whole remaining minutes. This
/// value type has no clock and performs no interpolation, so the arc changes in
/// whole-minute steps.
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

    /// Call when a new pass starts after the previous pass has expired.
    mutating func reset(initialMinutes: Int) {
        self.initialMinutes = max(0, initialMinutes)
        self.lastShownMinutes = nil
    }

    mutating func observe(remainingMinutes: Int) -> State {
        var value = min(max(0, remainingMinutes), initialMinutes)

        // Shared state can change outside the app (for example, a widget purchase
        // or monitor recovery). Keep the displayed arc from jumping forward.
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
