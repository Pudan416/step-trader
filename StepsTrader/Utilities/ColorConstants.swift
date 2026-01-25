import SwiftUI

/// Centralized color constants for the app
/// Replaces hardcoded Color(red:green:blue:) values throughout the codebase
enum AppColors {
    // MARK: - Brand Colors
    static let brandPink = Color(red: 224/255, green: 130/255, blue: 217/255)
    
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
