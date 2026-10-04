import Foundation
import simd

/// Reversible offsets around the frozen composition. Nothing here is persisted
/// or fed back into the saved actor, and music keeps ownership of its physics.
enum NativeAtlasAmbientMotion {
    struct Pose {
        var offset = SIMD2<Float>.zero
        var rotation: Float = 0
        var scale: Float = 1
    }

    static func pose(
        actor: NativeAtlasRecipe.Actor,
        family: NativeAtlasDailyStyle.Family,
        daySeed: UInt64,
        elapsed: TimeInterval,
        weight: Float,
        livingVariation: Bool = false
    ) -> Pose {
        guard elapsed.isFinite, weight > 0 else { return Pose() }
        let seed = UInt64(actor.seedHex, radix: 16) ?? 0
        var random = SeededRNG(seed: seed ^ 0x414D_4249_454E_5432)
        let phase = Float(random.nextDouble(in: 0...(2 * .pi)))
        let driftPeriod = Float(random.nextDouble(in: livingVariation ? 14...24 : 24...40))
        let breathPeriod = Float(random.nextDouble(in: livingVariation ? 9...15 : 14...24))
        let turnPeriod = Float(random.nextDouble(in: livingVariation ? 50...85 : 140...220))
        let time = max(0, elapsed)
        func cycle(_ period: Float, speed: Float = 1) -> Float {
            Float((time * Double(speed) * 2 * .pi / Double(period))
                .truncatingRemainder(dividingBy: 2 * .pi))
        }
        let strength: Float = livingVariation ? 0.78 + Float(seed % 5) * 0.055
            : seed % 5 == 0 ? 0.18 : 1
        let blend = min(max(weight, 0), 1) * strength
        let drift = cycle(driftPeriod)
        let breath = sin(cycle(breathPeriod) + phase * 1.7)
        var offset = SIMD2(sin(drift + phase), cos(cycle(driftPeriod, speed: 0.73) + phase * 1.3))
        var rotation: Float = 0
        let amplitude: Float
        let breathing: Float
        switch family {
        case .circles:
            amplitude = 0.010
            breathing = 0.023
        case .blobs:
            amplitude = 0.016
            breathing = 0.014
            rotation = sin(cycle(driftPeriod, speed: 0.55) + phase) * 0.035
        case .squares:
            amplitude = 0.006
            breathing = 0.006
            rotation = sin(cycle(driftPeriod, speed: 0.6) + phase) * 0.045
        case .clovers:
            amplitude = 0.007
            breathing = 0.009
            // Bounded turns remain calm even while fading into music physics.
            rotation = sin(cycle(turnPeriod) + phase) * (seed.isMultiple(of: 2) ? 0.11 : 0.055)
        case .flowers:
            amplitude = 0.009
            breathing = 0.012
            rotation = sin(cycle(driftPeriod, speed: 0.45) + phase) * 0.07
        case .rays:
            amplitude = 0.012
            breathing = 0.007
            let axis = Float(daySeed & 65_535) / 65_535 * 2 * .pi
            offset = SIMD2(cos(axis), sin(axis)) * sin(drift + phase)
            rotation = sin(cycle(driftPeriod, speed: 0.4) + phase) * (livingVariation ? 0.14 : 0.035)
        }
        let driftGain: Float = livingVariation ? 1.35 : 1
        let breathGain: Float = livingVariation ? 1.3 : 1
        return Pose(offset: offset * amplitude * driftGain * blend,
                    rotation: rotation * blend,
                    scale: 1 + breath * breathing * breathGain * blend)
    }
}

/// Fade ambient offsets out as music takes over, and back in while its existing
/// return animation settles. The elapsed clock pauses with the Canvas lifecycle.
struct NativeAtlasAmbientBlend {
    private var previousTime: TimeInterval?
    private var value: Float = 0

    mutating func update(elapsed: TimeInterval, enabled: Bool, playbackIsActive: Bool) -> Float {
        guard elapsed.isFinite else { return 0 }
        let target: Float = enabled && !playbackIsActive ? 1 : 0
        guard let previousTime, elapsed >= previousTime else {
            self.previousTime = elapsed
            value = target
            return value
        }
        self.previousTime = elapsed
        // Reduce Motion takes effect immediately; music handoffs ease over 0.8s.
        guard enabled else { value = 0; return value }
        let step = Float(min(elapsed - previousTime, 0.1)) / 0.8
        value += min(max(target - value, -step), step)
        return value
    }
}
