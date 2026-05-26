import Foundation

// MARK: - Ephemeral Moment
//
// A one-time life event (wedding, concert, first day at a new job) that belongs
// to an energy category but is NOT saved to the permanent activity library.
// The label lives only inside the PastDaySnapshot for that specific day.
//
// Sync contract (this device only, by design):
// - Moments are stored locally in `AppModel.dailyMoments` and persisted in the
//   current day's `PastDaySnapshot.moments`. Energy accounting works because
//   the moment's optionId is added to `dailyBodySelections` / `dailyRestSelections`
//   / `dailyHeartSelections` along with regular activities.
// - Moment IDs (prefix `moment_`) are *filtered out* at every Supabase sync
//   boundary — both when sending day snapshots / daily selections and when
//   receiving them. This keeps the UI promise in `MomentEntrySheet`
//   ("Just for today, on this device.") truthful: a moment never leaves the
//   device and never arrives from another device as an opaque `moment_<uuid>`
//   string. Filter helpers live below; new sync sites must use them.
// - Cross-device moment sync is a separate feature (would require a
//   `moments` JSONB column on `user_day_snapshots` plus restore + merge
//   semantics). See CODE_AUDIT.md §5.5 for the follow-up scope.

struct EphemeralMoment: Identifiable, Codable, Equatable, Sendable {
    /// Stable identifier — also used as the optionId in daily selections.
    /// Format: `EphemeralMoment.idPrefix + "<uuid>"`.
    let id: String

    /// Human-readable label entered by the user. e.g. "Wedding", "Concert".
    var label: String

    /// SF Symbol name for the icon chosen at creation time.
    var icon: String

    /// Energy category this moment belongs to (.body / .mind / .heart).
    /// Determines which selection list it goes into and which canvas shape it uses.
    let category: EnergyCategory

    /// Day key (yyyy-MM-dd) the moment was created for.
    let dayKey: String

    init(label: String, icon: String, category: EnergyCategory, dayKey: String) {
        self.id = Self.idPrefix + UUID().uuidString
        self.label = label
        self.icon = icon
        self.category = category
        self.dayKey = dayKey
    }
}

// MARK: - Local-only sync helpers
//
// Used by AppModel and SupabaseSyncService to filter moment IDs at the sync
// boundary. Do NOT inline the prefix string — go through these helpers so the
// "moments are device-local" contract has a single source of truth.
extension EphemeralMoment {
    /// Prefix used for `EphemeralMoment.id` values. Stable on disk and on the
    /// wire (the latter only via category ID arrays that we now filter out).
    static let idPrefix: String = "moment_"

    /// `true` when the given option ID belongs to an `EphemeralMoment`.
    static func isMomentId(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }

    /// Returns `ids` with any `moment_*` entries removed. Use at every Supabase
    /// sync site (send + receive) so moment IDs do not cross the device boundary.
    static func filteredOutOfSync(_ ids: [String]) -> [String] {
        ids.filter { !isMomentId($0) }
    }
}
