import SwiftUI

extension EnergyCategory {
    /// The canonical accent color for this category.
    var color: Color {
        switch self {
        case .body:  return .green
        case .mind:  return .purple
        case .heart: return .orange
        }
    }

    /// A random palette color for new options (each addition gets a different tint).
    var defaultColorHex: String {
        CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
    }

    /// Localized display name for this category. Single source of truth used by
    /// RadialHoldMenu, MomentEntrySheet, and anywhere else the category appears
    /// in the UI.
    var displayName: String {
        switch self {
        case .body:  String(localized: "Body",  comment: "EnergyCategory display name")
        case .mind:  String(localized: "Mind",  comment: "EnergyCategory display name")
        case .heart: String(localized: "Heart", comment: "EnergyCategory display name")
        }
    }

    /// SF Symbol icon associated with this category.
    var iconName: String {
        switch self {
        case .body:  "figure.walk"
        case .mind:  "brain.head.profile"
        case .heart: "heart.fill"
        }
    }
}
