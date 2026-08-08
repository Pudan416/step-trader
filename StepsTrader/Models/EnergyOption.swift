import Foundation

struct EnergyOption: Identifiable, Codable, Equatable {
    let id: String
    /// Fallback English title. Authoritative copy lives in Localizable.xcstrings under
    /// `option.title.<id>` for built-in options. Custom (user-added) options use this directly.
    let titleEn: String
    let category: EnergyCategory
    let icon: String

    func title(for lang: String) -> String {
        let key = "option.title.\(id)"
        return Bundle.main.localizedString(forKey: key, value: titleEn, table: nil)
    }
}

struct CustomEnergyOption: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var titleEn: String
    let category: EnergyCategory
    var icon: String
    
    init(id: String, titleEn: String, category: EnergyCategory, icon: String = "pencil") {
        self.id = id
        self.titleEn = titleEn
        self.category = category
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        titleEn = try container.decode(String.self, forKey: .titleEn)
        category = try container.decode(EnergyCategory.self, forKey: .category)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "pencil"
    }

    private enum CodingKeys: String, CodingKey {
        case id, titleEn, category, icon
    }
    
    func title(for lang: String) -> String {
        titleEn
    }
    
    func asEnergyOption() -> EnergyOption {
        EnergyOption(id: id, titleEn: titleEn, category: category, icon: icon)
    }
}

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
