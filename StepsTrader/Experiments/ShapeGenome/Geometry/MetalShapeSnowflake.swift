import Foundation
import simd

struct MetalShapeSnowflakeHarmonic: Equatable, Sendable {
    static let zero = MetalShapeSnowflakeHarmonic(multiplier: 0, amplitude: 0)
    let multiplier: Int
    let amplitude: Float
}

struct MetalShapeSnowflakeParameters: Equatable, Sendable {
    let folds: Int
    let harmonics: [MetalShapeSnowflakeHarmonic]
    let branchDepth: Float
    let branchWidth: Float
    let notchDepth: Float
    let notchPosition: Float
    let rotation: Float
    let normalization: Float
}

enum MetalShapeSnowflake {
    static func make(seed: UInt64) -> MetalShapeSnowflakeParameters {
        let folds = ProceduralShapeGenerator.mindFolds(seed: seed)
        var random = SeededRNG(seed: seed)

        // Keep the legacy RectMorph draw order, even for layout values that
        // cancel when the contour is normalized for the atlas.
        _ = random.nextDouble()
        _ = random.nextDouble()
        _ = random.nextDouble()
        let rotation = Float(random.nextDouble(in: 0...(2 * .pi / Double(folds))))
        _ = random.nextInt(in: 0...(CanvasColorPalette.paletteHex.count - 1))

        let harmonicCount = 2 + random.nextInt(in: 0...3)
        var harmonics = [MetalShapeSnowflakeHarmonic]()
        for index in 0..<harmonicCount {
            let maximum = index == 0 ? 2 : (index < 2 ? 4 : 6)
            harmonics.append(.init(
                multiplier: random.nextInt(in: 1...maximum),
                amplitude: Float(random.nextDouble(in: 0.06...0.55) * (index < 2 ? 1 : 0.5))
            ))
        }

        let hasBranch = random.nextDouble(in: 0...1) < 0.4
        let branchDepth = hasBranch ? Float(random.nextDouble(in: 0.15...0.5)) : 0
        let branchWidth = hasBranch ? Float(random.nextDouble(in: 0.15...0.4)) : 0
        let hasNotch = random.nextDouble(in: 0...1) < 0.35
        let notchDepth = hasNotch ? Float(random.nextDouble(in: 0.1...0.35)) : 0
        let notchPosition = hasNotch ? Float(random.nextDouble(in: 0.3...0.7)) : 0.5

        var form = MetalShapeSnowflakeParameters(
            folds: folds,
            harmonics: harmonics,
            branchDepth: branchDepth,
            branchWidth: branchWidth,
            notchDepth: notchDepth,
            notchPosition: notchPosition,
            rotation: rotation,
            normalization: 1
        )
        let maximum = (0..<64).reduce(Float(0)) { value, index in
            let angle = Float(index) * 2 * .pi / 64
            return max(value, rawRadius(angle: angle, parameters: form))
        }
        form = MetalShapeSnowflakeParameters(
            folds: form.folds,
            harmonics: form.harmonics,
            branchDepth: form.branchDepth,
            branchWidth: form.branchWidth,
            notchDepth: form.notchDepth,
            notchPosition: form.notchPosition,
            rotation: form.rotation,
            normalization: 1 / max(maximum, 0.000_01)
        )
        return form
    }

    static func radius(angle: Float, parameters form: MetalShapeSnowflakeParameters) -> Float {
        rawRadius(angle: angle - form.rotation, parameters: form) * form.normalization
    }

    private static func rawRadius(angle: Float, parameters form: MetalShapeSnowflakeParameters) -> Float {
        let halfSector = Float.pi / Float(form.folds)
        var local = angle.truncatingRemainder(dividingBy: 2 * halfSector)
        if local < 0 { local += 2 * halfSector }
        let folded = local > halfSector ? 2 * halfSector - local : local
        let unit = folded / halfSector
        let u = unit * .pi
        var radius: Float = 1
        for harmonic in form.harmonics {
            radius += harmonic.amplitude * cos(u * Float(harmonic.multiplier))
        }
        if form.branchDepth > 0 {
            let spike = max(0, 1 - abs(unit) / form.branchWidth)
            radius += form.branchDepth * spike * spike
        }
        if form.notchDepth > 0 {
            let distance = (unit - form.notchPosition) / 0.12
            radius -= form.notchDepth * exp(-(distance * distance))
        }
        return max(radius, 0.12)
    }
}
