import Foundation

/// A single loggable thing. Replaces `EnergyOption`, `CustomEnergyOption` and
/// `EphemeralMoment` — the three near-identical types the category model needed.
///
/// `useCount` and `lastUsedAt` are stored rather than derived: the palette reads
/// them every time it opens and must not scan history to do it.
struct Happening: Identifiable, Codable, Equatable {
    let id: String

    /// Fallback English title. For built-ins the authoritative copy lives in
    /// `Localizable.xcstrings` under `option.title.<id>`, matching the
    /// convention built-in options already use. User happenings carry their
    /// own title here and use it directly.
    var title: String

    let isBuiltIn: Bool
    var useCount: Int
    var lastUsedAt: Date?

    init(
        id: String,
        title: String,
        isBuiltIn: Bool,
        useCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isBuiltIn = isBuiltIn
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    /// Built-ins resolve through the string catalog; user happenings return
    /// their own title, which is already in whatever language they typed.
    func localizedTitle() -> String {
        guard isBuiltIn else { return title }
        return Bundle.main.localizedString(
            forKey: "option.title.\(id)", value: title, table: nil
        )
    }

    /// Records one addition. Called by the store, never directly by views —
    /// the store owns persistence and the palette's ordering reads the result.
    mutating func recordUse(at date: Date = .now) {
        useCount += 1
        lastUsedAt = date
    }
}

/// One concrete addition to a day. Multiple entries may share an `optionId`:
/// identity belongs to the addition, not to the happening being added.
struct OptionEntry: Identifiable, Codable, Equatable {
    let id: String
    let dayKey: String
    let optionId: String
    var colorHex: String
    var timestamp: Date
    var assetVariant: Int?
}

enum HappeningEconomy {
    static func points(forAdditionCount count: Int) -> Int {
        min(
            max(0, count) * HappeningDefaults.pointsPerAddition,
            HappeningDefaults.happeningsMaxPoints
        )
    }
}
