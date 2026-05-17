import Foundation

struct EnergyOption: Identifiable, Codable, Equatable {
    let id: String
    /// Fallback English title. Authoritative copy lives in Localizable.xcstrings under
    /// `option.title.<id>` for built-in options. Custom (user-added) options use this directly.
    let titleEn: String
    /// Fallback Russian title. Same semantics as `titleEn`.
    let titleRu: String
    let category: EnergyCategory
    let icon: String

    func title(for lang: String) -> String {
        let fallback = lang == "ru" ? titleRu : titleEn
        let key = "option.title.\(id)"
        return Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }
}

struct OptionEntry: Identifiable, Codable, Equatable {
    let id: String
    let dayKey: String
    let optionId: String
    let category: EnergyCategory
    var colorHex: String
    var text: String
    var timestamp: Date
    var assetVariant: Int?
}

struct CustomEnergyOption: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var titleEn: String
    var titleRu: String
    let category: EnergyCategory
    var icon: String
    
    init(id: String, titleEn: String, titleRu: String, category: EnergyCategory, icon: String = "pencil") {
        self.id = id
        self.titleEn = titleEn
        self.titleRu = titleRu
        self.category = category
        self.icon = icon
    }
    
    func title(for lang: String) -> String {
        lang == "ru" ? titleRu : titleEn
    }
    
    func asEnergyOption() -> EnergyOption {
        EnergyOption(id: id, titleEn: titleEn, titleRu: titleRu, category: category, icon: icon)
    }
}

struct EnergyRoutine: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var bodyIds: [String]
    var mindIds: [String]
    var heartIds: [String]
    var lastUsed: Date?

    init(id: String = UUID().uuidString, name: String, bodyIds: [String], mindIds: [String], heartIds: [String], lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.bodyIds = bodyIds
        self.mindIds = mindIds
        self.heartIds = heartIds
        self.lastUsed = lastUsed
    }
}
