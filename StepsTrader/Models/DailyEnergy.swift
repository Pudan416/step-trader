import Foundation

// MARK: - Gallery tab: past day snapshot (for history)
struct PastDaySnapshot: Codable, Equatable {
    var experienceEarned: Int
    var experienceSpent: Int
    var bodyIds: [String]
    var mindIds: [String]
    var heartIds: [String]
    var steps: Int
    var sleepHours: Double
    var stepsTarget: Double
    var sleepTargetHours: Double

    enum CodingKeys: String, CodingKey {
        case experienceEarned
        case experienceSpent
        // Encode with new names, decode with backward compat
        case bodyIds
        case mindIds
        case heartIds
        case steps
        case sleepHours
        case stepsTarget
        case sleepTargetHours
        // Backward-compat keys (historical)
        case controlGained
        case controlSpent
        case activityIds
        case creativityIds
        case recoveryIds
        case restIds
        case joysIds
    }

    // Backward compatibility - old snapshots won't have steps/sleep/targets
    init(
        experienceEarned: Int,
        experienceSpent: Int,
        bodyIds: [String],
        mindIds: [String],
        heartIds: [String],
        steps: Int = 0,
        sleepHours: Double = 0,
        stepsTarget: Double = EnergyDefaults.stepsTarget,
        sleepTargetHours: Double = EnergyDefaults.sleepTargetHours
    ) {
        self.experienceEarned = experienceEarned
        self.experienceSpent = experienceSpent
        self.bodyIds = bodyIds
        self.mindIds = mindIds
        self.heartIds = heartIds
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let earned = try container.decodeIfPresent(Int.self, forKey: .experienceEarned) {
            experienceEarned = earned
        } else {
            experienceEarned = try container.decode(Int.self, forKey: .controlGained)
        }
        if let spent = try container.decodeIfPresent(Int.self, forKey: .experienceSpent) {
            experienceSpent = spent
        } else {
            experienceSpent = try container.decode(Int.self, forKey: .controlSpent)
        }
        // bodyIds: try new key first, then legacy "activityIds"
        if let v = try container.decodeIfPresent([String].self, forKey: .bodyIds) {
            bodyIds = v
        } else {
            bodyIds = (try? container.decode([String].self, forKey: .activityIds)) ?? []
        }
        // mindIds: try new key first, then legacy "creativityIds", "recoveryIds", "restIds"
        if let v = try container.decodeIfPresent([String].self, forKey: .mindIds) {
            mindIds = v
        } else if let v = try container.decodeIfPresent([String].self, forKey: .creativityIds) {
            mindIds = v
        } else if let v = try container.decodeIfPresent([String].self, forKey: .recoveryIds) {
            mindIds = v
        } else if let v = try container.decodeIfPresent([String].self, forKey: .restIds) {
            mindIds = v
        } else {
            mindIds = []
        }
        // heartIds: try new key first, then legacy "joysIds"
        if let v = try container.decodeIfPresent([String].self, forKey: .heartIds) {
            heartIds = v
        } else {
            heartIds = (try? container.decode([String].self, forKey: .joysIds)) ?? []
        }
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        stepsTarget = try container.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTargetHours = try container.decodeIfPresent(Double.self, forKey: .sleepTargetHours) ?? EnergyDefaults.sleepTargetHours
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(experienceEarned, forKey: .experienceEarned)
        try container.encode(experienceSpent, forKey: .experienceSpent)
        try container.encode(bodyIds, forKey: .bodyIds)
        try container.encode(mindIds, forKey: .mindIds)
        try container.encode(heartIds, forKey: .heartIds)
        try container.encode(steps, forKey: .steps)
        try container.encode(sleepHours, forKey: .sleepHours)
        try container.encode(stepsTarget, forKey: .stepsTarget)
        try container.encode(sleepTargetHours, forKey: .sleepTargetHours)
    }
}

// MARK: - Gallery tab: one of four daily slots (category + option)
struct DayGallerySlot: Codable, Equatable {
    var category: EnergyCategory?
    var optionId: String?
}

