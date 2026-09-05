import Foundation

/// Lab-only material axes for the app-native palette atlas. Every case is
/// expressed through the same GPU families used by Day Objects production.
enum DayObjectEditorialPreviewMaterial: String, CaseIterable, Hashable, Identifiable {
    case solid
    case translucentSolid
    case softMist
    case wideGradient
    case softOutline
    case hairlineOutline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .translucentSolid: "Translucent solid"
        case .softMist: "Soft mist"
        case .wideGradient: "Wide gradient"
        case .softOutline: "Soft outline"
        case .hairlineOutline: "Hairline outline"
        }
    }

    var family: DayObjectEditorialMaterialFamily {
        switch self {
        case .solid, .translucentSolid: .solid
        case .softMist: .mist
        case .wideGradient: .gradient
        case .softOutline, .hairlineOutline: .outline
        }
    }

    var colorCount: Int {
        switch self {
        case .solid, .translucentSolid, .softMist, .softOutline, .hairlineOutline: 1
        case .wideGradient: 2
        }
    }
}

enum DayObjectEditorialPreviewPlacement: String, CaseIterable, Hashable, Identifiable {
    case depthField
    case equalMedium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .depthField: "Depth field"
        case .equalMedium: "Equal medium"
        }
    }
}

/// The interactive Editorial Field variants exposed only inside Day Objects Lab.
/// Generative DNA gives each day one coherent visual envelope. The comparison
/// atlas intentionally mixes all six legacy preview formats for inspection.
enum DayObjectEditorialLabMaterialMode: String, CaseIterable, Hashable, Identifiable {
    case generativeDNA
    case mixed
    case solid
    case translucentSolid
    case softMist
    case wideGradient
    case softOutline
    case hairlineOutline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generativeDNA: "Generative DNA"
        case .mixed: "All formats (comparison)"
        case .solid: "Solid"
        case .translucentSolid: "Translucent solid"
        case .softMist: "Soft mist"
        case .wideGradient: "Wide gradient"
        case .softOutline: "Soft outline"
        case .hairlineOutline: "Hairline outline"
        }
    }

    var singleMaterial: DayObjectEditorialPreviewMaterial? {
        guard self != .generativeDNA, self != .mixed else { return nil }
        return DayObjectEditorialPreviewMaterial(rawValue: rawValue)
    }
}

struct DayObjectEditorialLabConfiguration: Equatable, Hashable {
    let materialMode: DayObjectEditorialLabMaterialMode
    let placement: DayObjectEditorialPreviewPlacement
}

struct DayObjectEditorialPreviewSpec: Equatable, Hashable, Identifiable {
    let index: Int
    let paletteCategory: ModernPaletteCategory
    let material: DayObjectEditorialPreviewMaterial
    let placement: DayObjectEditorialPreviewPlacement
    let dayKey: String

    var id: Int { index }
}

enum DayObjectEditorialPreviewCatalog {
    static let all: [DayObjectEditorialPreviewSpec] =
        DayObjectEditorialPreviewMaterial.allCases.enumerated().flatMap { materialIndex, material in
            DayObjectEditorialPreviewPlacement.allCases.enumerated().map { placementIndex, placement in
                let index = materialIndex * DayObjectEditorialPreviewPlacement.allCases.count
                    + placementIndex
                let categories = ModernPaletteCategory.allCases
                return DayObjectEditorialPreviewSpec(
                    index: index,
                    paletteCategory: categories[index % categories.count],
                    material: material,
                    placement: placement,
                    dayKey: String(format: "editorial-soft-review-%03d", index)
                )
            }
        }

    static func spec(at index: Int) -> DayObjectEditorialPreviewSpec? {
        all.indices.contains(index) ? all[index] : nil
    }
}
