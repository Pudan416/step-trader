import Foundation

/// Frozen native parameters rather than references to an evolving palette.
/// This model is deliberately opt-in until the shared Metal path is validated.
struct NativeAtlasRecipe: Codable, Equatable {
    struct Actor: Codable, Equatable {
        let eventID: String
        let presetID: String
        let materialID: MetalShapeMaterial
        let seedHex: String
        let geometry: MetalShapeGenomeUniforms
        let material: MetalShapeMaterialUniforms
        let position: SIMD2<Float>
        let size: Float
        let rotation: Float
        let slot: Int
    }

    var schemaVersion: Int
    let generatorVersion: String
    let catalogVersion: String
    let seedHex: String
    let trajectory: Int
    let sizeRhythm: Int
    let spacing: Float
    let background: SIMD4<Float>
    var glitchType: Int
    var intersectionType: Int
    var intersectionStrength: Float
    var glitchStrength: Float? = nil
    var locks: Set<String> = []
    var actors: [Actor]
    /// Numeric colors and topology survive palette-catalog and preference changes.
    /// Optional for recipes saved before backgrounds were frozen.
    var backgroundStyle: DayObjectMeshGradientStyle? = nil

    var isSupported: Bool {
        schemaVersion == 1 && generatorVersion == "atlas-1" && catalogVersion == "2026-09-09"
    }
}
