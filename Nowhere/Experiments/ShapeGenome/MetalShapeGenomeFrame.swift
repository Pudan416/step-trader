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
        if material == .eclipseGlow {
            palette = eclipseGlowPalette(seed: seed)
        } else if material == .spiralVariation {
            palette = spiralRaysPalette()
        } else if preset.id == "reference.dimpled-sphere" {
            palette = dimpledSpherePalette()
        }
        if material == .sideLight { palette.2 = palette.1 }
        let materialIndex = UInt32(MetalShapeMaterial.allCases.firstIndex(of: material) ?? 0)
        let radialDensity = material == .concentricRings
            ? 0.08 + random.nextUnit() * 0.84
            : 0.48 + random.nextUnit() * 0.42
        var params0 = SIMD4(phase, radialDensity, 0.16 + random.nextUnit() * 0.18, 0.52)
        var params1 = SIMD4(direction.x, direction.y, 0.34 + random.nextUnit() * 0.30, 0.68)
        if material == .spiralVariation {
            let angles: [Float] = [-80, -70, -55, -45, -35, -20, -10, -5, 5, 10, 20, 35, 45, 55, 70, 80]
            params0 = SIMD4(phase, angles[Int(seed % UInt64(angles.count))], 0.0038, 0.92)
            params1.z = 22
        }
        let materialUniforms = MetalShapeMaterialUniforms(
            color0: palette.0,
            color1: palette.1,
            color2: palette.2,
            params0: params0,
            params1: params1,
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
