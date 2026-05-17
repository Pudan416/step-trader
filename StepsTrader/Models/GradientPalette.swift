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
        case .warmSunset: return "Sunset"
        case .ocean:      return "Ocean"
        case .aurora:     return "Aurora"
        case .dusk:       return "Dusk"
        case .dawn:       return "Dawn"
        case .ember:      return "Ember"
        case .horizon:    return "Horizon"
        }
    }

    static func normalized(rawValue: String) -> GradientPalette {
        switch rawValue {
        case "roseGarden": return .ocean
        default:           return GradientPalette(rawValue: rawValue) ?? .warmSunset
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

    var displayName: String {
        switch self {
        case .radial: return "Radial"
        case .linear: return "Linear"
        case .radialReversed: return "Radial Reversed"
        case .linearReversed: return "Linear Reversed"
        case .organic: return "Organic"
        case .mesh: return "Mesh"
        }
    }
}
