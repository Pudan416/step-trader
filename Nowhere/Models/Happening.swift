import Foundation

/// A single loggable thing. Replaces `EnergyOption`, `CustomEnergyOption` and
/// `EphemeralMoment` — the three near-identical types the category model needed.
///
/// `useCount` and `lastUsedAt` retain local usage metadata. Personal also uses
/// restored day snapshots when an older account has no local counters.
struct Happening: Identifiable, Codable, Equatable {
    static let titleCharacterLimit = 20

    let id: String

    /// Reviewed English copy for new built-ins. Historical records preserve
    /// their original titles and legacy string-catalog keys.
    var title: String

    let isBuiltIn: Bool
    /// Stable editorial tags used for day summaries and long-term patterns.
    /// Unknown future tags are retained as strings for forward compatibility.
    var tags: [String]
    var useCount: Int
    var lastUsedAt: Date?

    static func limitedTitle(_ title: String) -> String {
        String(title.prefix(titleCharacterLimit))
    }

    init(
        id: String,
        title: String,
        isBuiltIn: Bool,
        tags: [String] = [],
        useCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isBuiltIn = isBuiltIn
        self.tags = Array(Set(tags)).sorted()
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, isBuiltIn, tags, useCount, lastUsedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        tags = Array(Set(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])).sorted()
        useCount = try container.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encode(tags, forKey: .tags)
        try container.encode(useCount, forKey: .useCount)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }

    /// The fixed catalog is English. Older built-ins retain their localization;
    /// historical user records retain the language in which they were entered.
    func localizedTitle() -> String {
        guard isBuiltIn else { return title }
        if id.hasPrefix("event_") { return title }
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

/// Computes per-day tag frequencies from the catalog. A single happening ID
/// contributes once per day so repeated taps do not dominate a day title.
enum HappeningTagging {
    static func counts(for happeningIDs: [String], catalog: [Happening]) -> [String: Int] {
        let byID = Dictionary(catalog.map { ($0.id, $0.tags) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for id in Set(happeningIDs) {
            for tag in byID[id] ?? [] {
                counts[tag, default: 0] += 1
            }
        }
        return counts
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
