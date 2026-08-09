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
    var dayKey: String
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

/// A saved preset. The three category arrays collapsed to one flat list;
/// `init(from:)` still reads the old shape so saved routines survive.
struct EnergyRoutine: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var happeningIds: [String]
    var lastUsed: Date?

    init(id: String = UUID().uuidString, name: String, happeningIds: [String], lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.happeningIds = happeningIds
        self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, happeningIds, lastUsed
        case bodyIds, mindIds, heartIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let flat = try c.decodeIfPresent([String].self, forKey: .happeningIds) {
            happeningIds = flat
        } else {
            happeningIds = (try c.decodeIfPresent([String].self, forKey: .bodyIds) ?? [])
                + (try c.decodeIfPresent([String].self, forKey: .mindIds) ?? [])
                + (try c.decodeIfPresent([String].self, forKey: .heartIds) ?? [])
        }
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(happeningIds, forKey: .happeningIds)
        try c.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
}
