import Foundation
import SwiftUI

/// Visual poster styles for the day canvas share/export image.
/// Each style wraps the same canvas content with a different layout.
enum PosterStyle: String, CaseIterable, Codable, Identifiable {
    case museum      // cream border, serif typography, thin separator lines
    case fullBleed   // canvas fills the frame, white text overlaid
    case framedDark  // black background, canvas inset with white border

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .museum:     return String(localized: "Museum", comment: "Poster style name")
        case .fullBleed:  return String(localized: "Full Bleed", comment: "Poster style name")
        case .framedDark: return String(localized: "Framed", comment: "Poster style name")
        }
    }

    var iconName: String {
        switch self {
        case .museum:     return "text.below.photo"
        case .fullBleed:  return "photo"
        case .framedDark: return "photo.artframe"
        }
    }

    /// Background color used to pad the poster to 9:16 for social media.
    var padColor: Color {
        switch self {
        case .museum:     return Color(red: 0.969, green: 0.961, blue: 0.925)
        case .fullBleed:  return .black
        case .framedDark: return .black
        }
    }

    /// The poster's native aspect ratio (width / height) from Figma sources.
    var nativeAspect: CGFloat {
        switch self {
        case .museum:     return 604.0 / 842.0
        case .fullBleed:  return 595.0 / 842.0
        case .framedDark: return 595.0 / 842.0
        }
    }
}
