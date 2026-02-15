import SwiftUI

enum PayGateBackgroundStyle: String, CaseIterable, Identifiable {
    case midnight = "midnight"
    case aurora = "aurora"
    case sunset = "sunset"
    case ocean = "ocean"
    case neon = "neon"
    case minimal = "minimal"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .neon: return "Neon"
        case .minimal: return "Minimal"
        }
    }
    
    var displayNameRU: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .neon: return "Neon"
        case .minimal: return "Minimal"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .midnight:
            return [
                AppColors.PayGate.midnight1,
                AppColors.PayGate.midnight2,
                AppColors.PayGate.midnight3,
                AppColors.PayGate.midnight4
            ]
        case .aurora:
            return [
                AppColors.PayGate.aurora1,
                AppColors.PayGate.aurora2,
                AppColors.PayGate.aurora3,
                AppColors.PayGate.aurora4
            ]
        case .sunset:
            return [
                AppColors.PayGate.sunset1,
                AppColors.PayGate.sunset2,
                AppColors.PayGate.sunset3,
                AppColors.PayGate.sunset4
            ]
        case .ocean:
            return [
                AppColors.PayGate.ocean1,
                AppColors.PayGate.ocean2,
                AppColors.PayGate.ocean3,
                AppColors.PayGate.ocean4
            ]
        case .neon:
            return [
                AppColors.PayGate.neon1,
                AppColors.PayGate.neon2,
                AppColors.PayGate.neon3,
                AppColors.PayGate.neon4
            ]
        case .minimal:
            return [
                AppColors.PayGate.minimal1,
                AppColors.PayGate.minimal2,
                AppColors.PayGate.minimal3,
                AppColors.PayGate.minimal4
            ]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .midnight: return .purple
        case .aurora: return .cyan
        case .sunset: return .orange
        case .ocean: return .blue
        case .neon: return .pink
        case .minimal: return .white.opacity(0.3)
        }
    }
}
