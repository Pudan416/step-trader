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
    
    // MARK: - Night Theme
    // Night and screens. Same yellow accent, different context.
    enum Night {
        static let background = Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)  // #222831
        static let backgroundSecondary = Color(red: 48/255, green: 48/255, blue: 58/255)

        static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.95)
        /// Intentional alias of `textPrimary` — hierarchy comes from opacity
        /// at the call site, not a separate base color.
        static let textSecondary = textPrimary

        static let stroke = Color(red: 0.25, green: 0.25, blue: 0.25)
        
        static let body = Color(red: 0.45, green: 0.72, blue: 0.55)  // #73B88C lifted forest
        static let mind = Color(red: 0.50, green: 0.65, blue: 0.85)      // #80A6D9 lifted slate blue
        static let heart = Color(red: 0.90, green: 0.62, blue: 0.40)      // #E69E66 lifted amber
    }
    
    // MARK: - PayGate Background Styles
    enum PayGate {
        static let midnight1 = Color(red: 0.05, green: 0.05, blue: 0.15)
        static let midnight2 = Color(red: 0.1, green: 0.05, blue: 0.2)
        static let midnight3 = Color(red: 0.15, green: 0.1, blue: 0.3)
        static let midnight4 = Color(red: 0.05, green: 0.02, blue: 0.1)
        
        static let aurora1 = Color(red: 0.05, green: 0.1, blue: 0.15)
        static let aurora2 = Color(red: 0.1, green: 0.3, blue: 0.4)
        static let aurora3 = Color(red: 0.2, green: 0.5, blue: 0.4)
        static let aurora4 = Color(red: 0.1, green: 0.2, blue: 0.3)
        
        static let sunset1 = Color(red: 0.15, green: 0.05, blue: 0.1)
        static let sunset2 = Color(red: 0.4, green: 0.15, blue: 0.2)
        static let sunset3 = Color(red: 0.6, green: 0.3, blue: 0.2)
        static let sunset4 = Color(red: 0.2, green: 0.05, blue: 0.1)
        
        static let ocean1 = Color(red: 0.02, green: 0.1, blue: 0.2)
        static let ocean2 = Color(red: 0.05, green: 0.2, blue: 0.35)
        static let ocean3 = Color(red: 0.1, green: 0.3, blue: 0.5)
        static let ocean4 = Color(red: 0.02, green: 0.08, blue: 0.15)
        
        static let neon1 = Color(red: 0.05, green: 0.02, blue: 0.1)
        static let neon2 = Color(red: 0.2, green: 0.05, blue: 0.3)
        static let neon3 = Color(red: 0.4, green: 0.1, blue: 0.5)
        static let neon4 = Color(red: 0.1, green: 0.02, blue: 0.15)
        
        static let minimal1 = Color(red: 0.08, green: 0.08, blue: 0.08)
        static let minimal2 = Color(red: 0.12, green: 0.12, blue: 0.12)
        static let minimal3 = Color(red: 0.1, green: 0.1, blue: 0.1)
        static let minimal4 = Color(red: 0.05, green: 0.05, blue: 0.05)
    }
}
