import Foundation
import simd

enum MetalShapeContourError: Error, Equatable {
    case unsupportedLegacyPreset
    case invalidSampleCount
}

enum MetalShapeContour {
    static func point(for preset: MetalShapePreset, angle: Float) throws -> SIMD2<Float> {
        guard case let .genome(genome) = preset.contour else {
            throw MetalShapeContourError.unsupportedLegacyPreset
        }
        return point(genome: genome, angle: angle, normalization: normalization(for: genome))
    }

    static func sample(preset: MetalShapePreset, count: Int) throws -> [SIMD2<Float>] {
        guard count >= 3 else { throw MetalShapeContourError.invalidSampleCount }
        guard case let .genome(genome) = preset.contour else {
            throw MetalShapeContourError.unsupportedLegacyPreset
        }
        let scale = normalization(for: genome)
        return (0..<count).map { index in
            let angle = Float(index) * 2 * .pi / Float(count)
            return point(genome: genome, angle: angle, normalization: scale)
        }
    }

    static func radius(angle theta: Float, genome: MetalShapeGenome) -> Float {
        let m = min(max(genome.superformula.x, 2), 12)
        let n1 = min(max(genome.superformula.y, 0.2), 8)
        let n2 = min(max(genome.superformula.z, 0.2), 8)
        let n3 = min(max(genome.superformula.w, 0.2), 8)
        let a = pow(abs(cos(m * theta / 4)), n2)
        let b = pow(abs(sin(m * theta / 4)), n3)
        let base = pow(max(a + b, 0.000_01), -1 / n1)
        let modulation = genome.harmonics.prefix(3).reduce(Float(1)) { partial, harmonic in
            let frequency = Float(min(max(harmonic.frequency, 2), 12))
            let amplitude = min(max(harmonic.amplitude, -0.12), 0.12)
            return partial + amplitude * cos(frequency * theta + harmonic.phase)
        }
        return max(base * modulation, 0.000_01)
    }

    private static func normalization(for genome: MetalShapeGenome) -> Float {
        let maximum = (0..<512).reduce(Float(0)) { current, index in
            let angle = Float(index) * 2 * .pi / 512
            return max(current, radius(angle: angle, genome: genome))
        }
        return 1 / max(maximum, 0.000_01)
    }

    private static func point(
        genome: MetalShapeGenome,
        angle: Float,
        normalization: Float
    ) -> SIMD2<Float> {
        let normalizedRadius = min(max(radius(angle: angle, genome: genome) * normalization, 0.72), 1)
        var point = SIMD2(cos(angle), sin(angle)) * normalizedRadius
        point *= SIMD2(
            min(max(genome.anisotropy.x, 0.82), 1.18),
            min(max(genome.anisotropy.y, 0.82), 1.18)
        )
        let cosine = cos(genome.rotation)
        let sine = sin(genome.rotation)
        point = SIMD2(
            point.x * cosine - point.y * sine,
            point.x * sine + point.y * cosine
        )
        return point + simd_clamp(
            genome.centerOffset,
            SIMD2(repeating: -0.12),
            SIMD2(repeating: 0.12)
        )
    }
}
