import Foundation

enum EnergyDefaults {
    static let maxBaseEnergy: Int = 100
    static let maxSelectionsPerCategory: Int = 4
    
    static let sleepTargetHours: Double = 8
    static let sleepMaxPoints: Int = 20
    static let assumedSleepPoints: Int = 10
    static let stepsTarget: Double = 10_000
    static let stepsMaxPoints: Int = 20
    
    static let selectionPoints: Int = 5

    static let coreOptionIdsOrdered: [String] = [
        "body_walking", "body_stretching", "body_physical_effort", "body_resting",
        "mind_focusing", "mind_learning", "mind_planning", "mind_screen_detox",
        "heart_joy", "heart_gratitude", "heart_connection", "heart_calm"
    ]

    static let coreOptionIds: Set<String> = Set(coreOptionIdsOrdered)

    static var coreOptions: [EnergyOption] {
        let byId = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        return coreOptionIdsOrdered.compactMap { byId[$0] }
    }

    static let options: [EnergyOption] = [
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
        EnergyOption(id: "body_healing", titleEn: "Healing", titleRu: "Исцеление", category: .body, icon: "cross.case.fill"),

        EnergyOption(id: "mind_focusing", titleEn: "Focusing", titleRu: "Фокусировка", category: .mind, icon: "eye.fill"),
        EnergyOption(id: "mind_learning", titleEn: "Learning", titleRu: "Обучение", category: .mind, icon: "book.fill"),
        EnergyOption(id: "mind_thinking", titleEn: "Thinking", titleRu: "Размышление", category: .mind, icon: "brain.head.profile"),
        EnergyOption(id: "mind_planning", titleEn: "Planning", titleRu: "Планирование", category: .mind, icon: "calendar"),
        EnergyOption(id: "mind_writing", titleEn: "Writing", titleRu: "Письмо", category: .mind, icon: "pencil.line"),
        EnergyOption(id: "mind_observing", titleEn: "Observing", titleRu: "Наблюдение", category: .mind, icon: "binoculars.fill"),
        EnergyOption(id: "mind_questioning", titleEn: "Questioning", titleRu: "Вопрошание", category: .mind, icon: "questionmark.circle.fill"),
        EnergyOption(id: "mind_ordering", titleEn: "Ordering", titleRu: "Упорядочивание", category: .mind, icon: "square.grid.2x2.fill"),
        EnergyOption(id: "mind_remembering", titleEn: "Remembering", titleRu: "Воспоминание", category: .mind, icon: "clock.arrow.circlepath"),
        EnergyOption(id: "mind_screen_detox", titleEn: "Screen Detoxing", titleRu: "Экранный детокс", category: .mind, icon: "iphone.slash"),

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
    
    static func description(for optionId: String) -> String {
        let fallback = optionDescriptions[optionId]?.description ?? ""
        let key = "option.description.\(optionId)"
        return Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func examples(for optionId: String) -> String {
        let fallback = optionDescriptions[optionId]?.examples ?? ""
        let key = "option.examples.\(optionId)"
        return Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    static let optionDescriptions: [String: (description: String, examples: String)] = [
        "body_walking": ("Moving forward with your body in the world.", "city walk, nature walk, walking without a goal"),
        "body_physical_effort": ("Using strength and resistance.", "gym, home workout, manual work"),
        "body_stretching": ("Opening and releasing tension.", "stretching, yoga, mobility, slow warm-up"),
        "body_resting": ("Allowing the body to recover.", "good sleep, lying down, intentional break, power nap"),
        "body_breathing": ("Returning to your physical rhythm.", "breathing pause, calming breath, mindful inhale"),
        "body_touch": ("Feeling the world through contact.", "water, grass, sunlight, physical grounding"),
        "body_balance": ("Finding equilibrium and coordination.", "yoga, balance exercises, standing on one leg, tai chi"),
        "body_healing": ("Taking care of your body through medical attention.", "visiting a doctor, taking medication, therapy, antidepressants"),
        "body_repetition": ("Doing simple physical actions with presence.", "cleaning, tidying, daily routines"),
        "body_warming": ("Feeling heat and comfort in the body.", "hot shower, sun exposure, warm drink"),
        "body_stillness": ("Being completely motionless for a moment.", "sitting quietly, body scan, silent pause"),
        
        "mind_focusing": ("Holding attention on one thing.", "reading, deep work, careful listening"),
        "mind_learning": ("Taking something new into the mind.", "studying, educational content, skill practice"),
        "mind_thinking": ("Actively processing ideas or situations.", "reflecting, problem-solving, mental exploration"),
        "mind_planning": ("Organising what comes next.", "structuring tasks, setting priorities, looking for a job"),
        "mind_writing": ("Turning thoughts into form.", "journaling, notes, drafting ideas"),
        "mind_observing": ("Noticing without interfering.", "watching people, noticing patterns, awareness"),
        "mind_questioning": ("Challenging assumptions.", "asking why, rethinking, curiosity moments"),
        "mind_ordering": ("Creating clarity and structure.", "organising files, simplifying, arranging ideas"),
        "mind_remembering": ("Returning to a past moment consciously.", "sitting on a bench, reviewing the day, recalling a memory"),
        "mind_screen_detox": ("A day with minimal screen time.", "phone untouched, no scrolling, present in the moment"),
        
        "heart_joy": ("Feeling lightness and warmth.", "laughter, playful moments, spontaneous happiness"),
        "heart_calm": ("Feeling settled and safe inside.", "quiet time, relaxation, emotional ease"),
        "heart_gratitude": ("Recognising something as valuable.", "appreciating a moment, feeling thankful"),
        "heart_connection": ("Feeling close to someone.", "meaningful talk, shared silence"),
        "heart_care": ("Giving attention and warmth.", "helping, supporting, caring for yourself"),
        "heart_wonder": ("Feeling awe or curiosity.", "noticing beauty, surprise, inspiration"),
        "heart_trust": ("Allowing openness without tension.", "relying on someone, emotional safety"),
        "heart_vulnerability": ("Allowing yourself to feel honestly.", "emotional openness, sincere sharing"),
        "heart_belonging": ("Feeling part of something.", "community, shared identity, feeling at home"),
        "heart_peace": ("Deep inner quiet.", "acceptance of self, emotional stillness")
    ]
}

enum DayEndOptions {
    static let minuteStep: Int = 15

    static var allowedMinutes: [Int] {
        var result: [Int] = []
        for m in stride(from: 21 * 60, to: 24 * 60, by: minuteStep) { result.append(m) }
        for m in stride(from: 0, through: 3 * 60, by: minuteStep) { result.append(m) }
        return result
    }

    static func nearestAllowed(to current: Int) -> Int {
        let allowed = allowedMinutes
        let normalized = ((current % (24 * 60)) + (24 * 60)) % (24 * 60)
        return allowed.min { lhs, rhs in
            wrappedDistance(from: normalized, to: lhs) < wrappedDistance(from: normalized, to: rhs)
        } ?? (23 * 60)
    }

    private static func wrappedDistance(from a: Int, to b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 24 * 60 - d)
    }
}

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
