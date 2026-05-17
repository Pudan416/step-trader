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
}
