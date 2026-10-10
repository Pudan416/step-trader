import Foundation

enum HappeningIntention: String, Codable, CaseIterable, Identifiable {
    case observe, more, less, trySomething

    var id: String { rawValue }
    var title: String {
        switch self {
        case .observe: "Observe"
        case .more: "More often"
        case .less: "Less often"
        case .trySomething: "Try it"
        }
    }
}

/// Device-only preferences, deliberately absent from Happening, snapshots,
/// SharedKeys and every sync payload. Unknown future IDs survive decoding.
struct PersonalHappeningProfile: Codable, Equatable {
    var version = 1
    var interests: Set<String> = []
    var pinnedIDs: Set<String> = []
    var hiddenIDs: Set<String> = []
    var intentions: [String: HappeningIntention] = [:]
    /// Resetting Personal forgets older recommendation signals, not saved days.
    var historyStartsAt: Date?
    var historyStartsAfterDayKey: String?
}
