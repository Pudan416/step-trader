import SwiftUI

// MARK: - Theme Environment Keys

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .night
}

private struct ResolvedAppThemeKey: EnvironmentKey {
    static let defaultValue: ResolvedAppTheme = .night
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }

    var resolvedAppTheme: ResolvedAppTheme {
        get { self[ResolvedAppThemeKey.self] }
        set { self[ResolvedAppThemeKey.self] = newValue }
    }
}

// MARK: - Themed View Modifiers

private struct ThemedModifier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .environment(\.appTheme, theme)
            .environment(\.resolvedAppTheme, .night)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func themed(_ theme: AppTheme) -> some View {
        modifier(ThemedModifier(theme: theme))
    }

    func themedBackground(_ theme: AppTheme) -> some View {
        self.background(theme.backgroundColor)
    }

    func themedSecondaryBackground(_ theme: AppTheme) -> some View {
        self.background(theme.backgroundSecondary)
    }

    func themedBorder(
        _ theme: AppTheme,
        width: CGFloat = 1,
        cornerRadius: CGFloat = 12
    ) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(theme.stroke.opacity(theme.strokeOpacity), lineWidth: width)
        )
    }
}
