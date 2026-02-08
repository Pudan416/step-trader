import Foundation

// MARK: - Gallery tab: past day snapshot (for history)
struct PastDaySnapshot: Codable, Equatable {
    var controlGained: Int
    var controlSpent: Int
    var activityIds: [String]
    var creativityIds: [String]
    var joysIds: [String]
    var steps: Int
    var sleepHours: Double

    enum CodingKeys: String, CodingKey {
        case controlGained, controlSpent, activityIds, creativityIds, joysIds, steps, sleepHours
        // Backward-compat keys (historical)
        case recoveryIds
        case restIds
    }

    // Backward compatibility - old snapshots won't have steps/sleep
    init(controlGained: Int, controlSpent: Int, activityIds: [String], creativityIds: [String], joysIds: [String], steps: Int = 0, sleepHours: Double = 0) {
        self.controlGained = controlGained
        self.controlSpent = controlSpent
        self.activityIds = activityIds
        self.creativityIds = creativityIds
        self.joysIds = joysIds
        self.steps = steps
        self.sleepHours = sleepHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlGained = try container.decode(Int.self, forKey: .controlGained)
        controlSpent = try container.decode(Int.self, forKey: .controlSpent)
        activityIds = try container.decode([String].self, forKey: .activityIds)
        if let v = try container.decodeIfPresent([String].self, forKey: .creativityIds) {
            creativityIds = v
        } else if let v = try container.decodeIfPresent([String].self, forKey: .recoveryIds) {
            creativityIds = v
        } else if let v = try container.decodeIfPresent([String].self, forKey: .restIds) {
            creativityIds = v
        } else {
            creativityIds = []
        }
        joysIds = try container.decode([String].self, forKey: .joysIds)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controlGained, forKey: .controlGained)
        try container.encode(controlSpent, forKey: .controlSpent)
        try container.encode(activityIds, forKey: .activityIds)
        try container.encode(creativityIds, forKey: .creativityIds)
        try container.encode(joysIds, forKey: .joysIds)
        try container.encode(steps, forKey: .steps)
        try container.encode(sleepHours, forKey: .sleepHours)
    }
}

// MARK: - Gallery tab: one of four daily slots (category + option)
struct DayGallerySlot: Codable, Equatable {
    var category: EnergyCategory?
    var optionId: String?
}

enum EnergyCategory: String, CaseIterable, Codable, Identifiable {
    case activity  // Activity (steps + movement activities)
    case creativity  // Creativity (choices)
    case joys      // Joys (gallery)

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "recovery" || raw == "rest" {
            self = .creativity
        } else if let value = EnergyCategory(rawValue: raw) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown EnergyCategory: \(raw)")
        }
    }
}

struct EnergyOption: Identifiable, Codable, Equatable {
    let id: String
    let titleEn: String
    let titleRu: String
    let category: EnergyCategory
    let icon: String
    
    func title(for lang: String) -> String {
        lang == "ru" ? titleRu : titleEn
    }
}

enum EnergyDefaults {
    static let maxBaseEnergy: Int = 100
    static let maxBonusEnergy: Int = 50
    static let maxSelectionsPerCategory: Int = 4
    
    static let sleepTargetHours: Double = 8
    static let sleepMaxPoints: Int = 20
    static let stepsTarget: Double = 10_000
    static let stepsMaxPoints: Int = 20
    
    static let selectionPoints: Int = 5
    
