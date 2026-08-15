import Foundation

/// The one persisted piece of the palette's figures.
///
/// Everything else — shape type, colour, seed, rotation — is derived from this
/// nonce by `HappeningShapeRoll`, so there is nothing else that can fall out of
/// sync with it.
final class HappeningShapeNonceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// The nonce for `dayKey`, minting and persisting one when the stored value
    /// belongs to another day. Reading is what rolls the day over — there is no
    /// separate rollover hook to forget to call.
    func nonce(for dayKey: String) -> UInt64 {
        guard
            defaults.string(forKey: SharedKeys.happeningShapeNonceDayKey) == dayKey,
            let stored = defaults.object(forKey: SharedKeys.happeningShapeNonce) as? NSNumber
        else {
            return mint(for: dayKey)
        }
        return UInt64(bitPattern: stored.int64Value)
    }

    /// Shake.
    @discardableResult
    func reroll(for dayKey: String) -> UInt64 {
        mint(for: dayKey)
    }

    /// `UserDefaults` has no `UInt64` accessor. Storing the bit pattern as
    /// `Int64` round-trips exactly, including nonces with the high bit set.
    private func mint(for dayKey: String) -> UInt64 {
        let value = UInt64.random(in: UInt64.min...UInt64.max)
        defaults.set(NSNumber(value: Int64(bitPattern: value)), forKey: SharedKeys.happeningShapeNonce)
        defaults.set(dayKey, forKey: SharedKeys.happeningShapeNonceDayKey)
        return value
    }
}
