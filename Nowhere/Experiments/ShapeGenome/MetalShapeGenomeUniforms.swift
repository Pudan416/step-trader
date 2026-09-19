import Foundation
import simd

@_alignment(16)
struct MetalShapeGenomeUniforms: Codable, Equatable, Sendable {
    static let metalStride = 128

    let superformula: SIMD4<Float>
    let harmonic0: SIMD4<Float>
    let harmonic1: SIMD4<Float>
    let harmonic2: SIMD4<Float>
    let anisotropyOffset: SIMD4<Float>
    let transform: SIMD4<Float>
    let metadata: SIMD4<UInt32>
    let reserved: SIMD4<Float>

    var sourceKind: UInt32 { metadata.x }
    var legacyShape: UInt32 { metadata.y }
    var legacyVariant: UInt32 { metadata.z }
    var normalization: Float { transform.y }

    var isFiniteAndBounded: Bool {
        let values = [
            superformula.x, superformula.y, superformula.z, superformula.w,
            anisotropyOffset.x, anisotropyOffset.y, anisotropyOffset.z, anisotropyOffset.w,
            transform.x, transform.y,
        ]
        return values.allSatisfy(\.isFinite)
            && (0.82...1.18).contains(anisotropyOffset.x)
            && (0.82...1.18).contains(anisotropyOffset.y)
            && transform.y > 0
    }
}
