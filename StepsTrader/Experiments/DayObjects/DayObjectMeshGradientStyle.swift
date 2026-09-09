import Foundation
import simd

enum DayObjectMeshGradientArchetype: UInt32, CaseIterable, Equatable {
    case drift
    case orbit
    case tide
    case islands
    case bloom
}

/// The daily background's moving mesh-gradient art direction. A day retains
/// one curated topology and one direction; continuous values vary inside
/// bounded ranges so seeds feel related without collapsing into one vortex.
struct DayObjectMeshGradientStyle: Equatable {
    let colors: [SIMD3<Float>]
    let archetype: DayObjectMeshGradientArchetype
    let offset: SIMD2<Double>
    let distortion: Double
    let swirl: Double
    let speed: Double
    let scale: Double
    let phase: Double
    let motionDirection: Double
    let preservesColorFields: Bool

    init(
        colors: [SIMD3<Float>],
        archetype: DayObjectMeshGradientArchetype = .orbit,
        offset: SIMD2<Double> = .zero,
        distortion: Double,
        swirl: Double,
        speed: Double,
        scale: Double,
        phase: Double,
        motionDirection: Double = 1,
        preservesColorFields: Bool = false
    ) {
        self.colors = colors
        self.archetype = archetype
        self.offset = offset
        self.distortion = distortion
        self.swirl = swirl
        self.speed = speed
        self.scale = scale
        self.phase = phase
        self.motionDirection = motionDirection < 0 ? -1 : 1
        self.preservesColorFields = preservesColorFields
    }

    static func make(seed: UInt64, palette: DayObjectPalette) -> DayObjectMeshGradientStyle {
        var rng = SeededRNG.derived(from: seed, domain: "dayObjectMeshGradient")
        let archetype = DayObjectMeshGradientArchetype.allCases[
            rng.nextInt(in: 0...(DayObjectMeshGradientArchetype.allCases.count - 1))
        ]
        let direction = rng.nextInt(in: 0...1) == 0 ? -1.0 : 1.0
        let offset = SIMD2(
            rng.nextDouble(in: -0.18...0.18),
            rng.nextDouble(in: -0.18...0.18)
        )
        let distortion: Double
        let swirl: Double
        let speed: Double
        let scale: Double
        switch archetype {
        case .drift:
            distortion = rng.nextDouble(in: 0.08...0.24)
            swirl = rng.nextDouble(in: -0.04...0.04)
            speed = rng.nextDouble(in: 0.045...0.085)
            scale = rng.nextDouble(in: 0.90...1.24)
        case .orbit:
            distortion = rng.nextDouble(in: 0.20...0.48)
            swirl = direction * rng.nextDouble(in: 0.00...0.42)
            speed = rng.nextDouble(in: 0.045...0.090)
            scale = rng.nextDouble(in: 0.92...1.26)
        case .tide:
            distortion = rng.nextDouble(in: 0.20...0.50)
            swirl = rng.nextDouble(in: -0.08...0.08)
            speed = rng.nextDouble(in: 0.040...0.080)
            scale = rng.nextDouble(in: 0.88...1.22)
        case .islands:
            distortion = rng.nextDouble(in: 0.08...0.30)
            swirl = rng.nextDouble(in: -0.12...0.12)
            speed = rng.nextDouble(in: 0.050...0.100)
            scale = rng.nextDouble(in: 0.96...1.34)
        case .bloom:
            distortion = rng.nextDouble(in: 0.14...0.38)
            swirl = rng.nextDouble(in: -0.16...0.16)
            speed = rng.nextDouble(in: 0.035...0.070)
            scale = rng.nextDouble(in: 0.86...1.18)
        }
        return DayObjectMeshGradientStyle(
            colors: palette.colors.map(\.linearRGB),
            archetype: archetype,
            offset: offset,
            distortion: distortion,
            swirl: swirl,
            speed: speed,
            scale: scale,
            phase: rng.nextDouble(in: 0...(2 * .pi - Double.ulpOfOne)),
            motionDirection: direction
        )
    }

    /// Keep two genuinely different palette colors instead of averaging every
    /// swatch into a pale wash. Only the atlas route opts into this direction.
    static func primaryCanvas(seed: UInt64, palette: DayObjectPalette) -> DayObjectMeshGradientStyle {
        let base = make(seed: seed, palette: palette)
        let colors = palette.colors.map(\.linearRGB)
        var pair = (0, 1)
        var separation: Float = -1
        for i in colors.indices {
            for j in colors.indices where j > i {
                let delta = colors[i] - colors[j]
                let distance = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
                if distance > separation { separation = distance; pair = (i, j) }
            }
        }
        var rng = SeededRNG.derived(from: seed, domain: "primary-background")
        if rng.nextInt(in: 0...1) == 1 { pair = (pair.1, pair.0) }
        let remaining = colors.indices.filter { $0 != pair.0 && $0 != pair.1 }
        let accent = !remaining.isEmpty && rng.nextInt(in: 0...3) == 0
            ? colors[remaining[rng.nextInt(in: 0...(remaining.count - 1))]]
            : colors[pair.0]
        return Self(colors: [colors[pair.0], colors[pair.1], accent],
                    archetype: base.archetype, offset: base.offset,
                    distortion: base.distortion, swirl: base.swirl,
                    speed: base.speed, scale: 0.72, phase: base.phase,
                    motionDirection: base.motionDirection, preservesColorFields: true)
    }
}
