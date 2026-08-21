import Foundation
import simd

struct DayObjectEnvironment: Equatable {
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool

    init(motionEnergy: Double, visualClarity: Double, reduceMotion: Bool) {
        self.motionEnergy = Self.clampedUnit(motionEnergy)
        self.visualClarity = Self.clampedUnit(visualClarity)
        self.reduceMotion = reduceMotion
    }

    var tempoScale: Double {
        guard !reduceMotion else { return 0.02 }
        let progress = motionEnergy * motionEnergy * (3 - 2 * motionEnergy)
        return 0.035 + (1.25 - 0.035) * progress
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DayObjectInsertionState: Equatable {
    let startedAt: Double
    let duration: Double

    init(startedAt rawStartedAt: Double, duration rawDuration: Double) {
        startedAt = rawStartedAt.isFinite ? rawStartedAt : 0
        duration = min(max(rawDuration.isFinite ? rawDuration : 0.8, 0.8), 1.4)
    }

    func envelope(at rawElapsed: Double) -> DayObjectInsertionEnvelope {
        let elapsed = rawElapsed.isFinite ? rawElapsed : 0
        let progress = min(max((elapsed - startedAt) / duration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return DayObjectInsertionEnvelope(
            opacity: eased,
            scale: 0.7 + 0.3 * eased
        )
    }
}

struct DayObjectInsertionEnvelope: Equatable {
    let opacity: Double
    let scale: Double
}

struct DayObjectPostProcess: Equatable {
    let blurRadius: Double
    let contrast: Double
    let saturation: Double
    let grainIntensity: Double
    let grainPhase: Double

    init(visualClarity rawVisualClarity: Double, reduceMotion: Bool, grainSeed: UInt64, elapsed rawElapsed: Double = 0) {
        let visualClarity = Self.clampedUnit(rawVisualClarity)
        blurRadius = pow(1 - visualClarity, 1.4) * 18
        contrast = 0.84 + 0.16 * visualClarity
        saturation = 0.88 + 0.12 * visualClarity
        grainIntensity = 0.035 + 0.04 * Self.stableUnit(grainSeed)

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        grainPhase = reduceMotion ? 0 : floor(elapsed * 12) / 12
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func stableUnit(_ seed: UInt64) -> Double {
        var value = seed &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}

/// The exact Swift counterpart of the Metal `DayObjectGPUActor` struct.
///
/// `color` deliberately begins at byte 32: the explicit eight-byte hole after
/// `halfSize` satisfies Metal's 16-byte `float4` alignment. The final padding
/// makes every element 80 bytes, a multiple of the struct's 16-byte alignment.
struct DayObjectGPUActor: Equatable {
    static let metalAlignment = 16
    static let metalStride = 80

    let position: SIMD2<Float>       // bytes 0...7
    let direction: SIMD2<Float>      // bytes 8...15
    let halfSize: SIMD2<Float>       // bytes 16...23
    private let positionPadding: SIMD2<Float> // bytes 24...31
    let color: SIMD4<Float>          // bytes 32...47
    let opacity: Float               // bytes 48...51
    let trailLength: Float           // bytes 52...55
    let shape: UInt32                // bytes 56...59
    let fill: UInt32                 // bytes 60...63
    let depth: Float                 // bytes 64...67
    let radialVariation: Float       // bytes 68...71
    private let tailPadding1: Float       // bytes 72...75
    private let tailPadding2: Float       // bytes 76...79

    init(
        position: SIMD2<Float>,
        direction: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        color: SIMD4<Float>,
        opacity: Float,
        trailLength: Float,
        shape: UInt32,
        fill: UInt32,
        depth: Float,
        radialVariation: Float = 0
    ) {
        self.position = Self.finite(position)
        self.direction = Self.normalized(direction)
        self.halfSize = Self.nonnegativeFinite(halfSize)
        positionPadding = .zero
        self.color = Self.finite(color)
        self.opacity = Self.clampedUnit(opacity)
        self.trailLength = max(0, trailLength.isFinite ? trailLength : 0)
        self.shape = shape
        self.fill = fill
        self.depth = depth.isFinite ? depth : 0
        self.radialVariation = radialVariation.isFinite
            ? min(max(radialVariation, -1), 1)
            : 0
        tailPadding1 = 0
        tailPadding2 = 0
    }

    private static func finite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func finite(_ value: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0,
            value.z.isFinite ? value.z : 0,
            value.w.isFinite ? value.w : 0
        )
    }

    private static func nonnegativeFinite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            value.x.isFinite ? max(value.x, 0) : 0,
            value.y.isFinite ? max(value.y, 0) : 0
        )
    }

    private static func normalized(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let finite = Self.finite(value)
        let length = simd_length(finite)
        return length > 0.000_001 ? finite / length : SIMD2(1, 0)
    }

    private static func clampedUnit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

struct DayObjectRenderActor: Equatable {
    let actorID: DayObjectActorID
    let eventID: String
    let gpuActor: DayObjectGPUActor

    var halfSize: SIMD2<Float> { gpuActor.halfSize }
    var opacity: Float { gpuActor.opacity }
    var trailLength: Float { gpuActor.trailLength }
    var depth: Float { gpuActor.depth }
}

struct DayObjectRenderFrame: Equatable {
    static let baseTempo = 0.8

    let choreographyTime: Double
    let actors: [DayObjectRenderActor]
    let postProcess: DayObjectPostProcess

    static func make(
        scene: DayObjectScene,
        environment: DayObjectEnvironment,
        elapsed rawElapsed: Double,
        insertions: [String: Double],
        removals: [String: Double] = [:],
        actorInsertions: [DayObjectActorID: Double] = [:],
        actorRemovals: [DayObjectActorID: Double] = [:],
        canvasAspect rawCanvasAspect: Double = 1
    ) -> DayObjectRenderFrame {
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let canvasAspect = rawCanvasAspect.isFinite && rawCanvasAspect > 0 ? rawCanvasAspect : 1
        let choreographyTime = elapsed * baseTempo * environment.tempoScale
        let postProcess = DayObjectPostProcess(
            visualClarity: environment.visualClarity,
            reduceMotion: environment.reduceMotion,
            grainSeed: scene.rootSeed,
            elapsed: elapsed
        )

        var actors = [DayObjectRenderActor]()
        actors.reserveCapacity(scene.actors.count)
        for actor in scene.actors {
            let pose = scene.score.pose(
                for: actor,
                at: choreographyTime,
                canvasAspect: canvasAspect,
                compositionPlan: scene.compositionPlan
            )
            let insertion: DayObjectInsertionEnvelope
            if let startedAt = actorInsertions[actor.id] ?? insertions[actor.eventID] {
                insertion = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
            } else {
                insertion = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let removal: DayObjectInsertionEnvelope
            if let startedAt = actorRemovals[actor.id] ?? removals[actor.eventID] {
                let forward = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
                removal = DayObjectInsertionEnvelope(
                    opacity: 1 - forward.opacity,
                    scale: 1 - 0.3 * forward.opacity
                )
            } else {
                removal = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let envelopeScale = environment.reduceMotion
                ? 1
                : insertion.scale * removal.scale
            let halfSize = bodyHalfSize(for: actor, pose: pose, envelopeScale: envelopeScale)
            let depth = Float(Double(pose.depthBand) + actor.zIndex * 0.001)
            let position = SIMD2<Float>(Float(pose.position.x), Float(pose.position.y))
            let direction = SIMD2<Float>(Float(pose.tangent.x), Float(pose.tangent.y))
            let rgba = SIMD4<Float>(color(for: actor, palette: scene.palette), 1)
            let gpuActor = DayObjectGPUActor(
                position: position,
                direction: direction,
                halfSize: halfSize,
                color: rgba,
                opacity: Float(pose.opacity * insertion.opacity * removal.opacity),
                trailLength: environment.reduceMotion ? 0 : Float(pose.trailReach),
                shape: numericShape(actor.shape),
                fill: numericFill(actor.fill),
                depth: depth,
                radialVariation: Float(
                    2 * stableUnit(actor.seed, salt: 0xD1B5_4A32_D192_ED03) - 1
                )
            )
            actors.append(DayObjectRenderActor(actorID: actor.id, eventID: actor.eventID, gpuActor: gpuActor))
        }
        actors.sort { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        }

        return DayObjectRenderFrame(
            choreographyTime: choreographyTime,
            actors: actors,
            postProcess: postProcess
        )
    }

    static func transitionDuration(for actor: DayObjectActor) -> Double {
        0.8 + 0.6 * stableUnit(actor.seed, salt: 0xC6BC_2796_92B5_CC83)
    }

    private static func bodyHalfSize(
        for actor: DayObjectActor,
        pose: DayObjectPose,
        envelopeScale: Double
    ) -> SIMD2<Float> {
        let aspect = DayObjectActorGeometry.aspectRatio(for: actor)
        let major = pose.scale * 0.5
        let baseHalfSize = SIMD2<Float>(Float(major), Float(major * aspect))
        return baseHalfSize * Float(envelopeScale)
    }

    private static func color(for actor: DayObjectActor, palette: DayObjectPalette) -> SIMD3<Float> {
        switch actor.role {
        case .focal, .satellite:
            return palette.figurePrimary
        case .support, .bridge:
            return palette.figureSecondary
        case .accent:
            return palette.accent
        }
    }

    private static func numericShape(_ shape: DayObjectShape) -> UInt32 {
        UInt32(DayObjectShape.allCases.firstIndex(of: shape) ?? 0)
    }

    private static func numericFill(_ fill: DayObjectFill) -> UInt32 {
        UInt32(DayObjectFill.allCases.firstIndex(of: fill) ?? 0)
    }

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ salt
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
