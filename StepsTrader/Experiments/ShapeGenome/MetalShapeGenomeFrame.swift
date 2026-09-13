import Foundation
import simd

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
        var direction = SIMD2(cos(angle), sin(angle))
        if material == .directionalBlur {
            switch preset.id {
            case "legacy.soft-square": direction = SIMD2(-1, 0)
            case "legacy.rounded-triangle": direction = SIMD2(1, 0)
            case "legacy.rounded-hexagon": direction = SIMD2(0, 1)
            default: break
            }
        }
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

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
