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

    var colorHexes: [String] {
        switch self {
        case .warmSunset: ["#FFBF65", "#FD8973", "#003A6C", "#002646"]
        case .ocean:      ["#7FDBDA", "#3A9FBF", "#1A4B6E", "#0B1E33"]
        case .aurora:     ["#C4B5FD", "#7C6FBF", "#1F6E5C", "#0F1B2D"]
        case .dusk:       ["#EEDDC9", "#C0AC98", "#5E7282", "#384856"]
        case .dawn:       ["#EBBFC8", "#B87A92", "#4A3568", "#181430"]
        case .ember:      ["#F07838", "#D04428", "#2E1858", "#0C0A22"]
        case .horizon:    ["#D0A440", "#2898A8", "#105868", "#0A2832"]
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
