import Foundation

/// Legacy catalog — all categories now use procedural generative shapes.
/// Kept as a no-op stub so callers that reference it still compile.
/// Safe to remove entirely once all `assetVariant` references are cleaned up.
enum CanvasImageCatalog {
    static let mind: [String] = []
    static let heart: [String] = []

    static func imageNames(for category: EnergyCategory) -> [String] { [] }

    static func hasImage(named name: String) -> Bool { false }
}
