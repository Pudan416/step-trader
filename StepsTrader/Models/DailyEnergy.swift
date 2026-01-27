import Foundation

enum EnergyCategory: String, CaseIterable, Codable, Identifiable {
    case move   // Move (activity - steps + movement activities)
    case reboot // Reboot (recovery - sleep + recovery activities)
    case joy    // Choice
    
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
        // Move (activity - steps + movement)
        EnergyOption(id: "move_moved", titleEn: "Moved a bit", titleRu: "Немного подвигался", category: .move, icon: "figure.walk"),
        EnergyOption(id: "move_outside", titleEn: "Went outside", titleRu: "Вышел на улицу", category: .move, icon: "sun.max.fill"),
        EnergyOption(id: "move_workout", titleEn: "Workout", titleRu: "Тренировка", category: .move, icon: "figure.run"),
        EnergyOption(id: "move_walk", titleEn: "Long walk", titleRu: "Долгая прогулка", category: .move, icon: "figure.walk.circle.fill"),
        EnergyOption(id: "move_yoga", titleEn: "Yoga", titleRu: "Йога", category: .move, icon: "figure.yoga"),
        EnergyOption(id: "move_swim", titleEn: "Swimming", titleRu: "Плавание", category: .move, icon: "figure.pool.swim"),
        EnergyOption(id: "move_cycle", titleEn: "Cycling", titleRu: "Велосипед", category: .move, icon: "figure.outdoor.cycle"),
        EnergyOption(id: "move_dance", titleEn: "Dance", titleRu: "Танцы", category: .move, icon: "figure.dance"),
        EnergyOption(id: "move_sauna", titleEn: "Sauna", titleRu: "Сауна", category: .move, icon: "thermometer.sun.fill"),
        
        // Reboot (recovery - sleep + recovery activities)
        EnergyOption(id: "reboot_slept", titleEn: "Slept enough", titleRu: "Выспался", category: .reboot, icon: "moon.zzz.fill"),
        EnergyOption(id: "reboot_stretch", titleEn: "Stretching", titleRu: "Растяжка", category: .reboot, icon: "figure.flexibility"),
        EnergyOption(id: "reboot_meditation", titleEn: "Meditation", titleRu: "Медитация", category: .reboot, icon: "brain.head.profile"),
        EnergyOption(id: "reboot_nap", titleEn: "Power nap", titleRu: "Дневной сон", category: .reboot, icon: "bed.double.fill"),
        EnergyOption(id: "reboot_breathwork", titleEn: "Breathwork", titleRu: "Дыхательные практики", category: .reboot, icon: "wind"),
        EnergyOption(id: "reboot_journaling", titleEn: "Journaling", titleRu: "Дневник", category: .reboot, icon: "book.closed.fill"),
        EnergyOption(id: "reboot_tea", titleEn: "Herbal tea", titleRu: "Травяной чай", category: .reboot, icon: "cup.and.saucer.fill"),
        EnergyOption(id: "reboot_massage", titleEn: "Massage", titleRu: "Массаж", category: .reboot, icon: "hand.raised.fill"),
        
        // Choice
        EnergyOption(id: "joy_wanted", titleEn: "Did what I wanted", titleRu: "Сделал то, что хотел", category: .joy, icon: "hand.thumbsup.fill"),
        EnergyOption(id: "joy_pleasure", titleEn: "Chose pleasure", titleRu: "Выбрал удовольствие", category: .joy, icon: "heart.fill"),
        EnergyOption(id: "joy_wasted", titleEn: "Wasted time. On purpose.", titleRu: "Потратил время. Намеренно.", category: .joy, icon: "clock.fill"),
        EnergyOption(id: "joy_hobby", titleEn: "Hobby time", titleRu: "Хобби", category: .joy, icon: "paintbrush.fill"),
        EnergyOption(id: "joy_creativity", titleEn: "Creativity", titleRu: "Творчество", category: .joy, icon: "paintpalette.fill"),
        EnergyOption(id: "joy_social", titleEn: "Social connection", titleRu: "Общение", category: .joy, icon: "person.2.fill"),
        EnergyOption(id: "joy_family", titleEn: "Time with loved ones", titleRu: "Время с близкими", category: .joy, icon: "house.fill"),
        EnergyOption(id: "joy_music", titleEn: "Music", titleRu: "Музыка", category: .joy, icon: "music.note"),
        EnergyOption(id: "joy_read", titleEn: "Reading", titleRu: "Чтение", category: .joy, icon: "book.fill"),
        EnergyOption(id: "joy_game", titleEn: "Gaming", titleRu: "Игры", category: .joy, icon: "gamecontroller.fill"),
        EnergyOption(id: "joy_food", titleEn: "Good meal", titleRu: "Хорошая еда", category: .joy, icon: "fork.knife"),
        EnergyOption(id: "joy_nature", titleEn: "Nature time", titleRu: "Время на природе", category: .joy, icon: "leaf.fill")
    ]
}
