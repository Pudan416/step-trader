import SwiftUI

// MARK: - Theme Environment Keys

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .night
    @Entry var resolvedAppTheme: ResolvedAppTheme = .night
}

// MARK: - Themed View Modifiers

private struct ThemedModifier: ViewModifier {
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, theme.isLight(in: colorScheme) ? .daylight : .night)
            .environment(\.resolvedAppTheme, theme.isLight(in: colorScheme) ? .daylight : .night)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.isLight(in: colorScheme) ? AppColors.accentInk : AppColors.brandAccent)
    }
}

extension View {
    func themed(_ theme: AppTheme) -> some View {
        modifier(ThemedModifier(theme: theme))
    }


}
