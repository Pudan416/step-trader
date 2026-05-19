import SwiftUI

/// Visual shape types available for canvas elements.
/// Each shape bundles its own rendering style and movement behavior.
/// Pro users can assign any shape type to any energy category.
enum CanvasShapeType: String, CaseIterable, Codable, Identifiable {
    case circle      // dense gradient circles, overlapping, no deformation
    case snowflake   // symmetric rectmorph outline, Lissajous drift, morphing trail ghosts
    case rays        // Metal spotlight cones, edge-anchored, sweep oscillation
    case organicBlob // multi-layer organic contour morph + breathe — Pro only
    case blob        // (hidden) legacy noise-deformed closed path — kept for legacy data
    case spirograph  // (hidden) legacy hypotrochoid curves — kept for legacy data

    var id: String { rawValue }

    /// Only the shapes exposed in the picker UI.
    static var selectableCases: [CanvasShapeType] {
        [.circle, .snowflake, .rays, .organicBlob]
    }

    var displayName: String {
        switch self {
        case .circle:      String(localized: "Circle", comment: "Canvas shape type")
        case .snowflake:   String(localized: "Snowflake", comment: "Canvas shape type")
        case .rays:        String(localized: "Rays", comment: "Canvas shape type")
        case .organicBlob: String(localized: "Organic", comment: "Canvas shape type")
        case .blob:        String(localized: "Blob", comment: "Canvas shape type")
        case .spirograph:  String(localized: "Spirograph", comment: "Canvas shape type")
        }
    }

    var iconName: String {
        switch self {
        case .circle:      "circle.fill"
        case .snowflake:   "snowflake"
        case .rays:        "rays"
        case .organicBlob: "aqi.medium"
        case .blob:        "drop.fill"
        case .spirograph:  "circle.fill"
        }
    }

    static func defaultShape(for category: EnergyCategory) -> CanvasShapeType {
        switch category {
        case .body:  .circle
        case .mind:  .snowflake
        case .heart: .rays
        }
    }

    /// Reads the user's shape preference for a category, falling back to defaults.
    /// Migrates legacy `.blob` selections to `.circle`.
    static func resolved(for category: EnergyCategory) -> CanvasShapeType {
        let key: String = switch category {
        case .body:  SharedKeys.bodyCanvasShape
        case .mind:  SharedKeys.mindCanvasShape
        case .heart: SharedKeys.heartCanvasShape
        }
        guard let raw = UserDefaults.standard.string(forKey: key),
              let shape = CanvasShapeType(rawValue: raw) else {
            return defaultShape(for: category)
        }
        if shape == .blob || shape == .spirograph { return .circle }
        return shape
    }
}
