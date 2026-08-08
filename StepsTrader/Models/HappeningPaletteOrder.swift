import Foundation

/// The palette's ranking rule. Pure — no storage, no clock, no UI.
enum HappeningPaletteOrder {

    /// How many happenings the palette shows on a settled day.
    static let visibleCount = 10

    /// Score is `useCount`, ties broken by more recent `lastUsedAt`, then by id.
    ///
    /// The fall-through to id matters: ranking runs on every palette open, and
    /// without a total order two calls on identical input could disagree and
    /// shuffle the cluster. Built-in and user happenings rank together, with no
    /// distinction between them.
    static func rank(_ happenings: [Happening]) -> [String] {
        happenings.sorted { lhs, rhs in
            if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
            let l = lhs.lastUsedAt?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            let r = rhs.lastUsedAt?.timeIntervalSince1970 ?? -.greatestFiniteMagnitude
            if l != r { return l > r }
            return lhs.id < rhs.id
        }.map(\.id)
    }
}

/// Freezes the palette order for the duration of one custom day.
///
/// Re-sorting after every tap moves buttons under the user's thumb and stops
/// muscle memory from forming, so the order is computed once per `dayKey` and
/// cached. Same shape as the daily-random-theme guard in
/// `AppModel+DailyRandomTheme`: stamp the day key, recompute only when it
/// changes. Callers pass a key from `AppModel.dayKey(for:)`, which respects the
/// user's configured `dayEndHour`/`dayEndMinute` rather than calendar midnight.
final class HappeningPaletteOrderCache {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// The frozen order for `dayKey`, recomputing only on rollover.
    ///
    /// Ids that no longer exist in `happenings` are filtered out — a deleted
    /// happening must not linger in a frozen order.
    func order(for dayKey: String, happenings: [Happening]) -> [String] {
        if defaults.string(forKey: SharedKeys.paletteOrderDayKey) == dayKey,
           let cached = defaults.stringArray(forKey: SharedKeys.paletteOrderIds) {
            let live = Set(happenings.map(\.id))
            return cached.filter(live.contains)
        }

        let fresh = Array(HappeningPaletteOrder.rank(happenings)
            .prefix(HappeningPaletteOrder.visibleCount))
        defaults.set(dayKey, forKey: SharedKeys.paletteOrderDayKey)
        defaults.set(fresh, forKey: SharedKeys.paletteOrderIds)
        return fresh
    }

    /// Appends a happening created mid-day to the end of the frozen order, so
    /// it shows in addition to the ten and nothing already on screen moves. It
    /// takes its ranked position on the next rollover.
    ///
    /// No-ops when `dayKey` is not the frozen one — the app can be backgrounded
    /// across the day boundary, and a stale append must not corrupt today.
    func append(id: String, dayKey: String) {
        guard defaults.string(forKey: SharedKeys.paletteOrderDayKey) == dayKey else { return }
        var current = defaults.stringArray(forKey: SharedKeys.paletteOrderIds) ?? []
        guard !current.contains(id) else { return }
        current.append(id)
        defaults.set(current, forKey: SharedKeys.paletteOrderIds)
    }
}
