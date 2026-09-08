import Foundation

struct MetalShapeHarmonic: Codable, Equatable, Sendable {
    let frequency: Int
    let amplitude: Float
    let phase: Float
}

enum MetalShapeMorphology: String, Codable, CaseIterable, Sendable {
    case softRadial
    case lobed
    case snowflake
    case windflower
    case concaveSquare
    case softClover
    case foldedRosette
    case crystalline
    case legacyRound
    case legacyPolygon
    case legacyStar
}

struct MetalShapeGenome: Codable, Equatable, Sendable {
    let morphology: MetalShapeMorphology
    let superformula: SIMD4<Float>
    let harmonics: [MetalShapeHarmonic]
    let anisotropy: SIMD2<Float>
    let centerOffset: SIMD2<Float>
    let rotation: Float
}

enum MetalShapeMaterial: String, Codable, CaseIterable, Sendable {
    case solid
    case sideLight
    case contour
    case directionalBlur
    case radialTwo
    case radialThree
    case proceduralLight
    case proceduralFlow
    case proceduralContour
    case eclipseGlow
}

enum MetalShapeRole: String, Codable, CaseIterable, Sendable {
    case primary
    case supporting
    case accent
}

enum MetalShapeSource: String, Codable, Sendable {
    case genome
    case legacy
}

enum MetalShapeContourDescriptor: Codable, Equatable, Sendable {
    case genome(MetalShapeGenome)
    case snowflake
    case windflower
    case concaveSquare
    case softClover
    case legacy(shape: UInt32, variant: UInt32)
}

struct MetalShapeCompatibility: Codable, Equatable, Sendable {
    let preferred: Set<MetalShapeMaterial>
    let allowed: Set<MetalShapeMaterial>
    let roles: Set<MetalShapeRole>
    let minimumSize: Float
    let maximumSize: Float
    let maxInstances: Int
    let complexity: Float
    let visualMass: Float
    let haloFootprint: Float
    let blurFootprint: Float

    var prohibited: Set<MetalShapeMaterial> {
        Set(MetalShapeMaterial.allCases).subtracting(allowed)
    }
}

struct MetalShapePreset: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let source: MetalShapeSource
    let morphology: MetalShapeMorphology
    let contour: MetalShapeContourDescriptor
    let compatibility: MetalShapeCompatibility
}
