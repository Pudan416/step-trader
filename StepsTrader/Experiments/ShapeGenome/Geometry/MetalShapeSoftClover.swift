import Foundation
import simd

struct MetalShapeSoftCloverParameters: Equatable, Sendable {
    let valleyRadius: Float
    let lobeExponent: Float
    let anisotropy: SIMD2<Float>
    let rotation: Float
}

enum MetalShapeSoftClover {
    static func make(seed: UInt64) -> MetalShapeSoftCloverParameters {
        var random = MetalShapeAtlasRandom(seed: seed ^ 0x434C_4F56_4552_5346)
        let stretch = (random.nextUnit() - 0.5) * 0.10
        return .init(
            valleyRadius: 0.46 + random.nextUnit() * 0.12,
            lobeExponent: 0.54 + random.nextUnit() * 0.20,
            anisotropy: SIMD2(1 + stretch, 1 - stretch),
            rotation: random.nextUnit() * 2 * .pi
        )
    }

    static func radius(angle: Float, parameters form: MetalShapeSoftCloverParameters) -> Float {
        let lobe = abs(cos(2 * (angle - .pi / 4)))
        return form.valleyRadius + (1 - form.valleyRadius) * pow(lobe, form.lobeExponent)
    }
}
