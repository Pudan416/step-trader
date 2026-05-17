import SwiftUI

// MARK: - Semantic Text Styles

extension Text {
    func themedPrimary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textPrimary)
    }

    func themedSecondary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textSecondary)
    }

    func themedAccent(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.accentColor)
    }
}

extension AppTheme {
    var adaptivePrimaryText: Color { textPrimary }

    var adaptiveSecondaryText: Color {
        AppColors.Night.textSecondary.opacity(0.78)
    }

    var adaptiveMutedText: Color {
        AppColors.Night.textSecondary.opacity(0.55)
    }

    var adaptiveDividerColor: Color {
        textPrimary.opacity(0.18)
    }
}
