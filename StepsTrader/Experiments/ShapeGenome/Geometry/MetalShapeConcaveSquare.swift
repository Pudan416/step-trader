import Foundation
import simd

struct MetalShapeConcaveSquareParameters: Equatable, Sendable {
    let valleyRadius: Float
    let edgeExponent: Float
    let rotation: Float
}

enum MetalShapeConcaveSquare {
    static func make(seed: UInt64) -> MetalShapeConcaveSquareParameters {
        var random = MetalShapeAtlasRandom(seed: seed ^ 0x434F_4E43_4156_4534)
        return .init(
            valleyRadius: 0.62 + random.nextUnit() * 0.10,
            edgeExponent: 2.4 + random.nextUnit() * 1.6,
            rotation: random.nextUnit() * 2 * .pi
        )
    }

    static func radius(angle: Float, parameters form: MetalShapeConcaveSquareParameters) -> Float {
        let corner = abs(cos(2 * (angle - .pi / 4)))
        return form.valleyRadius + (1 - form.valleyRadius) * pow(corner, form.edgeExponent)
    }
}
