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
}
