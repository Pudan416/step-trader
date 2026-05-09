import SwiftUI

/// Centralized color constants for the app
/// Replaces hardcoded Color(red:green:blue:) values throughout the codebase
enum AppColors {
    // MARK: - Brand Colors
    /// Primary accent — gold marker.
    static let brandAccent = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)   // #FFD369

    /// Hex string fallback for the brand accent. Use this anywhere a string-typed
    /// hex literal is expected (e.g. palette `randomElement() ?? AppColors.goldFallbackHex`).
    ///
    /// Hex string convention used throughout this codebase:
    /// - 6-char `#RRGGBB`  (no alpha)
    /// - 8-char `#AARRGGBB` (Apple/Cocoa convention — alpha-FIRST)
    /// CSS uses alpha-LAST (`#RRGGBBAA`) — do not paste CSS hex strings without
    /// reordering. The 8-char parser in `Color(hex:)` (CanvasElement.swift)
    /// expects ARGB.
    static let goldFallbackHex = "#FFD369"
    
    // MARK: - Daylight Theme (Paper)
    // "This is not a light mode. This is a daytime version of resistance."
    // The screen is not your life. This is just a place to notice.
    enum Daylight {
        static let background = Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF2/255)  // #F2F2F2
        static let backgroundSecondary = Color(red: 243/255, green: 244/255, blue: 246/255)

        static let textPrimary = Color(red: 0.08, green: 0.08, blue: 0.08)
        /// Intentional alias of `textPrimary`. The Daylight philosophy avoids
        /// soft greys for body text — visual hierarchy is produced by per-call-site
        /// opacity (see `AppTheme.adaptiveSecondaryText` / `adaptiveMutedText`),
        /// not by a separate base color.
        static let textSecondary = textPrimary

        static let stroke = Color(red: 0.12, green: 0.12, blue: 0.12)
        
        static let body = Color(red: 0.30, green: 0.56, blue: 0.42)   // #4D8F6B muted forest
        static let mind = Color(red: 0.32, green: 0.46, blue: 0.65)      // #5275A6 muted slate blue
        static let heart = Color(red: 0.78, green: 0.48, blue: 0.30)      // #C77A4D muted amber
    }
    
    // MARK: - Night Theme
    // Night and screens. Same yellow accent, different context.
    enum Night {
        static let background = Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)  // #222831
        static let backgroundSecondary = Color(red: 48/255, green: 48/255, blue: 58/255)

        static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.95)
        /// Intentional alias of `textPrimary`. See `AppColors.Daylight.textSecondary`
        /// for rationale — hierarchy comes from opacity at the call site, not a
        /// separate base color.
        static let textSecondary = textPrimary

        static let stroke = Color(red: 0.25, green: 0.25, blue: 0.25)
        
        static let body = Color(red: 0.45, green: 0.72, blue: 0.55)  // #73B88C lifted forest
        static let mind = Color(red: 0.50, green: 0.65, blue: 0.85)      // #80A6D9 lifted slate blue
        static let heart = Color(red: 0.90, green: 0.62, blue: 0.40)      // #E69E66 lifted amber
    }
    
    // MARK: - PayGate Background Styles
    enum PayGate {
        // Midnight
        static let midnight1 = Color(red: 0.05, green: 0.05, blue: 0.15)
        static let midnight2 = Color(red: 0.1, green: 0.05, blue: 0.2)
        static let midnight3 = Color(red: 0.15, green: 0.1, blue: 0.3)
        static let midnight4 = Color(red: 0.05, green: 0.02, blue: 0.1)
        
        // Aurora
        static let aurora1 = Color(red: 0.05, green: 0.1, blue: 0.15)
        static let aurora2 = Color(red: 0.1, green: 0.3, blue: 0.4)
        static let aurora3 = Color(red: 0.2, green: 0.5, blue: 0.4)
        static let aurora4 = Color(red: 0.1, green: 0.2, blue: 0.3)
        
        // Sunset
        static let sunset1 = Color(red: 0.15, green: 0.05, blue: 0.1)
        static let sunset2 = Color(red: 0.4, green: 0.15, blue: 0.2)
        static let sunset3 = Color(red: 0.6, green: 0.3, blue: 0.2)
        static let sunset4 = Color(red: 0.2, green: 0.05, blue: 0.1)
        
        // Ocean
        static let ocean1 = Color(red: 0.02, green: 0.1, blue: 0.2)
        static let ocean2 = Color(red: 0.05, green: 0.2, blue: 0.35)
        static let ocean3 = Color(red: 0.1, green: 0.3, blue: 0.5)
        static let ocean4 = Color(red: 0.02, green: 0.08, blue: 0.15)
        
        // Neon
        static let neon1 = Color(red: 0.05, green: 0.02, blue: 0.1)
        static let neon2 = Color(red: 0.2, green: 0.05, blue: 0.3)
        static let neon3 = Color(red: 0.4, green: 0.1, blue: 0.5)
        static let neon4 = Color(red: 0.1, green: 0.02, blue: 0.15)
        
        // Minimal
        static let minimal1 = Color(red: 0.08, green: 0.08, blue: 0.08)
        static let minimal2 = Color(red: 0.12, green: 0.12, blue: 0.12)
        static let minimal3 = Color(red: 0.1, green: 0.1, blue: 0.1)
        static let minimal4 = Color(red: 0.05, green: 0.05, blue: 0.05)
    }
}

// MARK: - Theme Environment Key
/// Use @Environment(\.appTheme) to access current theme in any view
private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Themed View Modifiers
extension View {
    /// Apply theme to a view hierarchy
    func themed(_ theme: AppTheme) -> some View {
        self
            .environment(\.appTheme, theme)
            .preferredColorScheme(theme.colorScheme)
    }
    
    /// Background for main content areas — off-white paper in daylight
    func themedBackground(_ theme: AppTheme) -> some View {
        self.background(theme.backgroundColor)
    }
    
    /// Secondary background for grouped content — no shadows, just different paper tone
    func themedSecondaryBackground(_ theme: AppTheme) -> some View {
        self.background(theme.backgroundSecondary)
    }
    
    /// Stroke border — thin black lines for separation (daylight philosophy: no shadows, no soft cards)
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

// MARK: - Semantic Text Styles
/// Text styles that follow the Daylight theme philosophy:
/// - High-contrast, printed, factual
/// - No soft greys for main content
/// - Text should feel printed, not digital
extension Text {
    /// Primary text — near-black, high contrast
    func themedPrimary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textPrimary)
    }
    
    /// Secondary text — still readable, not soft
    func themedSecondary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textSecondary)
    }
    
    /// Accent text — gold marker.
    func themedAccent(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.accentColor)
    }
}

extension AppTheme {
    var adaptivePrimaryText: Color {
        textPrimary
    }

    var adaptiveSecondaryText: Color {
        textSecondary.opacity(isLightTheme ? 0.72 : 0.78)
    }

    var adaptiveMutedText: Color {
        textSecondary.opacity(isLightTheme ? 0.5 : 0.55)
    }

    var adaptiveDividerColor: Color {
        textPrimary.opacity(isLightTheme ? 0.12 : 0.18)
    }
}

