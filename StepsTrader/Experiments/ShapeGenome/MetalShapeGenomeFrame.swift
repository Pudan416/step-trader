import Foundation
import simd

@_alignment(16)
struct MetalShapeGenomeUniforms: Equatable, Sendable {
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

@_alignment(16)
struct MetalShapeMaterialUniforms: Equatable, Sendable {
    static let metalStride = 128

    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let params0: SIMD4<Float>
    let params1: SIMD4<Float>
    let params2: SIMD4<Float>
    let params3: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    var materialIndex: UInt32 { metadata.x }
    var direction: SIMD2<Float> { SIMD2(params1.x, params1.y) }

    var colorsAreFiniteAndBounded: Bool {
        [color0, color1, color2].allSatisfy { color in
            color.x.isFinite && color.y.isFinite && color.z.isFinite && color.w.isFinite
                && (0...1).contains(color.x) && (0...1).contains(color.y)
                && (0...1).contains(color.z) && (0...1).contains(color.w)
        }
    }
}

struct MetalShapeGenomeFrame: Equatable, Sendable {
    let geometry: MetalShapeGenomeUniforms
    let material: MetalShapeMaterialUniforms

    static func make(
        preset: MetalShapePreset,
        material: MetalShapeMaterial,
        seed: UInt64,
        blurMode: UInt32 = 0
    ) -> MetalShapeGenomeFrame {
        var random = MetalShapeAtlasRandom(seed: seed ^ stableHash(preset.id))
        let geometry = geometry(for: preset, seed: seed)
        let phase = random.nextUnit()
        let angle = random.nextUnit() * 2 * .pi
        let direction = SIMD2(cos(angle), sin(angle))
        var palette = palette(seed: seed, random: &random)
        if material == .sideLight { palette.2 = palette.1 }
        let materialIndex = UInt32(MetalShapeMaterial.allCases.firstIndex(of: material) ?? 0)
        let materialUniforms = MetalShapeMaterialUniforms(
            color0: palette.0,
            color1: palette.1,
            color2: palette.2,
            params0: SIMD4(phase, 0.48 + random.nextUnit() * 0.42, 0.16 + random.nextUnit() * 0.18, 0.52),
            params1: SIMD4(direction.x, direction.y, 0.34 + random.nextUnit() * 0.30, 0.68),
            params2: SIMD4(random.nextUnit(), random.nextUnit(), random.nextUnit(), random.nextUnit()),
            params3: SIMD4(0.018, 0.055, 0.16, 0.72),
            metadata: SIMD4(materialIndex, blurMode, UInt32(seed & 0xffff_ffff), UInt32(seed >> 32))
        )
        return MetalShapeGenomeFrame(geometry: geometry, material: materialUniforms)
    }

    private static func geometry(for preset: MetalShapePreset, seed: UInt64) -> MetalShapeGenomeUniforms {
        let descriptor: MetalShapeContourDescriptor = preset.contour == .superform
            ? .genome(MetalShapeSuperform.make(seed: seed))
            : preset.contour
        switch descriptor {
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
        case .superform:
            preconditionFailure("Superform descriptors are resolved before packing")
        }
    }

    private static func normalization(_ genome: MetalShapeGenome) -> Float {
        let maximum = (0..<512).reduce(Float(0)) { current, index in
            let angle = Float(index) * 2 * .pi / 512
            return max(current, MetalShapeContour.radius(angle: angle, genome: genome))
        }
        return 1 / max(maximum, 0.000_01)
    }

    private static func palette(
        seed: UInt64,
        random: inout MetalShapeAtlasRandom
    ) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let palettes: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0.91, 0.22, 0.50), SIMD3(1.00, 0.76, 0.19), SIMD3(0.24, 0.13, 0.40)),
            (SIMD3(0.13, 0.57, 0.78), SIMD3(0.48, 0.94, 0.73), SIMD3(0.12, 0.17, 0.34)),
            (SIMD3(0.94, 0.35, 0.20), SIMD3(0.98, 0.80, 0.57), SIMD3(0.32, 0.12, 0.22)),
        ]
        let selected = palettes[Int(seed % UInt64(palettes.count))]
        let lift = (random.nextUnit() - 0.5) * 0.06
        func packed(_ color: SIMD3<Float>) -> SIMD4<Float> {
            SIMD4(simd_clamp(color + SIMD3(repeating: lift), .zero, SIMD3(repeating: 1)), 1)
        }
        return (packed(selected.0), packed(selected.1), packed(selected.2))
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum MetalShapeSuperform {
    static func make(seed: UInt64) -> MetalShapeGenome {
        var random = MetalShapeAtlasRandom(seed: seed ^ 0x5355_5045_5246_4F52)
        let lobes = 3 + Int(seed % 5)
        let depth = 0.10 + random.nextUnit() * 0.075
        let companionFrequency = max(2, lobes - 1)
        return MetalShapeGenome(
            morphology: .superform,
            superformula: SIMD4(Float(lobes), 2, 2, 2),
            harmonics: [
                .init(frequency: lobes, amplitude: depth, phase: random.nextUnit() * 2 * .pi),
                .init(frequency: companionFrequency, amplitude: 0.008 + random.nextUnit() * 0.010, phase: random.nextUnit() * 2 * .pi),
            ],
            anisotropy: SIMD2(0.97 + random.nextUnit() * 0.06, 0.97 + random.nextUnit() * 0.06),
            centerOffset: .zero,
            rotation: random.nextUnit() * 2 * .pi
        )
    }
}

private struct MetalShapeAtlasRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func nextUnit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(value >> 40) / Float(1 << 24)
    }
}
