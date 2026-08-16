import Foundation

enum RichFigureFamily: String, CaseIterable, Hashable {
    case circle, luminousOrganic, crystallineStar, rays, orbitalSpirograph
}

enum RichFillKind: String, CaseIterable, Hashable {
    case luminousGradient, nestedContours, orbitalLines
    case filamentField, outlineWithCore, layeredTranslucentMass
}

enum RichFigureDetailTier: Int, Hashable {
    case accent, medium, large
}

struct RichFigureStyleSpec: Hashable {
    let family: RichFigureFamily
    let fill: RichFillKind
    let primaryHex: String
    let secondaryHex: String?
    let geometrySeed: UInt64
    let animationPhase: Double
    let speedMultiplier: Double
    let detailTier: RichFigureDetailTier
    let glowIntensity: Double
    let particleEligible: Bool
}

struct RichFigurePreviewItem: Identifiable {
    let source: CanvasElement
    let style: RichFigureStyleSpec

    var id: UUID { source.id }
}
