import SwiftUI

/// Centralized color constants for the app
/// Replaces hardcoded Color(red:green:blue:) values throughout the codebase
enum AppColors {
    // MARK: - Brand Colors
    // Primary accent (yellow marker)
    static let brandPink = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)   // #FFD369
    
    // MARK: - Daylight Theme (Paper)
    // "This is not a light mode. This is a daytime version of resistance."
    // The screen is not your life. This is just a place to notice.
    enum Daylight {
        static let background = Color(red: 0xEE/255, green: 0xEE/255, blue: 0xEE/255)  // #EEEEEE
        static let backgroundSecondary = Color(red: 243/255, green: 244/255, blue: 246/255)
        static let backgroundTertiary = Color(red: 235/255, green: 236/255, blue: 240/255)
        
        static let textPrimary = Color(red: 0.08, green: 0.08, blue: 0.08)      // Near-black ink
        static let textSecondary = textPrimary
        static let textMuted = textPrimary
        
        static let accentPink = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)   // #FFD369
        static let stroke = Color(red: 0.12, green: 0.12, blue: 0.12)
        
        static let activity = textPrimary
        static let rest = textPrimary
        static let joys = textPrimary
    }
    
    // MARK: - Night Theme
    // Night and screens. Same yellow accent, different context.
    enum Night {
        static let background = Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)  // #222831
        static let backgroundSecondary = Color(red: 48/255, green: 48/255, blue: 58/255)
        static let backgroundTertiary = Color(red: 56/255, green: 56/255, blue: 66/255)
        
        static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.95)
        static let textSecondary = textPrimary
        static let textMuted = textPrimary
        
        static let accentPink = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)   // #FFD369
        static let accentPinkMuted = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255).opacity(0.6)
        
        static let stroke = Color(red: 0.25, green: 0.25, blue: 0.25)
        static let strokeLight = Color(red: 0.20, green: 0.20, blue: 0.20)
        
        static let activity = textPrimary
        static let rest = textPrimary
        static let joys = textPrimary
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
    
    // MARK: - Login View
    enum Login {
        static let background1 = Color(red: 0.08, green: 0.08, blue: 0.12)
        static let background2 = Color(red: 0.12, green: 0.10, blue: 0.18)
        static let background3 = Color(red: 0.08, green: 0.08, blue: 0.12)
        static let gradient1 = Color(red: 0.88, green: 0.51, blue: 0.85)
        static let gradient2 = Color(red: 0.65, green: 0.35, blue: 0.85)
    }
    
    // MARK: - Status View
    enum Status {
        static let chartGradient1 = Color(red: 0.4, green: 0.6, blue: 1.0)
        static let chartGradient2 = Color(red: 0.6, green: 0.4, blue: 0.95)
        
        // App-specific colors
        static let youtube = Color(red: 1, green: 0, blue: 0)
        static let linkedin = Color(red: 0, green: 0.47, blue: 0.71)
        static let duolingo = Color(red: 0.35, green: 0.8, blue: 0.2)
        static let bronze = Color(red: 205/255, green: 127/255, blue: 50/255)
    }
    
    // MARK: - Apps Page
    enum Apps {
        static let progressBase = Color(red: 0.88, green: 0.51, blue: 0.85)
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
    func themedBorder(_ theme: AppTheme, width: CGFloat = 1) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 12)
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
    /// Primary text — near-black ink, high contrast
    func themedPrimary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textPrimary)
    }
    
    /// Secondary text — still readable, not soft
    func themedSecondary(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.textSecondary)
    }
    
    /// Accent text — rebellious pink marker ink
    func themedAccent(_ theme: AppTheme) -> Text {
        self.foregroundColor(theme.accentColor)
    }
}

// MARK: - Resistance UI Components
/// Components that embody the exp philosophy:
/// - No gamification. No motivation. No self-improvement tone.
/// - Observation over instruction
/// - Invitation over pressure
/// - Empty states are allowed
/// - "Spending exp" is neutral, never framed as failure

struct ResistanceTag: View {
    let text: String
    let theme: AppTheme
    
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(theme.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .stroke(theme.accentColor, lineWidth: 1)
            )
    }
}

/// Hand-drawn underline effect for rebellious accent
struct PinkUnderline: View {
    let width: CGFloat
    let theme: AppTheme
    
    var body: some View {
        // Slightly imperfect line — like marker on paper
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: width, y: 2),
                control: CGPoint(x: width * 0.5, y: -1)
            )
        }
        .stroke(theme.accentColor, lineWidth: 2)
        .frame(width: width, height: 4)
    }
}

/// Divider for daylight theme — thin black stroke, not grey
struct ThemedDivider: View {
    let theme: AppTheme
    
    var body: some View {
        Rectangle()
            .fill(theme.stroke.opacity(theme.strokeOpacity))
            .frame(height: 1)
    }
}

/// Empty state view — "Empty states are allowed. Observation, not instruction."
struct EmptyStateView: View {
    let message: String
    let theme: AppTheme
    var subMessage: String? = nil  // Optional: "or don't", "you can skip this", "nothing breaks"
    
    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)
            
            if let sub = subMessage {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(theme.textSecondary.opacity(0.7))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
