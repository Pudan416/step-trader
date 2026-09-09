import Foundation
import simd

struct MetalShapeWindflowerParameters: Equatable, Sendable {
    let petals: Int
    let valleyRadius: Float
    let irregularity: Float
    let tipExponent: Float
    let rotation: Float
    let seed: UInt32
}

enum MetalShapeWindflower {
    static func make(seed: UInt64) -> MetalShapeWindflowerParameters {
        let code = (seed &* 2) ^ (seed >> 3)
        let petals = 3 + 2 * Int(code % 3)
        var random = MetalShapeAtlasRandom(seed: seed ^ 0x5749_4E44_464C_4F57)
        return .init(
            petals: petals,
            valleyRadius: 0.34 + random.nextUnit() * 0.07,
            irregularity: 0.18 + random.nextUnit() * 0.16,
            tipExponent: 0.56 + random.nextUnit() * 0.16,
            rotation: random.nextUnit() * 2 * .pi,
            seed: UInt32(truncatingIfNeeded: seed)
        )
    }

    static func radius(angle theta: Float, parameters form: MetalShapeWindflowerParameters) -> Float {
        let sector = 2 * Float.pi / Float(form.petals)
        let shifted = (theta + sector * 0.5) / sector
        let cell = floor(shifted)
        let local = (shifted - cell) * sector - sector * 0.5
        let petal = positiveModulo(Int(cell), form.petals)
        let skew = (hash(form.seed, petal, 0) - 0.5) * sector * form.irregularity * 0.55
        let span = local < skew ? skew + sector * 0.5 : sector * 0.5 - skew
        let distance = min(abs(local - skew) / max(span, 0.000_01), 1)
        let exponent = form.tipExponent * (0.88 + 0.24 * hash(form.seed, petal, 1))
        let tip = 1 - form.irregularity * (0.05 + 0.42 * hash(form.seed, petal, 2))
        let valley = form.valleyRadius * (0.94 + 0.12 * hash(form.seed, petal, 3))
        return valley + (tip - valley) * (1 - pow(distance, exponent))
    }

    private static func hash(_ seed: UInt32, _ petal: Int, _ channel: UInt32) -> Float {
        var value = seed ^ (UInt32(petal) &* 0x9E37_79B9) ^ (channel &* 0x85EB_CA6B)
        value ^= value >> 16
        value &*= 0x7FEB_352D
        value ^= value >> 15
        value &*= 0x846C_A68B
        value ^= value >> 16
        return Float(value & 0x00FF_FFFF) / Float(0x0100_0000)
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let result = value % divisor
        return result >= 0 ? result : result + divisor
    }
}
