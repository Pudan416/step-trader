import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Catalog of image names from Assets for daily energy categories.
/// One list per selection grid in the editor. Add the Image Set name here when adding a new image to Assets.
enum CanvasImageCatalog {

    static let body: [String] = [
        "body 1",
        "body 2",
        "body 3"
    ]

    static let mind: [String] = [
        "mind 1", "mind 2", "mind 3", "mind 4", "mind 5",
        "mind 6", "mind 7", "mind 8", "mind 9", "mind 10",
        "mind 11", "mind 12", "mind 13", "mind 14", "mind 15",
        "mind 16", "mind 17", "mind 18", "mind 19"
    ]

    static let heart: [String] = [
        "heart 1", "heart 2", "heart 3", "heart 4", "heart 5",
        "heart 6", "heart 7", "heart 8", "heart 9", "heart 10",
        "heart 11", "heart 12", "heart 13"
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
