import SwiftUI

/// Resolved theme is always `.night` — the app uses a single dark canvas style.
enum ResolvedAppTheme: String {
    case night

    var isLight: Bool { false }
}

/// The app uses a single dark canvas style. Legacy stored values (`"system"`,
/// `"daylight"`, `"light"`) are all normalised to `.night`.
enum AppTheme: String, CaseIterable {
    case night

    var displayNameEn: String { "Night" }

    var colorScheme: ColorScheme? { .dark }

    var isLightTheme: Bool { false }

    func isLight(in scheme: ColorScheme?) -> Bool { false }

    var accentColor: Color { AppColors.brandAccent }

    var backgroundColor: Color { AppColors.Night.background }
    var backgroundSecondary: Color { AppColors.Night.backgroundSecondary }
    var textPrimary: Color { AppColors.Night.textPrimary }
    var textSecondary: Color { AppColors.Night.textSecondary }
    var stroke: Color { AppColors.Night.stroke }
    var strokeOpacity: Double { 0.15 }
    var bodyColor: Color { AppColors.Night.body }
    var mindColor: Color { AppColors.Night.mind }
    var heartColor: Color { AppColors.Night.heart }

    static func normalized(rawValue: String) -> AppTheme { .night }
}
