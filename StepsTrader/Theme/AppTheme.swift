import SwiftUI

/// Interface appearance only; never changes the canvas recipe or palette.
enum ResolvedAppTheme: String {
    case daylight, night

    var isLight: Bool { self == .daylight }
}

enum AppTheme: String, CaseIterable {
    case system, daylight, night

    var displayNameEn: String {
        switch self { case .system: "System"; case .daylight: "Light"; case .night: "Dark" }
    }

    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .daylight: .light; case .night: .dark }
    }

    var isLightTheme: Bool { self == .daylight }

    func isLight(in scheme: ColorScheme?) -> Bool {
        self == .daylight || (self == .system && scheme == .light)
    }

    var accentColor: Color { isLightTheme ? Color(red: 0.43, green: 0.29, blue: 0.07) : AppColors.brandAccent }

    var backgroundColor: Color { isLightTheme ? Color(red: 0.96, green: 0.95, blue: 0.92) : AppColors.Night.background }
    var backgroundSecondary: Color { isLightTheme ? Color(white: 0.90) : AppColors.Night.backgroundSecondary }
    var textPrimary: Color { isLightTheme ? AppColors.graphite : AppColors.Night.textPrimary }
    var textSecondary: Color { isLightTheme ? Color(white: 0.28) : Color(white: 0.82) }
    var stroke: Color { textPrimary }
    var strokeOpacity: Double { 0.15 }
    var bodyColor: Color { AppColors.Night.body }
    var mindColor: Color { AppColors.Night.mind }
    var heartColor: Color { AppColors.Night.heart }

    static func normalized(rawValue: String) -> AppTheme {
        switch rawValue {
        case "light", "daylight": .daylight
        case "dark", "night": .night
        default: .system
        }
    }
}
