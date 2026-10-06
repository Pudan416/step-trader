import Foundation
import simd

extension MetalShapeGenomeFrame {
    static func palette(
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

    static func dimpledSpherePalette() -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        (
            SIMD4(0.12, 0.29, 0.76, 1),
            SIMD4(0.56, 0.91, 0.98, 1),
            SIMD4(0.28, 0.70, 0.91, 1)
        )
    }

    static func spiralRaysPalette() -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let ink = SIMD4<Float>(0.59, 0.70, 0.94, 1)
        return (ink, ink, ink)
    }

    static func eclipseGlowPalette(seed: UInt64) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let palettes: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(1.00, 0.18, 0.20), SIMD3(1.00, 0.48, 0.08), SIMD3(1.00, 0.82, 0.22)),
            (SIMD3(0.94, 0.18, 0.55), SIMD3(0.96, 0.37, 0.27), SIMD3(1.00, 0.68, 0.18)),
            (SIMD3(0.20, 0.40, 1.00), SIMD3(0.12, 0.86, 0.95), SIMD3(0.67, 0.28, 1.00)),
            (SIMD3(0.10, 0.76, 0.57), SIMD3(0.70, 0.89, 0.20), SIMD3(1.00, 0.63, 0.16)),
            (SIMD3(0.65, 0.18, 1.00), SIMD3(0.18, 0.54, 1.00), SIMD3(0.18, 0.91, 0.83)),
            (SIMD3(1.00, 0.24, 0.36), SIMD3(0.82, 0.20, 0.89), SIMD3(0.29, 0.50, 1.00)),
        ]
        let selected = palettes[Int(seed % UInt64(palettes.count))]
        return (
            SIMD4(selected.0, 1),
            SIMD4(selected.1, 1),
            SIMD4(selected.2, 1)
        )
    }
}
