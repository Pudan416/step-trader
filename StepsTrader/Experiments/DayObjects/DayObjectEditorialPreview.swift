import Foundation

/// Lab-only material axes for the app-native palette atlas. Every case is
/// expressed through the same GPU families used by Day Objects production.
enum DayObjectEditorialPreviewMaterial: String, CaseIterable, Hashable, Identifiable {
    case solid
    case gradientTwo
    case gradientThree
    case paletteWash
    case depthPalette
    case glass
    case mist
    case luminous
    case softSphere
    case chromaticEdge
    case asymmetricPool
    case softOutline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .gradientTwo: "2 radial fields"
        case .gradientThree: "3 radial fields"
        case .paletteWash: "Palette wash"
        case .depthPalette: "Depth palette"
        case .glass: "Glass"
        case .mist: "Mist"
        case .luminous: "Luminous"
        case .softSphere: "Soft sphere"
        case .chromaticEdge: "Chromatic edge"
        case .asymmetricPool: "Asymmetric pool"
        case .softOutline: "Soft outline"
        }
    }

    var family: DayObjectEditorialMaterialFamily {
        switch self {
        case .solid, .depthPalette: .solid
        case .gradientTwo, .gradientThree, .paletteWash, .chromaticEdge, .asymmetricPool:
            .gradient
        case .glass: .glass
        case .mist: .mist
        case .luminous: .luminous
        case .softSphere: .sphere
        case .softOutline: .outline
        }
    }

    var colorCount: Int {
        switch self {
        case .solid, .depthPalette, .softOutline: 1
        case .gradientTwo, .chromaticEdge, .mist, .luminous, .softSphere: 2
        case .gradientThree, .paletteWash, .glass, .asymmetricPool: 3
        }
    }
}

struct DayObjectEditorialPreviewSpec: Equatable, Hashable, Identifiable {
    let index: Int
    let paletteCategory: ModernPaletteCategory
    let material: DayObjectEditorialPreviewMaterial
    let dayKey: String

    var id: Int { index }
}

enum DayObjectEditorialPreviewCatalog {
    static let all: [DayObjectEditorialPreviewSpec] =
        DayObjectEditorialPreviewMaterial.allCases.enumerated().flatMap { materialIndex, material in
            ModernPaletteCategory.allCases.enumerated().map { paletteIndex, category in
                let index = materialIndex * ModernPaletteCategory.allCases.count + paletteIndex
                return DayObjectEditorialPreviewSpec(
                    index: index,
                    paletteCategory: category,
                    material: material,
                    dayKey: String(format: "editorial-palette-atlas-%03d", index)
                )
            }
        }

    static func spec(at index: Int) -> DayObjectEditorialPreviewSpec? {
        all.indices.contains(index) ? all[index] : nil
    }
}
