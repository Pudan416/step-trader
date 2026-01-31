import Foundation

// MARK: - Choice tab: past day snapshot (for history)
struct PastDaySnapshot: Codable, Equatable {
    var controlGained: Int
    var controlSpent: Int
    var activityIds: [String]
    var recoveryIds: [String]
    var joysIds: [String]
    var steps: Int
    var sleepHours: Double
    
    // Backward compatibility - old snapshots won't have steps/sleep
    init(controlGained: Int, controlSpent: Int, activityIds: [String], recoveryIds: [String], joysIds: [String], steps: Int = 0, sleepHours: Double = 0) {
        self.controlGained = controlGained
        self.controlSpent = controlSpent
        self.activityIds = activityIds
        self.recoveryIds = recoveryIds
        self.joysIds = joysIds
        self.steps = steps
        self.sleepHours = sleepHours
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controlGained = try container.decode(Int.self, forKey: .controlGained)
        controlSpent = try container.decode(Int.self, forKey: .controlSpent)
        activityIds = try container.decode([String].self, forKey: .activityIds)
        recoveryIds = try container.decode([String].self, forKey: .recoveryIds)
        joysIds = try container.decode([String].self, forKey: .joysIds)
        // Optional for backward compatibility
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
    }
}

// MARK: - Choice tab: one of four daily slots (category + option)
struct DayChoiceSlot: Codable, Equatable {
    var category: EnergyCategory?
    var optionId: String?
}

enum EnergyCategory: String, CaseIterable, Codable, Identifiable {
    case activity  // Activity (steps + movement activities)
    case recovery  // Recovery (sleep + recovery activities)
    case joys      // Joys (choice)
    
    var id: String { rawValue }
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
        // Activity
        EnergyOption(id: "activity_favourite_sport", titleEn: "Doing my favourite sport", titleRu: "Doing my favourite sport", category: .activity, icon: "sportscourt.fill"),
        EnergyOption(id: "activity_just_sports", titleEn: "Just doing sports", titleRu: "Just doing sports", category: .activity, icon: "figure.run"),
        EnergyOption(id: "activity_apple_watch_ring", titleEn: "Closing that Apple Watch ring", titleRu: "Closing that Apple Watch ring", category: .activity, icon: "applewatch"),
        EnergyOption(id: "activity_apple_watch_3_rings", titleEn: "Closing 3 Apple Watch rings", titleRu: "Closing 3 Apple Watch rings", category: .activity, icon: "circle.hexagongrid.fill"),
        EnergyOption(id: "activity_10k_steps", titleEn: "Hitting 10k steps", titleRu: "Hitting 10k steps", category: .activity, icon: "figure.walk"),
        EnergyOption(id: "activity_squatting", titleEn: "Squatting a bit", titleRu: "Squatting a bit", category: .activity, icon: "figure.strengthtraining.traditional"),
        EnergyOption(id: "activity_stretching", titleEn: "Stretching randomly", titleRu: "Stretching randomly", category: .activity, icon: "figure.flexibility"),
        EnergyOption(id: "activity_hanging_bar", titleEn: "Hanging from a bar", titleRu: "Hanging from a bar", category: .activity, icon: "figure.cooldown"),
        EnergyOption(id: "activity_dancing", titleEn: "Dancing alone or not alone", titleRu: "Dancing alone or not alone", category: .activity, icon: "figure.dance"),
        EnergyOption(id: "activity_carrying_heavy", titleEn: "Carrying something heavy", titleRu: "Carrying something heavy", category: .activity, icon: "figure.walk"),
        EnergyOption(id: "activity_stairs", titleEn: "Taking the stairs instead of the elevator", titleRu: "Taking the stairs instead of the elevator", category: .activity, icon: "figure.stairs"),
        EnergyOption(id: "activity_other", titleEn: "Something else", titleRu: "Something else", category: .activity, icon: "plus.circle.fill"),

