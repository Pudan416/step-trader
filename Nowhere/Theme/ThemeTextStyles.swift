import SwiftUI

// MARK: - Semantic Text Styles

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
