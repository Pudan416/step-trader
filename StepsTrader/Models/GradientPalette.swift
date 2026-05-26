import Foundation

enum GradientPalette: String, CaseIterable {
    case warmSunset   // gold → dark blue (original)
    case ocean        // teal → midnight blue
    case aurora       // soft violet → emerald
    case dusk         // warm cream → slate blue
    case dawn         // blush pink → dusty rose → deep indigo
    case ember        // vivid orange → crimson → indigo
    case horizon      // amber gold → teal → deep petrol

    var displayName: String {
        switch self {
        case .warmSunset: "Sunset"
        case .ocean:      "Ocean"
        case .aurora:     "Aurora"
        case .dusk:       "Dusk"
        case .dawn:       "Dawn"
        case .ember:      "Ember"
        case .horizon:    "Horizon"
        }
    }

    static func normalized(rawValue: String) -> GradientPalette {
        switch rawValue {
        case "roseGarden": .ocean
        default:           GradientPalette(rawValue: rawValue) ?? .warmSunset
        }
    }
}

enum GradientStyle: String, CaseIterable {
    case radial
    case linear
    case radialReversed
    case linearReversed
    case organic
    case mesh
    case angular

    var displayName: String {
        switch self {
        case .radial: "Radial"
        case .linear: "Linear"
        case .radialReversed: "Radial Reversed"
        case .linearReversed: "Linear Reversed"
        case .organic: "Organic"
        case .mesh: "Mesh"
        case .angular: "Angular"
        }
    }

    var isAnimated: Bool {
        self == .mesh || self == .angular
    }
}