        // Recovery
        EnergyOption(id: "recovery_sleeping_well", titleEn: "Sleeping well", titleRu: "Sleeping well", category: .recovery, icon: "moon.zzz.fill"),
        EnergyOption(id: "recovery_walking_mental", titleEn: "Walking for mental health", titleRu: "Walking for mental health", category: .recovery, icon: "figure.walk"),
        EnergyOption(id: "recovery_silence", titleEn: "Sitting in silence", titleRu: "Sitting in silence", category: .recovery, icon: "speaker.slash.fill"),
        EnergyOption(id: "recovery_hot_shower", titleEn: "Taking a hot shower", titleRu: "Taking a hot shower", category: .recovery, icon: "drop.fill"),
        EnergyOption(id: "recovery_slow_breathing", titleEn: "Slow breathing with closed eyes", titleRu: "Slow breathing with closed eyes", category: .recovery, icon: "wind"),
        EnergyOption(id: "recovery_eating_healthy", titleEn: "Eating as healthy as possible", titleRu: "Eating as healthy as possible", category: .recovery, icon: "leaf.fill"),
        EnergyOption(id: "recovery_alone", titleEn: "Being alone", titleRu: "Being alone", category: .recovery, icon: "person.fill"),
        EnergyOption(id: "recovery_with_someone", titleEn: "Being with someone", titleRu: "Being with someone", category: .recovery, icon: "person.2.fill"),
        EnergyOption(id: "recovery_good_talk", titleEn: "Having a good talk", titleRu: "Having a good talk", category: .recovery, icon: "bubble.left.and.bubble.right.fill"),
        EnergyOption(id: "recovery_fantasizing", titleEn: "Fantasizing", titleRu: "Fantasizing", category: .recovery, icon: "sparkles"),
        EnergyOption(id: "recovery_good_music", titleEn: "Listening to good music", titleRu: "Listening to good music", category: .recovery, icon: "music.note"),
        EnergyOption(id: "recovery_resting", titleEn: "Resting without a reason", titleRu: "Resting without a reason", category: .recovery, icon: "moon.zzz.fill"),
        EnergyOption(id: "recovery_other", titleEn: "Other", titleRu: "Other", category: .recovery, icon: "plus.circle.fill"),

        // Joys
        EnergyOption(id: "joys_favourite_hobby", titleEn: "Doing a favourite hobby", titleRu: "Doing a favourite hobby", category: .joys, icon: "paintbrush.fill"),
        EnergyOption(id: "joys_whatever", titleEn: "Doing whatever I feel like", titleRu: "Doing whatever I feel like", category: .joys, icon: "hand.thumbsup.fill"),
        EnergyOption(id: "joys_drawing", titleEn: "Drawing", titleRu: "Drawing", category: .joys, icon: "pencil"),
        EnergyOption(id: "joys_great_time", titleEn: "Having a great time", titleRu: "Having a great time", category: .joys, icon: "star.fill"),
        EnergyOption(id: "joys_family", titleEn: "Seeing my family", titleRu: "Seeing my family", category: .joys, icon: "house.fill"),
        EnergyOption(id: "joys_friends", titleEn: "Being with friends", titleRu: "Being with friends", category: .joys, icon: "person.2.fill"),
        EnergyOption(id: "joys_pet", titleEn: "Playing with a pet", titleRu: "Playing with a pet", category: .joys, icon: "pawprint.fill"),
        EnergyOption(id: "joys_tasty", titleEn: "Eating something tasty", titleRu: "Eating something tasty", category: .joys, icon: "fork.knife"),
        EnergyOption(id: "joys_singing", titleEn: "Singing", titleRu: "Singing", category: .joys, icon: "music.mic"),
        EnergyOption(id: "joys_something_fun", titleEn: "Doing something fun", titleRu: "Doing something fun", category: .joys, icon: "face.smiling.fill"),
        EnergyOption(id: "joys_coffee_tea", titleEn: "Drinking coffee or tea slowly", titleRu: "Drinking coffee or tea slowly", category: .joys, icon: "cup.and.saucer.fill"),
        EnergyOption(id: "joys_alcohol", titleEn: "Drinking some alcohol", titleRu: "Drinking some alcohol", category: .joys, icon: "wineglass.fill"),
        EnergyOption(id: "joys_nothing", titleEn: "Doing nothing on purpose", titleRu: "Doing nothing on purpose", category: .joys, icon: "clock.fill"),
        EnergyOption(id: "joys_one_page", titleEn: "Reading one page", titleRu: "Reading one page", category: .joys, icon: "book.fill"),
        EnergyOption(id: "joys_pretty_picture", titleEn: "Taking a pretty picture", titleRu: "Taking a pretty picture", category: .joys, icon: "camera.fill"),
        EnergyOption(id: "joys_cooking", titleEn: "Cooking something simple", titleRu: "Cooking something simple", category: .joys, icon: "frying.pan.fill"),
        EnergyOption(id: "joys_bored", titleEn: "Being bored", titleRu: "Being bored", category: .joys, icon: "cloud.fill"),
        EnergyOption(id: "joys_laughing", titleEn: "Laughing at something stupid", titleRu: "Laughing at something stupid", category: .joys, icon: "face.smiling.fill"),
        EnergyOption(id: "joys_other", titleEn: "Other", titleRu: "Other", category: .joys, icon: "plus.circle.fill")
    ]
    
    /// IDs of options that open "Add custom activity" sheet
    static let otherOptionIds: Set<String> = ["activity_other", "recovery_other", "joys_other"]
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
    
    static let recovery: [String] = [
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
        case .recovery: return recovery
        case .joys: return joys
        }
    }
}
