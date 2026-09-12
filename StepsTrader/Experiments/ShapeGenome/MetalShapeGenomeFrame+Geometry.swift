import Foundation
import simd

extension MetalShapeGenomeFrame {
    static func geometry(for preset: MetalShapePreset, seed: UInt64) -> MetalShapeGenomeUniforms {
        switch preset.contour {
        case let .genome(genome):
            let harmonics = Array(genome.harmonics.prefix(3))
            func packed(_ index: Int) -> SIMD4<Float> {
                guard harmonics.indices.contains(index) else { return .zero }
                let value = harmonics[index]
                return SIMD4(Float(value.frequency), value.amplitude, value.phase, 1)
            }
            return MetalShapeGenomeUniforms(
                superformula: genome.superformula,
                harmonic0: packed(0),
                harmonic1: packed(1),
                harmonic2: packed(2),
                anisotropyOffset: SIMD4(
                    genome.anisotropy.x, genome.anisotropy.y,
                    genome.centerOffset.x, genome.centerOffset.y
                ),
                transform: SIMD4(genome.rotation, normalization(genome), 1, 0),
                metadata: SIMD4(0, 0, 0, UInt32(harmonics.count)),
                reserved: .zero
            )
        case let .legacy(shape, variant):
            return MetalShapeGenomeUniforms(
                superformula: SIMD4(2, 1, 1, 1),
                harmonic0: .zero,
                harmonic1: .zero,
                harmonic2: .zero,
                anisotropyOffset: SIMD4(1, 1, 0, 0),
                transform: SIMD4(0, 1, 1, 0),
                metadata: SIMD4(1, shape, variant, 0),
                reserved: .zero
            )
        case .snowflake:
            let form = MetalShapeSnowflake.make(seed: seed)
            func packed(_ first: Int, _ second: Int) -> SIMD4<Float> {
                let a = form.harmonics.indices.contains(first) ? form.harmonics[first] : .zero
                let b = form.harmonics.indices.contains(second) ? form.harmonics[second] : .zero
                return SIMD4(Float(a.multiplier), a.amplitude, Float(b.multiplier), b.amplitude)
            }
            return MetalShapeGenomeUniforms(
                superformula: SIMD4(Float(form.folds), Float(form.harmonics.count), 0, 0),
                harmonic0: packed(0, 1),
                harmonic1: packed(2, 3),
                harmonic2: SIMD4(
                    Float(form.harmonics.indices.contains(4) ? form.harmonics[4].multiplier : 0),
                    form.harmonics.indices.contains(4) ? form.harmonics[4].amplitude : 0,
                    form.branchDepth,
                    form.branchWidth
                ),
                anisotropyOffset: SIMD4(1, 1, 0, 0),
                transform: SIMD4(form.rotation, form.normalization, form.notchDepth, form.notchPosition),
                metadata: SIMD4(2, UInt32(truncatingIfNeeded: seed), UInt32(form.folds), UInt32(form.harmonics.count)),
                reserved: .zero
            )
        case .windflower:
            let form = MetalShapeWindflower.make(seed: seed)
            return MetalShapeGenomeUniforms(
                superformula: SIMD4(Float(form.petals), form.valleyRadius, form.irregularity, form.tipExponent),
                harmonic0: .zero,
                harmonic1: .zero,
                harmonic2: .zero,
                anisotropyOffset: SIMD4(1, 1, 0, 0),
                transform: SIMD4(form.rotation, 1, 1, 0),
                metadata: SIMD4(3, UInt32(truncatingIfNeeded: seed), UInt32(form.petals), 0),
                reserved: .zero
            )
        case .concaveSquare:
            let form = MetalShapeConcaveSquare.make(seed: seed)
            return MetalShapeGenomeUniforms(
                superformula: SIMD4(4, form.valleyRadius, form.edgeExponent, 0),
                harmonic0: .zero,
                harmonic1: .zero,
                harmonic2: .zero,
                anisotropyOffset: SIMD4(1, 1, 0, 0),
                transform: SIMD4(form.rotation, 1, form.valleyRadius, form.edgeExponent),
                metadata: SIMD4(4, UInt32(truncatingIfNeeded: seed), 4, 0),
                reserved: .zero
            )
        case .softClover:
            let form = MetalShapeSoftClover.make(seed: seed)
            return MetalShapeGenomeUniforms(
                superformula: SIMD4(4, form.valleyRadius, form.lobeExponent, 0),
                harmonic0: .zero,
                harmonic1: .zero,
                harmonic2: .zero,
                anisotropyOffset: SIMD4(form.anisotropy.x, form.anisotropy.y, 0, 0),
                transform: SIMD4(form.rotation, 1, form.valleyRadius, form.lobeExponent),
                metadata: SIMD4(5, UInt32(truncatingIfNeeded: seed), 4, 0),
                reserved: .zero
            )
        }
    }

    private static func normalization(_ genome: MetalShapeGenome) -> Float {
        let maximum = (0..<512).reduce(Float(0)) { current, index in
            let angle = Float(index) * 2 * .pi / 512
            return max(current, MetalShapeContour.radius(angle: angle, genome: genome))
        }
        return 1 / max(maximum, 0.000_01)
    }
}
