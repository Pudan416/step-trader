import SwiftUI

// MARK: - Theme Environment Keys

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .night
    @Entry var resolvedAppTheme: ResolvedAppTheme = .night
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
