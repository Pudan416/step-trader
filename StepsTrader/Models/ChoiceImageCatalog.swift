import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Catalog of image names from Assets for daily energy categories.
/// One list per selection grid in the editor. Add the Image Set name here when adding a new image to Assets.
enum GalleryImageCatalog {

    static let body: [String] = [
        "body 1",
        "body 2",
        "body 3"
    ]

    static let mind: [String] = [
        "mind 1"
    ]

    static let heart: [String] = [
        "heart_cringe",
        "heart_embrase",
        "heart_emotional",
        "heart_friends",
        "heart_happy_tears",
        "heart_in_love",
        "heart_kiss",
        "heart_love_myself",
        "heart_range",
        "heart_rebel",
        "heart_junkfood"
    ]

    static func imageNames(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return body
        case .mind: return mind
        case .heart: return heart
        }
    }

    /// Check if bundle contains an image with this name (tries exact, lowercase, capitalized).
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