enum EnergyCategory: String, CaseIterable, Codable, Identifiable {
    case body      // Body (steps + movement activities)
    case mind      // Mind (attention + creativity)
    case heart     // Heart (feelings + connection)

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Backward compatibility: old raw values → new cases
        switch raw {
        case "activity":                self = .body
        case "creativity", "recovery", "rest": self = .mind
        case "joys":                    self = .heart
        default:
            if let value = EnergyCategory(rawValue: raw) {
                self = value
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown EnergyCategory: \(raw)")
            }
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

// MARK: - Option Entry (user's daily log for an activity)
struct OptionEntry: Identifiable, Codable, Equatable {
    let id: String // matches optionId
    let dayKey: String
    let optionId: String
    let category: EnergyCategory
    var colorHex: String
    var text: String
    var timestamp: Date
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
        // BODY - Ways your body was truly present today
        EnergyOption(id: "body_walking", titleEn: "Walking", titleRu: "Ходьба", category: .body, icon: "figure.walk"),
        EnergyOption(id: "body_physical_effort", titleEn: "Physical Effort", titleRu: "Физическое усилие", category: .body, icon: "dumbbell.fill"),
        EnergyOption(id: "body_stretching", titleEn: "Stretching", titleRu: "Растяжка", category: .body, icon: "figure.flexibility"),
        EnergyOption(id: "body_resting", titleEn: "Resting", titleRu: "Отдых", category: .body, icon: "bed.double.fill"),
        EnergyOption(id: "body_breathing", titleEn: "Breathing", titleRu: "Дыхание", category: .body, icon: "wind"),
        EnergyOption(id: "body_touch", titleEn: "Touch", titleRu: "Прикосновение", category: .body, icon: "hand.raised.fill"),
        EnergyOption(id: "body_balance", titleEn: "Balance", titleRu: "Баланс", category: .body, icon: "figure.yoga"),
        EnergyOption(id: "body_repetition", titleEn: "Repetition", titleRu: "Повторение", category: .body, icon: "arrow.clockwise"),
        EnergyOption(id: "body_warming", titleEn: "Warming", titleRu: "Согревание", category: .body, icon: "sun.max.fill"),
        EnergyOption(id: "body_stillness", titleEn: "Stillness", titleRu: "Неподвижность", category: .body, icon: "figure.stand"),

        // MIND - Ways your attention shaped the day
        EnergyOption(id: "mind_focusing", titleEn: "Focusing", titleRu: "Фокусировка", category: .mind, icon: "eye.fill"),
        EnergyOption(id: "mind_learning", titleEn: "Learning", titleRu: "Обучение", category: .mind, icon: "book.fill"),
        EnergyOption(id: "mind_thinking", titleEn: "Thinking", titleRu: "Размышление", category: .mind, icon: "brain.head.profile"),
        EnergyOption(id: "mind_planning", titleEn: "Planning", titleRu: "Планирование", category: .mind, icon: "calendar"),
        EnergyOption(id: "mind_writing", titleEn: "Writing", titleRu: "Письмо", category: .mind, icon: "pencil.line"),
        EnergyOption(id: "mind_observing", titleEn: "Observing", titleRu: "Наблюдение", category: .mind, icon: "binoculars.fill"),
        EnergyOption(id: "mind_questioning", titleEn: "Questioning", titleRu: "Вопрошание", category: .mind, icon: "questionmark.circle.fill"),
        EnergyOption(id: "mind_ordering", titleEn: "Ordering", titleRu: "Упорядочивание", category: .mind, icon: "square.grid.2x2.fill"),
        EnergyOption(id: "mind_remembering", titleEn: "Remembering", titleRu: "Воспоминание", category: .mind, icon: "clock.arrow.circlepath"),
        EnergyOption(id: "mind_letting_go", titleEn: "Letting Go", titleRu: "Отпускание", category: .mind, icon: "leaf.fill"),

        // HEART - Ways you felt and connected today
        EnergyOption(id: "heart_joy", titleEn: "Joy", titleRu: "Радость", category: .heart, icon: "face.smiling.fill"),
        EnergyOption(id: "heart_calm", titleEn: "Calm", titleRu: "Спокойствие", category: .heart, icon: "moon.zzz.fill"),
        EnergyOption(id: "heart_gratitude", titleEn: "Gratitude", titleRu: "Благодарность", category: .heart, icon: "hands.sparkles.fill"),
        EnergyOption(id: "heart_connection", titleEn: "Connection", titleRu: "Связь", category: .heart, icon: "person.2.fill"),
        EnergyOption(id: "heart_care", titleEn: "Care", titleRu: "Забота", category: .heart, icon: "heart.circle.fill"),
        EnergyOption(id: "heart_wonder", titleEn: "Wonder", titleRu: "Удивление", category: .heart, icon: "sparkles"),
        EnergyOption(id: "heart_trust", titleEn: "Trust", titleRu: "Доверие", category: .heart, icon: "lock.open.fill"),
        EnergyOption(id: "heart_vulnerability", titleEn: "Vulnerability", titleRu: "Уязвимость", category: .heart, icon: "heart.slash.fill"),
        EnergyOption(id: "heart_belonging", titleEn: "Belonging", titleRu: "Принадлежность", category: .heart, icon: "house.fill"),
        EnergyOption(id: "heart_peace", titleEn: "Peace", titleRu: "Мир", category: .heart, icon: "infinity")
    ]
    
    /// Option descriptions and examples
    static let optionDescriptions: [String: (description: String, examples: String)] = [
        // BODY
        "body_walking": ("Moving forward with your body in the world.", "city walk, nature walk, walking without a goal"),
        "body_physical_effort": ("Using strength and resistance.", "gym, home workout, carrying, manual work"),
        "body_stretching": ("Opening and releasing tension.", "stretching, yoga, mobility, slow warm-up"),
        "body_resting": ("Allowing the body to recover.", "good sleep, lying down, intentional break"),
        "body_breathing": ("Returning to your physical rhythm.", "breathing pause, calming breath, mindful inhale"),
        "body_touch": ("Feeling the world through contact.", "water, grass, sunlight, physical grounding"),
        "body_balance": ("Holding yourself steady and aware.", "slow movement, posture work, standing still"),
        "body_repetition": ("Doing simple physical actions with presence.", "cleaning, tidying, daily routines"),
        "body_warming": ("Feeling heat and comfort in the body.", "hot shower, sun exposure, warm drink"),
        "body_stillness": ("Being completely motionless for a moment.", "sitting quietly, body scan, silent pause"),
        
        // MIND
        "mind_focusing": ("Holding attention on one thing.", "reading, deep work, careful listening"),
        "mind_learning": ("Taking something new into the mind.", "studying, educational content, skill practice"),
        "mind_thinking": ("Actively processing ideas or situations.", "reflecting, problem-solving, mental exploration"),
        "mind_planning": ("Organising what comes next.", "structuring tasks, setting priorities"),
        "mind_writing": ("Turning thoughts into form.", "journaling, notes, drafting ideas"),
        "mind_observing": ("Noticing without interfering.", "watching people, noticing patterns, awareness"),
        "mind_questioning": ("Challenging assumptions.", "asking why, rethinking, curiosity moments"),
        "mind_ordering": ("Creating clarity and structure.", "organising files, simplifying, arranging ideas"),
        "mind_remembering": ("Returning to past experience consciously.", "reviewing the day, recalling a memory"),
        "mind_letting_go": ("Releasing mental tension.", "closing tasks, stopping overthinking, pause"),
        
        // HEART
        "heart_joy": ("Feeling lightness and warmth.", "laughter, playful moments, spontaneous happiness"),
        "heart_calm": ("Feeling settled and safe inside.", "quiet time, relaxation, emotional ease"),
        "heart_gratitude": ("Recognising something as valuable.", "appreciating a moment, feeling thankful"),
        "heart_connection": ("Feeling close to someone.", "meaningful talk, shared silence"),
        "heart_care": ("Giving attention and warmth.", "helping, supporting, caring for yourself"),
        "heart_wonder": ("Feeling awe or curiosity.", "noticing beauty, surprise, inspiration"),
        "heart_trust": ("Allowing openness without tension.", "relying on someone, emotional safety"),
        "heart_vulnerability": ("Allowing yourself to feel honestly.", "emotional openness, sincere sharing"),
        "heart_belonging": ("Feeling part of something.", "community, shared identity, feeling at home"),
        "heart_peace": ("Deep inner quiet.", "acceptance, emotional stillness")
    ]
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
    static let body: [String] = [
        "figure.run", "figure.walk", "figure.hiking", "figure.outdoor.cycle",
        "figure.pool.swim", "figure.yoga", "figure.dance", "figure.basketball",
        "figure.tennis", "figure.golf", "figure.skiing.downhill", "figure.climbing",
        "sportscourt.fill", "dumbbell.fill", "bicycle", "skateboard.fill",
        "soccerball", "football.fill", "baseball.fill", "volleyball.fill"
    ]

    static let mind: [String] = [
        "moon.zzz.fill", "bed.double.fill", "cup.and.saucer.fill", "leaf.fill",
        "drop.fill", "wind", "sparkles", "cloud.fill",
        "sun.max.fill", "umbrella.fill", "flame.fill", "snowflake",
        "bubble.left.and.bubble.right.fill", "heart.fill", "brain.head.profile", "eye.fill"
    ]

    static let heart: [String] = [
        "paintbrush.fill", "music.note", "book.fill", "gamecontroller.fill",
        "film.fill", "tv.fill", "headphones", "guitars.fill",
        "camera.fill", "photo.fill", "heart.fill", "star.fill",
        "gift.fill", "balloon.fill", "party.popper.fill", "birthday.cake.fill",
        "face.smiling.fill", "hands.clap.fill", "hand.thumbsup.fill", "pawprint.fill"
    ]

    static func icons(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return body
        case .mind: return mind
        case .heart: return heart
        }
    }
}
