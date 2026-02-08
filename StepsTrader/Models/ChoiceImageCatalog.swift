import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Каталог имён картинок из Assets для категорий дневной энергии.
/// Один список — одна сетка выбора в редакторе. Добавляй имя Image Set сюда при добавлении картинки в Assets.
enum GalleryImageCatalog {
    
    static let activity: [String] = [
        "activity_dancing",
        "activity_meal",
        "activity_overcome",
        "activity_risk",
        "activity_sex",
        "activity_sport",
        "activity_strong"
    ]
    
    static let creativity: [String] = [
        "creativity_curiosity",
        "creativity_doing_cash",
        "creativity_fantasizing",
        "creativity_general",
        "creativity_invisible",
        "creativity_museum",
        "creativity_observe"
    ]
    
    static let joys: [String] = [
        "joys_cringe",
        "joys_embrase",
        "joys_emotional",
        "joys_friends",
        "joys_happy_tears",
        "joys_in_love",
        "joys_kiss",
        "joys_love_myself",
        "joys_money",
        "joys_range",
        "joys_rebel",
        "joysl_junkfood"
    ]
    
    static func imageNames(for category: EnergyCategory) -> [String] {
        switch category {
        case .activity: return activity
        case .creativity: return creativity
        case .joys: return joys
        }
    }
    
    /// Проверка: есть ли в бандле картинка с таким именем (пробует exact, lowercase, capitalized).
    static func hasImage(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
            || UIImage(named: name.lowercased()) != nil
            || UIImage(named: name.capitalized) != nil
        #else
        return false
        #endif
    }
}
