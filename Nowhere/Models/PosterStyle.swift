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
        case .museum:     String(localized: "Museum", comment: "Poster style name")
        case .fullBleed:  String(localized: "Full Bleed", comment: "Poster style name")
        case .framedDark: String(localized: "Framed", comment: "Poster style name")
        }
    }

    var iconName: String {
        switch self {
        case .museum:     "text.below.photo"
        case .fullBleed:  "photo"
        case .framedDark: "photo.artframe"
        }
    }
}
