import Foundation

// MARK: - Ephemeral Moment
//
// A one-time life event (wedding, concert, first day at a new job) that belongs
// to an energy category but is NOT saved to the permanent activity library.
// The label lives only inside the PastDaySnapshot for that specific day.
//
// Sync note: the optionId ("moment_<uuid>") flows into bodyIds/mindIds/heartIds
// and syncs to Supabase automatically. The human-readable label is local-only
// for now. TODO: sync moment labels via moment_labels JSONB column.

struct EphemeralMoment: Identifiable, Codable, Equatable {
    /// Stable identifier — also used as the optionId in daily selections.
    /// Format: "moment_<uuid>"
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
        self.id = "moment_\(UUID().uuidString)"
        self.label = label
        self.icon = icon
        self.category = category
        self.dayKey = dayKey
    }
}
