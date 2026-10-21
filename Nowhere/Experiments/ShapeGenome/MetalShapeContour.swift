import Foundation
import simd

enum MetalShapeContourError: Error, Equatable {
    case unsupportedLegacyPreset
    case invalidSampleCount
}

enum MetalShapeContour {
    static func point(for preset: MetalShapePreset, angle: Float, seed: UInt64 = 42) throws -> SIMD2<Float> {
        switch preset.contour {
        case let .genome(genome):
            return point(genome: genome, angle: angle, normalization: normalization(for: genome))
        case .snowflake:
            return point(snowflake: MetalShapeSnowflake.make(seed: seed), angle: angle)
        case .windflower:
            return point(windflower: MetalShapeWindflower.make(seed: seed), angle: angle)
        case .concaveSquare:
            return point(concaveSquare: MetalShapeConcaveSquare.make(seed: seed), angle: angle)
        case .softClover:
            return point(softClover: MetalShapeSoftClover.make(seed: seed), angle: angle)
        case .dimpledSphere:
            return SIMD2(cos(angle), sin(angle))
        case .legacy:
            throw MetalShapeContourError.unsupportedLegacyPreset
        }
    }

    static func sample(preset: MetalShapePreset, count: Int, seed: UInt64 = 42) throws -> [SIMD2<Float>] {
        guard count >= 3 else { throw MetalShapeContourError.invalidSampleCount }
        switch preset.contour {
        case let .genome(genome):
            let scale = normalization(for: genome)
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return point(genome: genome, angle: angle, normalization: scale)
            }
        case .snowflake:
            let form = MetalShapeSnowflake.make(seed: seed)
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return point(snowflake: form, angle: angle)
            }
        case .windflower:
            let form = MetalShapeWindflower.make(seed: seed)
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return point(windflower: form, angle: angle)
            }
        case .concaveSquare:
            let form = MetalShapeConcaveSquare.make(seed: seed)
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return point(concaveSquare: form, angle: angle)
            }
        case .softClover:
            let form = MetalShapeSoftClover.make(seed: seed)
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return point(softClover: form, angle: angle)
            }
        case .dimpledSphere:
            return (0..<count).map { index in
                let angle = Float(index) * 2 * .pi / Float(count)
                return SIMD2(cos(angle), sin(angle))
            }
        case .legacy:
            throw MetalShapeContourError.unsupportedLegacyPreset
        }
    }

    private static let frozenCacheLock = NSLock()
    private static var frozenCache: [(uniforms: MetalShapeGenomeUniforms, count: Int, points: [SIMD2<Float>])] = []

    /// Frozen native geometry, in the same local coordinates as metalShapeDistance.
    /// Hit testing must use saved uniforms rather than regenerating today's preset.
    static func sample(uniforms g: MetalShapeGenomeUniforms, count: Int = 256) -> [SIMD2<Float>] {
        guard count >= 3 else { return [] }
        frozenCacheLock.lock()
        let cached = frozenCache.first { $0.uniforms == g && $0.count == count }?.points
        frozenCacheLock.unlock()
        if let cached { return cached }
        let rotation = g.transform.x
        let cosine = cos(rotation), sine = sin(rotation)
        let points = (0..<count).map { index in
            let angle = Float(index) * 2 * .pi / Float(count)
            let radius = frozenRadius(angle: angle, uniforms: g)
            let point = SIMD2(cos(angle), sin(angle)) * radius
                * simd_clamp(SIMD2(g.anisotropyOffset.x, g.anisotropyOffset.y),
                             SIMD2(repeating: 0.82), SIMD2(repeating: 1.18))
            return SIMD2(point.x * cosine - point.y * sine, point.x * sine + point.y * cosine)
                + SIMD2(g.anisotropyOffset.z, g.anisotropyOffset.w)
        }
        frozenCacheLock.lock()
        if frozenCache.count >= 128 { frozenCache.removeFirst() }
        frozenCache.append((g, count, points))
        frozenCacheLock.unlock()
        return points
    }

    private static func frozenRadius(angle: Float, uniforms g: MetalShapeGenomeUniforms) -> Float {
        switch g.sourceKind {
        case 1:
            let variant = max(g.legacyVariant, 1) - 1
            if g.legacyShape == 6 {
                let exponent = 2.3 + 1.2 * Float(variant / 16)
                return pow(pow(abs(cos(angle)), exponent) + pow(abs(sin(angle)), exponent), -1 / exponent)
            }
            if g.legacyShape == 5 {
                let sides = 3 + Float(variant % 4)
                let sector = 2 * Float.pi / sides
                let folded = angle - sector * floor((angle + sector / 2) / sector)
                // The native polygon distance is blended 12% toward an r0.94 circle.
                return 0.88 * cos(.pi / sides) / max(cos(folded), 0.0001) + 0.12 * 0.94
            }
            if g.legacyShape == 4 {
                let amplitude = 0.12 + 0.105 * Float((variant / 4) % 4) / 3
                return (1 + amplitude * cos((3 + Float(variant % 4)) * angle)) / (1 + amplitude)
            }
            return 1
        case 2:
            let packed = [g.harmonic0, g.harmonic1, g.harmonic2]
            let harmonics = (0..<Int(min(g.metadata.w, 5))).map { index in
                let value = packed[index / 2]
                return MetalShapeSnowflakeHarmonic(multiplier: Int(index % 2 == 0 ? value.x : value.z),
                                                  amplitude: index % 2 == 0 ? value.y : value.w)
            }
            return MetalShapeSnowflake.radius(angle: angle, parameters: .init(
                folds: Int(min(max(g.metadata.z, 3), 12)), harmonics: harmonics,
                branchDepth: g.harmonic2.z, branchWidth: max(g.harmonic2.w, 0.0001),
                notchDepth: g.transform.z, notchPosition: g.transform.w,
                rotation: 0, normalization: g.normalization))
        case 3:
            return MetalShapeWindflower.radius(angle: angle, parameters: .init(
                petals: Int(min(max(g.metadata.z, 3), 7)), valleyRadius: g.superformula.y,
                irregularity: g.superformula.z, tipExponent: g.superformula.w, rotation: 0, seed: g.metadata.y))
        case 4:
            return MetalShapeConcaveSquare.radius(angle: angle, parameters: .init(
                valleyRadius: min(max(g.transform.z, 0.62), 0.72),
                edgeExponent: min(max(g.transform.w, 2.4), 4), rotation: 0))
        case 5:
            return MetalShapeSoftClover.radius(angle: angle, parameters: .init(
                valleyRadius: min(max(g.transform.z, 0.46), 0.58),
                lobeExponent: min(max(g.transform.w, 0.54), 0.74), anisotropy: SIMD2(repeating: 1), rotation: 0))
        default:
            let formula = g.superformula
            let a = pow(max(abs(cos(min(max(formula.x, 2), 12) * angle / 4)), 0.00001), min(max(formula.z, 0.2), 8))
            let b = pow(max(abs(sin(min(max(formula.x, 2), 12) * angle / 4)), 0.00001), min(max(formula.w, 0.2), 8))
            let base = pow(max(a + b, 0.00001), -1 / min(max(formula.y, 0.2), 8))
            let modulation = [g.harmonic0, g.harmonic1, g.harmonic2].reduce(Float(1)) { value, harmonic in
                value + (harmonic.w >= 0.5 ? harmonic.y * cos(harmonic.x * angle + harmonic.z) : 0)
            }
            return min(max(base * modulation * g.normalization, 0.72), 1)
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

    private static func point(
        snowflake: MetalShapeSnowflakeParameters,
        angle: Float
    ) -> SIMD2<Float> {
        let radius = min(MetalShapeSnowflake.radius(angle: angle, parameters: snowflake), 1)
        return SIMD2(cos(angle), sin(angle)) * radius
    }

    private static func point(
        windflower: MetalShapeWindflowerParameters,
        angle: Float
    ) -> SIMD2<Float> {
        let localAngle = angle - windflower.rotation
        let radius = min(MetalShapeWindflower.radius(angle: localAngle, parameters: windflower), 1)
        return SIMD2(cos(angle), sin(angle)) * radius
    }

    private static func point(
        concaveSquare: MetalShapeConcaveSquareParameters,
        angle: Float
    ) -> SIMD2<Float> {
        let localAngle = angle - concaveSquare.rotation
        let radius = MetalShapeConcaveSquare.radius(angle: localAngle, parameters: concaveSquare)
        return SIMD2(cos(angle), sin(angle)) * radius
    }

    private static func point(
        softClover: MetalShapeSoftCloverParameters,
        angle: Float
    ) -> SIMD2<Float> {
        let localAngle = angle - softClover.rotation
        let radius = MetalShapeSoftClover.radius(angle: localAngle, parameters: softClover)
        var point = SIMD2(cos(angle), sin(angle)) * radius
        point *= softClover.anisotropy
        return point
    }
}
