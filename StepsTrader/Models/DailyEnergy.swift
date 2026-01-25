import Foundation

enum EnergyCategory: String, CaseIterable, Codable {
    case recovery
    case activity
    case joy
}

struct EnergyOption: Identifiable, Codable, Equatable {
    let id: String
    let titleEn: String
    let titleRu: String
    let category: EnergyCategory
    
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
        EnergyOption(id: "recovery_meditation", titleEn: "Meditation", titleRu: "Медитация", category: .recovery),
        EnergyOption(id: "recovery_breathwork", titleEn: "Breathwork", titleRu: "Дыхательные практики", category: .recovery),
        EnergyOption(id: "recovery_stretching", titleEn: "Stretching", titleRu: "Растяжка", category: .recovery),
        EnergyOption(id: "recovery_nap", titleEn: "Power nap", titleRu: "Дневной сон", category: .recovery),
        EnergyOption(id: "recovery_journaling", titleEn: "Journaling", titleRu: "Дневник", category: .recovery),
        EnergyOption(id: "recovery_tea", titleEn: "Herbal tea", titleRu: "Травяной чай", category: .recovery),
        
        EnergyOption(id: "activity_workout", titleEn: "Workout", titleRu: "Тренировка", category: .activity),
        EnergyOption(id: "activity_sauna", titleEn: "Sauna", titleRu: "Сауна", category: .activity),
        EnergyOption(id: "activity_dance", titleEn: "Dance", titleRu: "Танцы", category: .activity),
        EnergyOption(id: "activity_swim", titleEn: "Swimming", titleRu: "Плавание", category: .activity),
        EnergyOption(id: "activity_yoga", titleEn: "Yoga", titleRu: "Йога", category: .activity),
        EnergyOption(id: "activity_walk", titleEn: "Long walk", titleRu: "Долгая прогулка", category: .activity),
        
        EnergyOption(id: "joy_family", titleEn: "Time with loved ones", titleRu: "Время с близкими", category: .joy),
        EnergyOption(id: "joy_hobby", titleEn: "Hobby time", titleRu: "Хобби", category: .joy),
        EnergyOption(id: "joy_good_deed", titleEn: "Good deed", titleRu: "Хороший поступок", category: .joy),
        EnergyOption(id: "joy_creativity", titleEn: "Creativity", titleRu: "Творчество", category: .joy),
        EnergyOption(id: "joy_nature", titleEn: "Nature break", titleRu: "Природа", category: .joy),
        EnergyOption(id: "joy_social", titleEn: "Social connection", titleRu: "Общение", category: .joy)
    ]
}