    static let options: [EnergyOption] = [
        // Activity (Assets: activity_*)
        EnergyOption(id: "activity_dancing", titleEn: "Dancing", titleRu: "Танцы", category: .activity, icon: "figure.dance"),
        EnergyOption(id: "activity_meal", titleEn: "Meal", titleRu: "Еда", category: .activity, icon: "fork.knife"),
        EnergyOption(id: "activity_overcome", titleEn: "Overcome", titleRu: "Преодолеть", category: .activity, icon: "bolt.fill"),
        EnergyOption(id: "activity_risk", titleEn: "Risk", titleRu: "Риск", category: .activity, icon: "exclamationmark.triangle.fill"),
        EnergyOption(id: "activity_sex", titleEn: "Sex", titleRu: "Секс", category: .activity, icon: "heart.fill"),
        EnergyOption(id: "activity_sport", titleEn: "Sport", titleRu: "Спорт", category: .activity, icon: "sportscourt.fill"),
        EnergyOption(id: "activity_strong", titleEn: "Strong", titleRu: "Сила", category: .activity, icon: "dumbbell.fill"),
        EnergyOption(id: "activity_other", titleEn: "Other", titleRu: "Другое", category: .activity, icon: "plus.circle.fill"),

        // Creativity (Assets: creativity_* — all 7 pictures in gallery)
        EnergyOption(id: "creativity_curiosity", titleEn: "Curiosity", titleRu: "Любопытство", category: .creativity, icon: "sparkles"),
        EnergyOption(id: "creativity_doing_cash", titleEn: "Cash doing", titleRu: "Делать деньги", category: .creativity, icon: "banknote"),
        EnergyOption(id: "creativity_fantasizing", titleEn: "Fantasizing", titleRu: "Фантазии", category: .creativity, icon: "cloud.fill"),
        EnergyOption(id: "creativity_general", titleEn: "General", titleRu: "Общее", category: .creativity, icon: "sparkles"),
        EnergyOption(id: "creativity_invisible", titleEn: "Invisible", titleRu: "Невидимое", category: .creativity, icon: "eye.slash.fill"),
        EnergyOption(id: "creativity_museum", titleEn: "Museum", titleRu: "Музей", category: .creativity, icon: "building.columns.fill"),
        EnergyOption(id: "creativity_observe", titleEn: "Observe", titleRu: "Наблюдать", category: .creativity, icon: "eye.fill"),
        EnergyOption(id: "creativity_other", titleEn: "Other", titleRu: "Другое", category: .creativity, icon: "plus.circle.fill"),

        // Joys (Assets: joys_*)
        EnergyOption(id: "joys_cringe", titleEn: "Cringe", titleRu: "Кринж", category: .joys, icon: "face.dashed"),
        EnergyOption(id: "joys_embrase", titleEn: "Embrace", titleRu: "Обнять", category: .joys, icon: "heart.circle.fill"),
        EnergyOption(id: "joys_emotional", titleEn: "Emotional", titleRu: "Эмоции", category: .joys, icon: "theatermasks.fill"),
        EnergyOption(id: "joys_friends", titleEn: "Friends", titleRu: "Друзья", category: .joys, icon: "person.2.fill"),
        EnergyOption(id: "joys_happy_tears", titleEn: "Happy tears", titleRu: "Счастье", category: .joys, icon: "drop.circle.fill"),
        EnergyOption(id: "joys_in_love", titleEn: "In love", titleRu: "Влюблённость", category: .joys, icon: "heart.fill"),
        EnergyOption(id: "joys_kiss", titleEn: "Kiss", titleRu: "Поцелуй", category: .joys, icon: "mouth.fill"),
        EnergyOption(id: "joys_love_myself", titleEn: "Love myself", titleRu: "Любить себя", category: .joys, icon: "person.fill.checkmark"),
        EnergyOption(id: "joys_money", titleEn: "Money", titleRu: "Деньги", category: .joys, icon: "dollarsign.circle.fill"),
        EnergyOption(id: "joys_range", titleEn: "Range", titleRu: "Размах", category: .joys, icon: "arrow.left.and.right.circle.fill"),
        EnergyOption(id: "joys_rebel", titleEn: "Rebel", titleRu: "Бунт", category: .joys, icon: "flame.fill"),
        EnergyOption(id: "joysl_junkfood", titleEn: "Junk food", titleRu: "Фастфуд", category: .joys, icon: "takeoutbag.and.cup.and.straw.fill"),
        EnergyOption(id: "joys_other", titleEn: "Other", titleRu: "Другое", category: .joys, icon: "plus.circle.fill")
    ]
    
    /// IDs of options that open "Add custom activity" sheet
    static let otherOptionIds: Set<String> = ["activity_other", "creativity_other", "joys_other"]
}

// MARK: - Custom (user-added) activity option, persisted in UserDefaults
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

// MARK: - Available icons for custom activities
enum CustomActivityIcons {
    static let activity: [String] = [
        "figure.run", "figure.walk", "figure.hiking", "figure.outdoor.cycle",
        "figure.pool.swim", "figure.yoga", "figure.dance", "figure.basketball",
        "figure.tennis", "figure.golf", "figure.skiing.downhill", "figure.climbing",
        "sportscourt.fill", "dumbbell.fill", "bicycle", "skateboard.fill",
        "soccerball", "football.fill", "baseball.fill", "volleyball.fill"
    ]
    
    static let creativity: [String] = [
        "moon.zzz.fill", "bed.double.fill", "cup.and.saucer.fill", "leaf.fill",
        "drop.fill", "wind", "sparkles", "cloud.fill",
        "sun.max.fill", "umbrella.fill", "flame.fill", "snowflake",
        "bubble.left.and.bubble.right.fill", "heart.fill", "brain.head.profile", "eye.fill"
    ]
    
    static let joys: [String] = [
        "paintbrush.fill", "music.note", "book.fill", "gamecontroller.fill",
        "film.fill", "tv.fill", "headphones", "guitars.fill",
        "camera.fill", "photo.fill", "heart.fill", "star.fill",
        "gift.fill", "balloon.fill", "party.popper.fill", "birthday.cake.fill",
        "face.smiling.fill", "hands.clap.fill", "hand.thumbsup.fill", "pawprint.fill"
    ]
    
    static func icons(for category: EnergyCategory) -> [String] {
        switch category {
        case .activity: return activity
        case .creativity: return creativity
        case .joys: return joys
        }
    }
}
